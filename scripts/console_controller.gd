extends Node

const Mapping = preload("res://scripts/console_mapping.gd")
const ScreenShader = preload("res://scripts/console_screen.gdshader")
enum Mode { NAVIGATION, PICKER, INTERACTING }
var mode: Mode = Mode.NAVIGATION
var native = null
var extension = null
var texture: ImageTexture
var material: ShaderMaterial
var content_pixels := Rect2()
var camera_before := Transform3D.IDENTITY
var selected_label := "No source assigned"
var source_state := "unassigned"
var last_message := ""
var last_native_message := ""
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
@onready var player = get_parent().get_node("Player")
@onready var camera: Camera3D = player.get_node("Camera3D")
@onready var console = get_parent().get_node("Console")
@onready var screen: MeshInstance3D = console.get_node("Screen")
@onready var status_label: Label3D = console.get_node("Status")

func _ready() -> void:
	# Physics tests and non-native machines retain the working M0 environment.
	if DisplayServer.get_name() == "headless":
		return
	_build_ui()
	get_parent().get_node("HUD/Instructions").text = "EBON HAWK DESKTOP / WINDOW PROTOTYPE\nWASD move | Mouse look | Esc release mouse | R reset\nNear console: P choose source / permissions | E interact\nDuring interaction: Right Control (or F12) / Esc releases | Cmd+Q quits Godot"
	if OS.get_name() == "macOS" and FileAccess.file_exists("res://native/bin/libebon_hawk.dylib"):
		extension = load("res://native/ebon_hawk.gdextension")
		if extension != null and ClassDB.class_exists("EbonHawkNative"):
			native = ClassDB.instantiate("EbonHawkNative")
	if native == null:
		last_message = "Native bridge unavailable. Run: python3 tools/dev.py native"
	material = ShaderMaterial.new()
	material.shader = ScreenShader
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
	release_choice = OptionButton.new()
	release_choice.add_item("Release: Right Control", 62)
	release_choice.add_item("Release: F12 (Fn+F12 on some keyboards)", 111)
	release_choice.item_selected.connect(func(index: int): release_key = release_choice.get_item_id(index))
	column.add_child(release_choice)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(760, 260)
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

func _near_console() -> bool:
	return player.global_position.distance_to(console.global_position) < 4.0

func _input(event: InputEvent) -> void:
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
	mode = Mode.PICKER
	player.controls_locked = true
	player.set_navigation(false)
	panel.show()
	_refresh_windows()
	_update_permissions()

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
			selected_label = list.get_item_text(index)
			texture = null
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
	camera.global_transform = console.get_node("ViewPose").global_transform
	var handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if native.begin_interaction(handle, release_key):
		mode = Mode.INTERACTING
		pointer.show()
	else:
		camera.global_transform = camera_before
		player.controls_locked = false
		last_message = native.status().message

func _leave_console() -> void:
	if native != null:
		native.end_interaction()
	if mode == Mode.INTERACTING:
		camera.global_transform = camera_before
		mode = Mode.NAVIGATION
		player.controls_locked = false
		player.set_navigation(false)
		pointer.hide()

func _process(delta: float) -> void:
	if hint == null:
		return
	if native != null:
		var state: Dictionary = native.status()
		source_state = state.state
		selected_label = state.label
		if state.message != last_native_message:
			last_native_message = state.message
			last_message = state.message
		if mode == Mode.INTERACTING and not state.interacting:
			var message: String = state.message
			_leave_console()
			last_message = message
			if message == "quit requested":
				get_tree().quit()
		var frame: Dictionary = native.take_frame()
		if not frame.is_empty():
			_update_frame(frame)
		if mode == Mode.INTERACTING:
			for event: Dictionary in native.poll_input():
				var uv := Vector2(-1, -1)
				if not event.key and event.view_width > 0 and event.view_height > 0:
					var position := Vector2(event.x / event.view_width, event.y / event.view_height) * get_viewport().get_visible_rect().size
					pointer.position = position - Vector2(5, 12)
					uv = Mapping.normalized(Mapping.surface_uv(camera, screen, position), content_pixels.size)
				var target_point := Vector2(INF, INF)
				if uv.x >= 0 and uv.y >= 0:
					var window: Array = state.window_rect
					target_point = Mapping.native_point(Mapping.capture_pixel(uv, content_pixels), content_pixels, Rect2(window[0], window[1], window[2], window[3]))
				# Invalid points drop downs/motion; native still releases a held button on up.
				if not native.forward_event(event.id, target_point):
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
					list.clear()
					item_ids.clear()
					for row: Dictionary in rows:
						item_ids.append(row.id)
						list.add_item("%s — %s [window %s]%s" % [row.app, row.title, row.id, "" if row.on_screen else " (off screen / other Space)"])
		if source_state != "live":
			screen.material_override = null
			status_label.show()
			status_label.text = "CONSOLE 01 / %s\n%s" % [source_state.to_upper(), selected_label]
		else:
			status_label.hide()
	_update_hint()

func _update_frame(frame: Dictionary) -> void:
	var image := Image.create_from_data(frame.width, frame.height, false, Image.FORMAT_RGBA8, frame.rgba)
	if texture == null or texture.get_size() != Vector2(image.get_size()):
		texture = ImageTexture.create_from_image(image)
	else:
		texture.update(image)
	var rect: Array = frame.content_pixels
	content_pixels = Rect2(rect[0], rect[1], rect[2], rect[3])
	var fitted: Rect2 = Mapping.fitted_rect(Vector2(2, 1), content_pixels.size)
	material.set_shader_parameter("frame_texture", texture)
	material.set_shader_parameter("content_uv", Vector4(content_pixels.position.x / image.get_width(), content_pixels.position.y / image.get_height(), content_pixels.size.x / image.get_width(), content_pixels.size.y / image.get_height()))
	material.set_shader_parameter("fitted_uv", Vector4(fitted.position.x / 2, fitted.position.y, fitted.size.x / 2, fitted.size.y))
	screen.material_override = material

func _update_hint() -> void:
	if mode == Mode.INTERACTING:
		hint.text = "%s | %s\nINTERACTING — %s / Esc releases; Cmd+Q quits Godot" % [selected_label, source_state, "Right Control" if release_key == 62 else "F12"]
	else:
		hint.text = "%s | %s\n%s" % [selected_label, source_state, last_message]

func _exit_tree() -> void:
	if native != null:
		native.stop()
		native = null
