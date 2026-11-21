extends Node

# This host stays alive while the ship scene is replaced. Changes to this file
# and native code require a process restart; game resources are reloadable.
const SHIP_SCENE := "res://scenes/ship.tscn"
const ENDPOINT := "res://build/ship-reload.json"
const WATCHED := ["res://scripts", "res://scenes", "res://assets/generated/ship", "res://assets/generated/ship_audio"]
const RESTART_WATCHED := ["res://native/src", "res://native/bin", "res://native/CMakeLists.txt", "res://native/ebon_hawk.gdextension", "res://project.godot", "res://scripts/ship_reload_host.gd", "res://scenes/ship_reload_host.tscn"]
const QUIET_SECONDS := 2.0

var ship: Node
var request_path := ""
var snapshot := {}
var restart_snapshot := {}
var elapsed := 0.0
var quiet := 0.0
var pending := false
var validating := false
var validation_thread := Thread.new()
var validation_result: Array = []
var revision := 0
var validating_revision := 0
var restart_required := false
var status: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(24, 92)
	status.add_theme_font_size_override("font_size", 18)
	canvas.add_child(status)
	ship = load(SHIP_SCENE).instantiate()
	add_child(ship)
	snapshot = _snapshot(WATCHED)
	restart_snapshot = _snapshot(RESTART_WATCHED)
	request_path = "res://build/ship-reload-request-%d" % OS.get_process_id()
	if not has_meta("reload_test"):
		_write_heartbeat()
	_set_status("T reloads the ship | Changes reload automatically when idle")

func _write_heartbeat() -> void:
	var temporary := ENDPOINT + ".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_set_status("Reload command unavailable: cannot write endpoint")
		return
	file.store_string(JSON.stringify({"heartbeat": Time.get_unix_time_from_system(), "pid": OS.get_process_id()}))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(ENDPOINT))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T and _is_idle():
		_request_reload()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if FileAccess.file_exists(request_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))
		_request_reload()
	elapsed += delta
	if elapsed >= 0.5:
		elapsed = 0.0
		if not has_meta("reload_test"):
			_write_heartbeat()
		var next := _snapshot(WATCHED)
		if next != snapshot:
			snapshot = next
			_request_reload()
		var next_restart := _snapshot(RESTART_WATCHED)
		if next_restart != restart_snapshot:
			restart_snapshot = next_restart
			restart_required = true
			_set_status("Reload host or native code changed: restart the ship preview")
	if pending:
		quiet += delta
		if quiet >= QUIET_SECONDS and _is_idle() and not validating:
			_start_validation()
	if validating and not validation_thread.is_alive():
		validation_thread.wait_to_finish()
		validating = false
		if validating_revision != revision:
			return
		if validation_result[0] != 0:
			pending = false
			_set_status("Reload failed validation; the current ship is unchanged. See build/ship-reload-validation.log")
		elif _is_idle():
			pending = false
			_replace_ship()
		else:
			_set_status("Reload ready; waiting until console interaction ends")

func _request_reload() -> void:
	revision += 1
	pending = true
	quiet = 0.0
	_set_status("Reload queued" if _is_idle() else "Reload queued until console interaction ends")

func _is_idle() -> bool:
	if ship == null:
		return false
	var player := ship.get_node_or_null("Player")
	var controller := ship.get_node_or_null("ConsoleController")
	return player != null and not player.get("controls_locked") and (controller == null or controller.mode == controller.Mode.NAVIGATION)

func _start_validation() -> void:
	validating = true
	validating_revision = revision
	_set_status("Checking ship before reload…")
	validation_thread.start(_validate.bind(ProjectSettings.globalize_path("res://")))

func _validate(root: String) -> void:
	var output := []
	var result := OS.execute("python3", [root.path_join("tools/dev.py"), "reload-validate"], output, true)
	var file := FileAccess.open(root.path_join("build/ship-reload-validation.log"), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(output))
	validation_result = [result]

