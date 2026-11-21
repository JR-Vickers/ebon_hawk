extends Node

const Selector = preload("res://scripts/source_selector.gd")
const SETTINGS_PATH = "user://console_assignments.json"
const Mapping = preload("res://scripts/console_surface_mapping.gd")
const ScreenShader = preload("res://scripts/console_screen.gdshader")
enum Mode { NAVIGATION, PICKER, INTERACTING, PAUSED }
var mode: Mode = Mode.NAVIGATION
var native = null
var extension = null
var texture: ImageTexture
var material: ShaderMaterial
var content_pixels := Rect2()
var camera_before := Transform3D.IDENTITY
var mouse_passthrough_before := false
var camera_fov_before := 75.0
var selected_label := "No source assigned"
var source_state := "unassigned"
var click_trace := ""
var pointer_direct := 0
var pointer_posted := 0
var pointer_rejected := 0
var last_message := ""
var last_native_message := ""
var last_diagnostic_state := ""
var refresh_clock: float = 0.0
var release_key: int = 62 # macOS Right Control; picker offers F12 (111).
var panel: PanelContainer
var list: ItemList
var permission_label: Label
var release_choice: OptionButton
var hint: Label
var pointer: Label
var item_ids: Array[int] = []
var last_rows: Array = []
var app_icons: Dictionary = {}
var slots: Array = []
var current_slot := 0
var nearby := false
var saved_selectors: Dictionary = {}
var quality := 1920
var restore_pending := true
var restore_attempts := 0
var quality_choice: OptionButton
var show_all_windows: CheckBox
var task_picker := false
var task_button: Button
var return_button: Button

@onready var pause_screen: CanvasLayer = get_parent().get_node("PauseScreen")
@onready var player = get_parent().get_node("Player")
@onready var camera: Camera3D = player.get_node("Camera3D")
var console: Node3D
var screen: MeshInstance3D
var status_label: Label3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if get_parent().has_meta("defer_console_start"):
		return
	start_sessions()

