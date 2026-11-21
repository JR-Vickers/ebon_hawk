extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var room: Node = load("res://scenes/placeholder_room.tscn").instantiate()
	root.add_child(room)
	var controller: Node = room.get_node("ConsoleController")
	controller._build_ui()
	controller.last_rows = [
		{"id": 11, "pid": 100, "app": "Editor", "title": "Document", "on_screen": false, "picker_eligible": true},
		{"id": 12, "pid": 100, "app": "Editor", "title": "Untitled", "on_screen": false, "picker_eligible": false},
		{"id": 13, "pid": 200, "app": "Other", "title": "Untitled", "on_screen": true, "picker_eligible": true},
	]
	var sample := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	sample.fill(Color.RED)
	if controller._decode_icon(sample.save_png_to_buffer()) == null or controller._decode_icon(PackedByteArray()) != null:
		push_error("Application icon decoding or fallback failed")
		quit(1)
		return
	controller._populate_windows()
	if controller.item_ids != [11, 13]:
		push_error("Default picker did not retain ordinary windows and hide helpers")
		quit(1)
		return
	controller.show_all_windows.button_pressed = true
	if controller.item_ids != [11, 12, 13]:
		push_error("Show all did not restore hidden windows")
		quit(1)
		return
	controller.slots = [{"original_pid": 100}]
	controller.task_picker = true
	controller.show_all_windows.button_pressed = false
	controller._populate_windows()
	if controller.item_ids != [11, 12]:
		push_error("Task picker must include auxiliary windows only from the assigned process")
		quit(1)
		return
	controller.slots.clear()
	print("Window picker checks: PASS")
	room.queue_free()
	await process_frame
	quit()
