extends SceneTree

const Mapping = preload("res://scripts/console_surface_mapping.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene: Node3D = load("res://scenes/ship.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	await physics_frame
	var player: CharacterBody3D = scene.get_node("Player")
	if not scene.material_errors.is_empty():
		push_error("Material dependencies: " + str(scene.material_errors.slice(0, 8)) + " (total " + str(scene.material_errors.size()) + ")")
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(scene.MATERIALS))
	var found_metal_wall := false
	var found_transparent_net := false
	for entry in manifest.surfaces.values():
		if entry.diffuse == "lightmaps/leh_wall01.png":
			found_metal_wall = true
			if entry.alpha_mode != "opaque" or not entry.alpha_is_reflectivity:
				push_error("Metal wall reflectivity alpha was treated as transparency")
				quit(1)
				return
		if entry.diffuse == "lightmaps/leh_net01.png":
			found_transparent_net = true
			if entry.alpha_mode != "blend":
				push_error("Net texture lost its transparency")
				quit(1)
				return
	if not found_metal_wall or not found_transparent_net:
		push_error("Expected material classification samples are missing")
		quit(1)
		return
	var ids := {}
	for console in get_nodes_in_group("consoles"):
		if not scene.is_ancestor_of(console):
			continue
		var id: String = console.get_meta("console_id", "")
		if id.is_empty() or ids.has(id):
			push_error("Console IDs must be nonempty and unique: " + id)
			quit(1)
			return
		ids[id] = true
		var point: Vector3 = console.get_node("InteractionPoint").global_position
		var screen: MeshInstance3D = console.get_node("Screen")
		var pose: Marker3D = console.get_node("ViewPose")
		var floor_query := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP)
		floor_query.exclude = [player.get_rid()]
		var floor_hit := scene.get_world_3d().direct_space_state.intersect_ray(floor_query)
		var approach: Transform3D = player.global_transform
		approach.origin = point
		var sight := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.65, screen.global_position)
		sight.exclude = [player.get_rid()]
		var obstruction := scene.get_world_3d().direct_space_state.intersect_ray(sight)
		if floor_hit.is_empty() or absf(floor_hit.position.y - point.y) > 0.1 or player.test_move(approach, Vector3.UP * 0.01) or (not obstruction.is_empty() and obstruction.position.distance_to(screen.global_position) > float(console.get_meta("sight_tolerance", 0.15))):
			push_error("Console approach obstructed or unsupported: " + id)
			quit(1)
			return
		if (-pose.global_basis.z.normalized()).dot((screen.global_position - pose.global_position).normalized()) < 0.999:
			push_error("Console view is not aligned: " + id)
			quit(1)
			return
		var camera: Camera3D = player.get_node("Camera3D")
		camera.global_transform = pose.global_transform
		var bounds := Rect2(-1000, 100, 1200, 800)
		for uv: Vector2 in [Vector2(0.02, 0.5), Vector2(0.2, 0.7), Vector2(0.98, 0.5)]:
			var pixel := Mapping.console_pointer(camera, screen, bounds.position + bounds.size * uv, bounds, Vector2(1200, 800))
			var mapped := Mapping.normalized(Mapping.surface_uv(camera, screen, pixel), Vector2(1200, 800), Mapping.surface_size(screen))
			if mapped.distance_to(uv) > 0.0001:
				push_error("Console pointer mapping failed: " + id)
				quit(1)
				return
	if ids.size() != 4 or not ids.has("ship_cockpit") or not ids.has("ship_central") or not ids.has("ship_central_right") or not ids.has("ship_medbay"):
		push_error("Ship must have the four expected console IDs")
		quit(1)
		return
	# Two neighboring displays must select the one under the crosshair.
	var controller = scene.get_node("ConsoleController")
	for console_name in ["CentralConsole", "CentralConsoleRight"]:
		controller.slots.append({"console": scene.get_node(console_name), "native": null,
			"material": null, "texture": null, "content": Rect2(), "state": "unassigned", "label": ""})
	player.camera.position = Vector3(0, 1.65, 0)
	var common_view := false
	for x in [44.2, 44.5, 44.8, 45.1, 45.4, 45.7]:
		for z in [-48.0, -48.4, -48.8, -49.2, -49.6, -50.0]:
			player.global_position = Vector3(x, 1.8, z)
			var approach: Transform3D = player.global_transform
			if player.test_move(approach, Vector3.UP * 0.01):
				continue
			var both := true
			for i in 2:
				var target: Node3D = controller.slots[i].console.get_node("Screen")
				player.camera.look_at(target.global_position)
				if not controller._near_console() or controller.current_slot != i:
					both = false
					break
			if both:
				common_view = true
				break
		if common_view:
			break
	if not common_view:
		push_error("Adjacent consoles could not both be selected from a shared approach")
		quit(1)
		return
	controller.slots.clear()
	player.camera.rotation = Vector3.ZERO
	var spawn: Transform3D = player.spawn_transform
	player.global_position += Vector3(2, 1, 2)
	player.camera.rotation.x = 0.5
	player.reset_to_spawn()
	if not player.global_transform.is_equal_approx(spawn) or not player.camera.rotation.is_equal_approx(Vector3.ZERO):
		push_error("Ship reset did not restore spawn and camera")
		quit(1)
		return
	var query := PhysicsRayQueryParameters3D.create(Vector3(50, 5, -50), Vector3(50, -5, -50))
	query.exclude = [player.get_rid()]
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		push_error("No collision floor beneath ship spawn")
		quit(1)
		return
	var wall_query := PhysicsRayQueryParameters3D.create(Vector3(50, 2.8, -50), Vector3(62, 2.8, -50))
	wall_query.exclude = [player.get_rid()]
	if scene.get_world_3d().direct_space_state.intersect_ray(wall_query).is_empty():
		push_error("No east wall collision near ship spawn")
		quit(1)
		return
	var floor_query := PhysicsRayQueryParameters3D.create(Vector3(45.5, 4, -36.5), Vector3(45.5, 0, -36.5))
	if scene.get_world_3d().direct_space_state.intersect_ray(floor_query).is_empty():
		push_error("No representative floor collision in room 003ebog")
		quit(1)
		return
	var table_query := PhysicsRayQueryParameters3D.create(Vector3(50, 2.4, -49.4), Vector3(50, 2.4, -46.2))
	table_query.exclude = [player.get_rid()]
	var table_hit := scene.get_world_3d().direct_space_state.intersect_ray(table_query)
	if table_hit.is_empty() or not str(table_hit.collider.name).begins_with("mroom_holocentre"):
		push_error("Missing central table collision")
		quit(1)
		return
	var approach := player.global_transform
	approach.origin = Vector3(50, 1.8, -49.4)
	if not player.test_move(approach, Vector3(0, 0, 3.2)):
		push_error("Player capsule passes through the central table")
		quit(1)
		return
	var panel_query := PhysicsRayQueryParameters3D.create(Vector3(57, 2.3, -44), Vector3(53, 2.3, -44))
	panel_query.exclude = [player.get_rid()]
	var panel_hit := scene.get_world_3d().direct_space_state.intersect_ray(panel_query)
	if panel_hit.is_empty() or not str(panel_hit.collider.name).begins_with("Object08"):
		push_error("Missing collision on the curved panel behind the central chairs")
		quit(1)
		return
	var door_query := PhysicsRayQueryParameters3D.create(Vector3(48.7416, 2.8, -52), Vector3(48.7416, 2.8, -55))
	door_query.exclude = [player.get_rid()]
	if not scene.get_world_3d().direct_space_state.intersect_ray(door_query).is_empty():
		push_error("Central doorway is obstructed")
		quit(1)
		return
	var doorway := player.global_transform
	doorway.origin = Vector3(48.7416, 1.8, -52)
	if player.test_move(doorway, Vector3(0, 0, -3)):
		push_error("Player capsule cannot cross the central doorway")
		quit(1)
		return
	for check in [
		[Vector3(51.1, 2.5, -79.5), Vector3(51.1, 2.5, -81), "cockpit_chair01"],
		[Vector3(52.7, 2.7, -78.5), Vector3(52.7, 2.7, -82.5), "Object120"],
		[Vector3(53.6, 2.5, -81.5), Vector3(53.6, 2.5, -82.4), "ck_panels"],
	]:
		var cockpit_query := PhysicsRayQueryParameters3D.create(check[0], check[1])
		cockpit_query.exclude = [player.get_rid()]
		var cockpit_hit := scene.get_world_3d().direct_space_state.intersect_ray(cockpit_query)
		if cockpit_hit.is_empty() or not str(cockpit_hit.collider.name).begins_with(check[2]):
			push_error("Missing cockpit collision: " + check[2])
			quit(1)
			return
	var cockpit_entrance := player.global_transform
	cockpit_entrance.origin = Vector3(52.7, 1.8, -71.5)
	if player.test_move(cockpit_entrance, Vector3(0, 0, -3)):
		push_error("Player capsule cannot enter the cockpit")
		quit(1)
		return
	print("Ship spawn floor:", hit.position)
	scene.queue_free()
	await create_timer(0.2).timeout
	quit()