func start_sessions() -> void:
	# Physics tests and non-native machines retain the working M0 environment.
	if DisplayServer.get_name() == "headless":
		return
	_build_ui()
	get_parent().get_node("HUD/Instructions").text = "EBON HAWK DESKTOP / WINDOW PROTOTYPE\nWASD move | Mouse look | Esc pause / resume | R reset\nNear console: P choose source / permissions | E interact\nDuring interaction: Right Control (or F12) / Esc releases | Cmd+Q quits Godot"
	if OS.get_name() == "macOS" and FileAccess.file_exists("res://native/bin/libebon_hawk.dylib"):
		extension = load("res://native/ebon_hawk.gdextension")
		if extension != null and ClassDB.class_exists("EbonHawkNative"):
			native = ClassDB.instantiate("EbonHawkNative")
	if native == null:
		last_message = "Native bridge unavailable. Run: python3 tools/dev.py native"
	_load_settings()
	var seen_ids := {}
	for node in get_tree().get_nodes_in_group("consoles"):
		if not get_parent().is_ancestor_of(node):
			continue
		var id: String = node.get_meta("console_id", "")
		if id.is_empty() or seen_ids.has(id):
			push_error("Console ID is empty or duplicated: " + id)
			continue
		seen_ids[id] = true
		var backend = ClassDB.instantiate("EbonHawkNative") if native != null else null
		var mat := ShaderMaterial.new()
		mat.shader = ScreenShader
		slots.append({"console": node, "native": backend, "material": mat, "texture": null,
			"content": Rect2(), "state": "unassigned", "label": "No source assigned"})
		if backend != null:
			backend.refresh_windows()
		else:
			node.get_node("Status").text = "%s / UNAVAILABLE\nNative bridge unavailable" % id
	if native != null:
		native.stop()
	if not slots.is_empty():
		_select_slot(0)
	_update_hint()

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hint = Label.new()
	hint.position = Vector2(24, 132)
	hint.add_theme_font_size_override("font_size", 18)
	canvas.add_child(hint)
	pointer = Label.new()
	pointer.text = "+"
	pointer.modulate = Color.ORANGE
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer.visible = false
	canvas.add_child(pointer)
	panel = PanelContainer.new()
	panel.position = Vector2(40, 210)
	panel.custom_minimum_size = Vector2(780, 440)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	permission_label = Label.new()
	permission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(permission_label)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	for entry in [["Request permissions", _request_permissions], ["Refresh windows", _refresh_windows], ["Close / Esc", _close_picker]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		buttons.add_child(button)
	task_button = Button.new()
	task_button.text = "Choose task window from this app"
	task_button.pressed.connect(_open_task_picker)
	buttons.add_child(task_button)
	return_button = Button.new()
	return_button.text = "Return to assigned source"
	return_button.pressed.connect(_return_to_source)
	buttons.add_child(return_button)
	release_choice = OptionButton.new()
	release_choice.add_item("Release: Right Control", 62)
	release_choice.add_item("Release: F12 (Fn+F12 on some keyboards)", 111)
	release_choice.item_selected.connect(func(index: int):
		release_key = release_choice.get_item_id(index)
		_save_settings())
	column.add_child(release_choice)
	quality_choice = OptionButton.new()
	quality_choice.add_item("Capture quality: High", 1920)
	quality_choice.add_item("Capture quality: Medium", 1280)
	quality_choice.add_item("Capture quality: Low", 800)
	quality_choice.item_selected.connect(func(index: int):
		quality = quality_choice.get_item_id(index)
		_save_settings()
		_update_quality())
	column.add_child(quality_choice)
	show_all_windows = CheckBox.new()
	show_all_windows.text = "Show background and helper windows"
	show_all_windows.toggled.connect(func(_pressed: bool): _populate_windows())
	column.add_child(show_all_windows)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(760, 260)
	list.fixed_icon_size = Vector2i(24, 24)
	list.item_activated.connect(_choose_window)
	column.add_child(list)
	var choose := Button.new()
	choose.text = "Capture selected window (or double-click a row)"
	choose.pressed.connect(func():
		var selected := list.get_selected_items()
		if not selected.is_empty():
			_choose_window(selected[0]))
	column.add_child(choose)
	panel.hide()

func _select_slot(index: int) -> void:
	if not slots.is_empty() and current_slot < slots.size():
		slots[current_slot].texture = texture
		slots[current_slot].content = content_pixels
		slots[current_slot].state = source_state
		slots[current_slot].label = selected_label
	current_slot = index
	var slot: Dictionary = slots[index]
	console = slot.console
	screen = console.get_node("Screen")
	status_label = console.get_node("Status")
	native = slot.native
	material = slot.material
	texture = slot.texture
	content_pixels = slot.content
	source_state = slot.state
	selected_label = slot.label

func _near_console() -> bool:
	var nearest := -1
	var distance := 4.0
	var aimed := false
	for i in slots.size():
		var target: Node3D = slots[i].console.get_node_or_null("InteractionPoint")
		var point: Vector3 = target.global_position if target != null else slots[i].console.global_position
		var d: float = player.global_position.distance_to(point)
		if d >= 4.0:
			continue
		var target_screen: MeshInstance3D = slots[i].console.get_node("Screen")
		var facing: Vector3 = target_screen.global_basis.z.normalized()
		if facing.dot(camera.global_position - slots[i].console.get_node("Screen").global_position) <= 0.0:
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, slots[i].console.get_node("Screen").global_position)
		query.exclude = [player.get_rid()]
		var obstruction: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		if not obstruction.is_empty() and obstruction.position.distance_to(query.to) > float(slots[i].console.get_meta("sight_tolerance", 0.15)):
			continue
		var uv := Mapping.surface_uv(camera, target_screen, get_viewport().get_visible_rect().size * 0.5)
		var is_aimed := Rect2(0, 0, 1, 1).has_point(uv)
		if (is_aimed and not aimed) or (is_aimed == aimed and d < distance):
			aimed = is_aimed
			distance = d
			nearest = i
	if nearest >= 0 and mode == Mode.NAVIGATION:
		_select_slot(nearest)
	return nearest >= 0

func _load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if parsed is Dictionary and parsed.get("version") == 1:
			if parsed.get("assignments") is Dictionary:
				saved_selectors = parsed.assignments
			if parsed.get("quality") in [800, 1280, 1920]:
				quality = parsed.quality
			if parsed.get("release_key") in [62, 111]:
				release_key = parsed.release_key
	quality_choice.select([1920, 1280, 800].find(quality))
	release_choice.select(0 if release_key == 62 else 1)

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		last_message = "Could not save console settings."
		return
	file.store_string(JSON.stringify({"version": 1, "assignments": saved_selectors, "quality": quality, "release_key": release_key}))