func _replace_ship() -> void:
	var old_audio := ship.get_node_or_null("ShipAudio")
	var music_on: bool = old_audio.music_enabled if old_audio != null else false
	var ambience_on: bool = old_audio.ambience_enabled if old_audio != null else true
	var old_player := ship.get_node("Player") as CharacterBody3D
	var old_transform := old_player.global_transform
	var old_camera := old_player.get_node("Camera3D") as Camera3D
	var old_rotation := old_camera.rotation
	var old_fov := old_camera.fov
	var old_navigation: bool = old_player.navigation_enabled
	var old_mouse := Input.mouse_mode
	var packed := ResourceLoader.load(SHIP_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null:
		_set_status("Reload failed to load scene; the current ship is unchanged")
		return
	var candidate := packed.instantiate()
	if candidate == null:
		_set_status("Reload failed to instantiate scene; the current ship is unchanged")
		return
	candidate.set_meta("defer_console_start", true)
	add_child(candidate)
	if not candidate.get("material_errors").is_empty():
		candidate.queue_free()
		Input.mouse_mode = old_mouse
		_set_status("Reload failed to load materials; the current ship is unchanged")
		return
	var new_player := candidate.get_node_or_null("Player") as CharacterBody3D
	if new_player == null or new_player.get_node_or_null("Camera3D") == null:
		candidate.queue_free()
		Input.mouse_mode = old_mouse
		_set_status("Reloaded scene has no player or camera; current ship is unchanged")
		return
	new_player.global_transform = old_transform
	new_player.get_node("Camera3D").rotation = old_rotation
	new_player.get_node("Camera3D").fov = old_fov
	new_player.set_navigation(old_navigation)
	Input.mouse_mode = old_mouse
	var old_controller := ship.get_node_or_null("ConsoleController")
	if old_controller != null:
		old_controller.shutdown_sessions()
	remove_child(ship)
	ship.queue_free()
	ship = candidate
	candidate.remove_meta("defer_console_start")
	var audio := candidate.get_node_or_null("ShipAudio")
	if audio != null:
		audio.start_audio()
		audio.set_enabled(music_on, ambience_on)
	var new_controller := candidate.get_node_or_null("ConsoleController")
	if new_controller != null:
		new_controller.start_sessions()
	_set_status("Ship reloaded")

func _snapshot(paths: Array) -> Dictionary:
	var result := {}
	for path in paths:
		_collect(path, result, paths == WATCHED)
	return result

func _collect(path: String, result: Dictionary, skip_host: bool) -> void:
	if DirAccess.dir_exists_absolute(path):
		var directory := DirAccess.open(path)
		if directory == null:
			return
		for name in directory.get_files():
			if not name.ends_with(".import") and not name.ends_with(".uid") and not name.ends_with(".blend") and not name.ends_with(".blend1"):
				_collect(path.path_join(name), result, skip_host)
		for name in directory.get_directories():
			_collect(path.path_join(name), result, skip_host)
	elif FileAccess.file_exists(path):
		if skip_host and paths_are_restart_only(path):
			return
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var signature := ""
			if path.ends_with(".gd") or path.ends_with(".tscn") or path.ends_with(".gdshader"):
				signature = FileAccess.get_sha256(path)
			result[path] = [FileAccess.get_modified_time(path), file.get_length(), signature]

func paths_are_restart_only(path: String) -> bool:
	# The reload host must never attempt to replace its own live code or scene.
	return path == "res://scripts/ship_reload_host.gd" or path == "res://scenes/ship_reload_host.tscn"

func _set_status(message: String) -> void:
	if status != null:
		status.text = message + (" | Restart required for host/native changes" if restart_required else "")
	print("Ship reload: ", message)

func _exit_tree() -> void:
	if validation_thread.is_started():
		validation_thread.wait_to_finish()
	if FileAccess.file_exists(request_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))
	if FileAccess.file_exists(ENDPOINT):
		var endpoint = JSON.parse_string(FileAccess.get_file_as_string(ENDPOINT))
		if endpoint is Dictionary and endpoint.get("pid") == OS.get_process_id():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(ENDPOINT))
