extends SceneTree

var failures: int = 0

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var room = load("res://scenes/placeholder_room.tscn").instantiate()
	root.add_child(room)
	var player = room.get_node("Player")
	await frames(60)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	expect(paused and room.get_node("PauseScreen").visible and not player.can_process(), "Escape pauses physics and shows pause screen")
	escape.echo = true
	root.push_input(escape)
	expect(paused, "Holding Escape keeps the game paused")
	escape.echo = false
	escape.pressed = false
	root.push_input(escape)
	escape.pressed = true
	root.push_input(escape)
	expect(not paused and not room.get_node("PauseScreen").visible and player.navigation_enabled, "Second Escape resumes navigation")
	expect(player.is_on_floor(), "Spawn must settle on the floor")
	expect(player.position.distance_to(room.get_node("Spawn").position) < 0.1, "Spawn is clear of geometry")
	expect(room.get_node("Console").get_meta("console_id") == "placeholder_console_01", "Console ID must remain stable")
	Input.action_press("move_forward")
	await frames(180)
	Input.action_release("move_forward")
	expect(player.position.z > -2.31 and player.position.z < -2.1, "Walking forward stops at console collision")
	player.reset_to_spawn()
	Input.action_press("move_right")
	await frames(180)
	Input.action_release("move_right")
	expect(player.position.x > 5.3 and player.position.x < 5.51, "Side wall contains player")
	player.reset_to_spawn()
	Input.action_press("move_back")
	await frames(120)
	Input.action_release("move_back")
	expect(player.position.z > 5.3 and player.position.z < 5.51, "Back wall contains player")
	player.reset_to_spawn()
	Input.action_press("move_forward")
	player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(not Input.is_action_pressed("move_forward"), "Focus loss clears stale navigation actions")
	var start: Vector3 = player.position
	Input.action_press("move_forward")
	await frames(60)
	Input.action_release("move_forward")
	expect(not player.navigation_enabled and absf(player.position.z - start.z) < 0.01, "Focus loss stops navigation")
	player.set_navigation(true)
	player.position.y = -6
	await frames(3)
	expect(player.position.distance_to(room.get_node("Spawn").position) < 0.1, "Fall recovery restores spawn")
	print("Foundation physics checks: %s" % ("PASS" if failures == 0 else "FAIL"))
	room.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