func _update_quality() -> void:
	for i in slots.size():
		if slots[i].native != null:
			var active := mode == Mode.INTERACTING and i == current_slot
			slots[i].native.set_quality(quality, 30 if active else 10)

func _input(event: InputEvent) -> void:
	var escape_pressed: bool = event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed and not event.echo
	if mode == Mode.PAUSED or (mode == Mode.NAVIGATION and escape_pressed):
		if escape_pressed:
			var entering := mode == Mode.NAVIGATION
			mode = Mode.PAUSED if entering else Mode.NAVIGATION
			player.set_navigation(not entering)
			pause_screen.visible = entering
			get_tree().paused = entering
		get_viewport().set_input_as_handled()
		return
	if hint == null:
		return
	if mode == Mode.INTERACTING:
		# Physical native events are consumed by the tap, not forwarded twice here.
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if mode == Mode.PICKER and event.keycode == KEY_ESCAPE:
			_close_picker()
		elif mode == Mode.NAVIGATION and _near_console() and event.physical_keycode == KEY_P:
			_open_picker()
		elif mode == Mode.NAVIGATION and _near_console() and event.physical_keycode == KEY_E:
			_enter_console()
		else:
			return
		get_viewport().set_input_as_handled()

func _open_picker() -> void:
	task_picker = false
	_show_picker()

func _show_picker() -> void:
	mode = Mode.PICKER
	player.controls_locked = true
	player.set_navigation(false)
	panel.show()
	_refresh_windows()
	_update_permissions()
	_populate_windows()

func _open_task_picker() -> void:
	if native == null or slots.is_empty():
		return
	var state: Dictionary = native.status()
	if not slots[current_slot].has("original_id"):
		if state.window_id == 0 or state.window_pid == 0:
			last_message = "Choose an assigned source before selecting a task window."
			return
		slots[current_slot].original_id = state.window_id
		slots[current_slot].original_pid = state.window_pid
	task_picker = true
	_populate_windows()
	_refresh_windows()

func _return_to_source() -> void:
	if native == null or slots.is_empty() or not slots[current_slot].has("original_id"):
		last_message = "No temporary task window is selected."
		return
	var original: int = slots[current_slot].original_id
	var pid: int = slots[current_slot].original_pid
	var found := false
	for row: Dictionary in last_rows:
		if row.id == original and row.get("pid", 0) == pid:
			found = true
	if found and native.select_window(original):
		slots[current_slot].erase("original_id")
		slots[current_slot].erase("original_pid")
		texture = null
		task_picker = false
		_close_picker()
		last_message = "Returned to assigned source; wait for a live frame."
	else:
		last_message = "Original source unavailable. Refresh, or choose a source with P."

func _close_picker() -> void:
	panel.hide()
	mode = Mode.NAVIGATION
	player.controls_locked = false
	player.set_navigation(false) # Explicit click resumes, as in M0.

func _request_permissions() -> void:
	if native != null:
		native.request_permissions()
	_update_permissions()

func _update_permissions() -> void:
	if native == null:
		permission_label.text = "Native bridge unavailable. Build it and restart Godot."
		return
	var p: Dictionary = native.permissions()
	permission_label.text = "Screen Recording: %s | Accessibility: %s | Input Monitoring: %s\nSystem Settings > Privacy & Security: enable each for the Godot application running this scene.\nRestart Godot after grants. Then Refresh. Input Monitoring is required by the reserved-key event tap.\nChoose an ordinary app window; ambiguous Accessibility matches are refused." % [p.capture, p.accessibility, p.listen]

func _refresh_windows() -> void:
	if native != null:
		native.refresh_windows()

func _choose_window(index: int) -> void:
	if native != null and index >= 0 and index < item_ids.size():
		_leave_console()
		if native.select_window(item_ids[index]):
			slots[current_slot].restored = true
			slots[current_slot].erase("restore_error")
			selected_label = list.get_item_text(index)
			texture = null
			if not task_picker:
				slots[current_slot].erase("original_id")
				slots[current_slot].erase("original_pid")
				for row: Dictionary in last_rows:
					if row.id == item_ids[index]:
						saved_selectors[console.get_meta("console_id")] = Selector.selector_for(row)
						_save_settings()
						break
			_update_quality()
			_close_picker()
		else:
			last_message = "Capture selection failed; check permissions and refresh."

