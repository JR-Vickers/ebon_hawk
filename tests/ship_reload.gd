extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error(message)
	quit(1)

func run() -> void:
	var host = load("res://scenes/ship_reload_host.tscn").instantiate()
	host.set_meta("reload_test", true)
	root.add_child(host)
	await process_frame
	var old_ship: Node = host.ship
	var player = old_ship.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector3(51, 1.8, -49)
	player.camera.rotation.x = 0.3
	var expected_transform: Transform3D = player.global_transform
	player.controls_locked = true
	var event := InputEventKey.new()
	event.physical_keycode = KEY_T
	event.pressed = true
	host._unhandled_input(event)
	if host.pending:
		fail("T must not request a reload while a console controls input")
		return
	player.controls_locked = false
	host._unhandled_input(event)
	if not host.pending:
		fail("T did not request a reload during navigation")
		return
	player.controls_locked = true
	await create_timer(2.5).timeout
	if host.validating or host.ship != old_ship:
		fail("Reload did not wait for console interaction")
		return
	player.controls_locked = false
	var deadline := Time.get_ticks_msec() + 30000
	while host.ship == old_ship and Time.get_ticks_msec() < deadline:
		await process_frame
	if host.ship == old_ship:
		fail("Queued reload did not finish: " + host.status.text)
		return
	var reloaded = host.ship.get_node("Player")
	if reloaded.global_position.distance_to(expected_transform.origin) > 0.05 or not is_equal_approx(reloaded.camera.rotation.x, 0.3):
		fail("Reload did not preserve player position and camera: " + str(reloaded.global_position) + " / " + str(reloaded.camera.rotation))
		return
	print("Ship reload checks: PASS")
	host.queue_free()
	await process_frame
	OS.delay_msec(200) # Let the audio mixer release stopped streams.
	quit()
