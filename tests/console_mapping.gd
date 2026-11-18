extends SceneTree
const Mapping = preload("res://scripts/console_mapping.gd")
var failed: bool = false
func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _initialize() -> void:
	# A 4:3 source on a 2:1 surface has pillarboxes. Reject the bars.
	expect(Mapping.normalized(Vector2(0.05, 0.5), Vector2(800, 600)).x < 0, "Pillarbox click rejected")
	expect(Mapping.normalized(Vector2(0.5, 0.5), Vector2(800, 600)).is_equal_approx(Vector2(0.5, 0.5)), "Aspect-fit center")
	# A wide source has letterboxes. Invalid dimensions never produce an input point.
	expect(Mapping.normalized(Vector2(0.5, 0.01), Vector2(2400, 600)).x < 0, "Letterbox click rejected")
	expect(Mapping.normalized(Vector2(0.5, 0.5), Vector2.ZERO).x < 0, "Unavailable source rejected")
	# Frame margins plus 2x Retina and capture downscaling. Origin may be on a negative display.
	var crop := Rect2(32, 16, 1200, 800)
	var target := Rect2(-1440, 120, 900, 600)
	var pixel: Vector2 = Mapping.capture_pixel(Vector2(0.25, 0.75), crop)
	expect(pixel.is_equal_approx(Vector2(332, 616)), "Content origin accounted for in pixels")
	expect(Mapping.native_point(pixel, crop, target).is_equal_approx(Vector2(-1215, 570)), "Native points do not double-apply Retina scale")
	# Same location after source resize, capture resize, move, and a different scale.
	crop = Rect2(0, 0, 1800, 1200)
	target = Rect2(300, -900, 1200, 800)
	pixel = Mapping.capture_pixel(Vector2(0.25, 0.75), crop)
	expect(Mapping.native_point(pixel, crop, target).is_equal_approx(Vector2(600, -300)), "Resized/moved source uses current bounds")
	# Test production ray mapping with the actual camera and screen transforms.
	call_deferred("ray_checks")
func ray_checks() -> void:
	var room = load("res://scenes/placeholder_room.tscn").instantiate()
	root.add_child(room)
	var camera: Camera3D = room.get_node("Player/Camera3D")
	var screen: MeshInstance3D = room.get_node("Console/Screen")
	camera.global_transform = room.get_node("Console/ViewPose").global_transform
	var center: Vector2 = camera.unproject_position(screen.global_position)
	expect(Mapping.surface_uv(camera, screen, center).is_equal_approx(Vector2(0.5, 0.5)), "Camera ray intersects screen center")
	var window := Rect2(-1000, 220, 900, 600)
	var content := Vector2(1350, 900)
	for uv: Vector2 in [Vector2(0.001, 0.45), Vector2(0.5, 0.999), Vector2(0.8, 0.2)]:
		var desktop := window.position + uv * window.size
		var drawn := Mapping.console_pointer(camera, screen, desktop, window, content)
		var back := Mapping.normalized(Mapping.surface_uv(camera, screen, drawn), content)
		expect(back.distance_to(uv) < 0.0001, "Desktop point projects onto its captured pixel")
	var edge := window.position + window.size * Vector2(0.5, 1)
	var before := Mapping.console_pointer(camera, screen, edge - Vector2.DOWN, window, content)
	var after := Mapping.console_pointer(camera, screen, edge + Vector2.DOWN, window, content)
	expect(after.y > before.y and after.distance_to(before) < 10, "Pointer crosses bottom bezel continuously")
	room.queue_free()
	await process_frame
	print("Console coordinate checks: %s" % ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