func _enter_console() -> void:
	if native == null:
		last_message = "Native bridge unavailable. Build it, restart Godot, then P to choose a window."
		return
	if texture == null or source_state != "live":
		last_message = "Choose a window with P and wait for a live frame."
		return
	player.controls_locked = true
	player.set_navigation(false)
	camera_before = camera.global_transform
	camera_fov_before = camera.fov
	camera.fov = 45.0
	camera.global_transform = console.get_node("ViewPose").global_transform
	var handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	mouse_passthrough_before = DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH)
	if native.begin_interaction(handle, release_key):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
		mode = Mode.INTERACTING
		_update_quality()
		pointer.position = get_viewport().get_visible_rect().size * 0.5 - pointer.size * 0.5
		pointer.show()
	else:
		camera.global_transform = camera_before
		camera.fov = camera_fov_before
		player.controls_locked = false
		last_message = native.status().message

func _leave_console() -> void:
	if native != null:
		native.end_interaction()
	if mode == Mode.INTERACTING:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, mouse_passthrough_before)
		camera.global_transform = camera_before
		camera.fov = camera_fov_before
		mode = Mode.NAVIGATION
		player.controls_locked = false
		player.set_navigation(false)
		pointer.hide()
		_update_quality()

func _process(delta: float) -> void:
	if mode == Mode.PAUSED or hint == null:
		return
	if mode == Mode.NAVIGATION and not slots.is_empty():
		nearby = _near_console()
	if native != null and not slots.is_empty():
		var selected_index := current_slot
		for i in slots.size():
			if i == selected_index:
				continue
			_select_slot(i)
			var other_state: Dictionary = native.status()
			source_state = other_state.state
			selected_label = other_state.label
			_apply_restore_error()
			var other_frame: Dictionary = native.take_frame()
			if not other_frame.is_empty():
				_update_frame(other_frame)
			_update_screen_state()
		_select_slot(selected_index)
		var state: Dictionary = native.status()
		source_state = state.state
		if source_state != last_diagnostic_state:
			print("Capture state: ", source_state)
			last_diagnostic_state = source_state
		if state.click_trace != click_trace:
			click_trace = state.click_trace
			if not click_trace.is_empty():
				print(click_trace)
		pointer_direct = state.pointer_direct
		pointer_posted = state.pointer_posted
		pointer_rejected = state.pointer_rejected
		selected_label = state.label
		_apply_restore_error()
		if state.message != last_native_message:
			last_native_message = state.message
			last_message = state.message
		if mode == Mode.INTERACTING and not state.interacting and not state.interaction_pending:
			var message: String = state.message
			print("Interaction ended: ", message)
			print("Key repeat: AppKit delay=%s interval=%s; generated=%d fallback posted=%d native posted=%d" % [
				state.repeat_delay, state.repeat_interval, state.repeat_generated,
				state.repeat_fallback_posted, state.repeat_native_posted])
			_leave_console()
			last_message = message
			if message == "quit requested":
				get_tree().quit()
		var frame: Dictionary = native.take_frame()
		if not frame.is_empty():
			_update_frame(frame)
		if mode == Mode.INTERACTING:
			for event: Dictionary in native.poll_input():
				var target_point := Vector2(event.x, event.y)
				if not event.key:
					var bounds: Array = state.window_rect
					var window := Rect2(bounds[0], bounds[1], bounds[2], bounds[3])
					if window.has_area() and content_pixels.has_area():
						var position := Mapping.console_pointer(camera, screen, target_point, window, content_pixels.size)
						pointer.position = position - pointer.size * 0.5
					else:
						target_point = Vector2(INF, INF)
				var forwarded: bool = native.forward_event(event.id, target_point)
				if not forwarded:
					if not native.status().interacting:
						break
		refresh_clock += delta
		if refresh_clock > 0.5:
			refresh_clock = 0
			if mode == Mode.PICKER:
				_update_permissions()
				_refresh_windows()
				var rows: Array = native.windows()
				if rows != last_rows:
					last_rows = rows.duplicate(true)
					_populate_windows()
		_update_screen_state()
		if restore_pending and refresh_clock == 0 and mode == Mode.NAVIGATION:
			_restore_assignments()
	_update_hint()

func _populate_windows() -> void:
	if list == null:
		return
	list.clear()
	item_ids.clear()
	for row: Dictionary in last_rows:
		if task_picker and row.get("pid", 0) != slots[current_slot].get("original_pid", 0):
			continue
		if not task_picker and not show_all_windows.button_pressed and not row.get("picker_eligible", true):
			continue
		item_ids.append(row.id)
		list.add_item("%s — %s [window %s]%s" % [row.app, row.title, row.id, "" if row.on_screen else " (off screen / other Space)"], _window_icon(row))

func _window_icon(row: Dictionary) -> Texture2D:
	var pid: int = row.get("pid", 0)
	if pid <= 0 or native == null or not native.has_method("application_icon"):
		return null
	var key := "%s:%s" % [pid, row.get("bundle_id", "")]
	if app_icons.has(key):
		return app_icons[key]
	var png: PackedByteArray = native.application_icon(pid)
	var icon := _decode_icon(png)
	app_icons[key] = icon
	return icon

func _decode_icon(png: PackedByteArray) -> Texture2D:
	if png.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(png) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _apply_restore_error() -> void:
	if slots[current_slot].has("restore_error"):
		source_state = slots[current_slot].restore_error
		selected_label = "Saved source %s; press P to reassign" % source_state

func _update_screen_state() -> void:
	if source_state != "live":
		screen.material_override = null
		status_label.show()
		status_label.text = "%s / %s\n%s" % [console.get_meta("console_id"), source_state.to_upper(), selected_label]
	else:
		status_label.hide()

func _restore_assignments() -> void:
	restore_attempts += 1
	var pending := false
	var previous := current_slot
	for i in slots.size():
		_select_slot(i)
		var id: String = console.get_meta("console_id")
		if not saved_selectors.has(id) or slots[i].get("restored", false):
			continue
		var rows: Array = native.windows()
		var result: Dictionary = Selector.resolve(saved_selectors[id], rows)
		if result.state == "resolved" and native.select_window(result.id):
			slots[i].restored = true
		elif restore_attempts < 10 and rows.is_empty():
			pending = true
		else:
			slots[i].restored = true
			slots[i].restore_error = result.state
			_apply_restore_error()
	_select_slot(previous)
	restore_pending = pending
	_update_quality()

func _update_frame(frame: Dictionary) -> void:
	var image := Image.create_from_data(frame.width, frame.height, false, Image.FORMAT_RGBA8, frame.rgba)
	if texture == null or texture.get_size() != Vector2(image.get_size()):
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	var rect: Array = frame.content_pixels
	content_pixels = Rect2(rect[0], rect[1], rect[2], rect[3])
	var size := Mapping.surface_size(screen)
	var fitted: Rect2 = Mapping.fitted_rect(size, content_pixels.size)
	material.set_shader_parameter("frame_texture", texture)
	material.set_shader_parameter("content_uv", Vector4(content_pixels.position.x / image.get_width(), content_pixels.position.y / image.get_height(), content_pixels.size.x / image.get_width(), content_pixels.size.y / image.get_height()))
	material.set_shader_parameter("fitted_uv", Vector4(fitted.position.x / size.x, fitted.position.y / size.y, fitted.size.x / size.x, fitted.size.y / size.y))
	screen.material_override = material

func _update_hint() -> void:
	if mode == Mode.NAVIGATION and not nearby:
		hint.text = "No nearby console"
		return
	if mode == Mode.INTERACTING:
		hint.text = "%s | %s\nINTERACTING — %s / Esc releases; Cmd+Q quits Godot\nPointer events posted: %d (%d direct) | not posted: %d" % [selected_label, source_state, "Right Control" if release_key == 62 else "F12", pointer_posted, pointer_direct, pointer_rejected] + "\n" + click_trace
	else:
		hint.text = "%s | %s | %s\n%s" % [console.get_meta("console_id") if console != null and nearby else "No nearby console", selected_label, source_state, last_message]

func shutdown_sessions() -> void:
	_leave_console()
	for slot in slots:
		if slot.native != null:
			slot.native.stop()
	slots.clear()
	native = null

func _exit_tree() -> void:
	if mode == Mode.PAUSED:
		get_tree().paused = false
	shutdown_sessions()
