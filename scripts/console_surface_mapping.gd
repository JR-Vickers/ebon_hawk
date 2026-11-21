extends RefCounted

# All UVs have top-left origin. The shader uses the same aspect-fit rectangle.
static func fitted_rect(surface_size: Vector2, content_size: Vector2) -> Rect2:
	if surface_size.x <= 0 or surface_size.y <= 0 or content_size.x <= 0 or content_size.y <= 0:
		return Rect2()
	var scale: float = minf(surface_size.x / content_size.x, surface_size.y / content_size.y)
	var size: Vector2 = content_size * scale
	return Rect2((surface_size - size) * 0.5, size)

static func normalized(surface_uv: Vector2, content_size: Vector2, surface_size: Vector2 = Vector2(2, 1)) -> Vector2:
	var rect := fitted_rect(surface_size, content_size)
	var point := surface_uv * surface_size
	if not rect.has_area() or not rect.has_point(point):
		return Vector2(-1, -1)
	return (point - rect.position) / rect.size

static func capture_pixel(uv: Vector2, content_pixels: Rect2) -> Vector2:
	return content_pixels.position + uv * content_pixels.size

static func native_point(pixel: Vector2, content_pixels: Rect2, window_points: Rect2) -> Vector2:
	# Ratios cancel capture downscale and Retina pixels/point, once content is cropped.
	return window_points.position + (pixel - content_pixels.position) / content_pixels.size * window_points.size

static func surface_size(screen: Node3D) -> Vector2:
	if screen.has_meta("surface_size"):
		return screen.get_meta("surface_size")
	return screen.mesh.size

static func surface_uv(camera: Camera3D, screen: Node3D, point: Vector2) -> Vector2:
	var origin := screen.to_local(camera.project_ray_origin(point))
	var ray := screen.global_basis.inverse() * camera.project_ray_normal(point)
	var size := surface_size(screen)
	var depth: float = screen.get_meta("curve_depth", 0.0)
	var k := 4.0 * depth / (size.x * size.x)
	var a := k * ray.x * ray.x
	var b := 2.0 * k * origin.x * ray.x - ray.z
	var c := k * origin.x * origin.x - origin.z
	var t := -1.0
	if absf(a) < 0.0000001:
		if absf(b) > 0.0000001:
			t = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var t1 := (-b - sqrt(discriminant)) / (2.0 * a)
			var t2 := (-b + sqrt(discriminant)) / (2.0 * a)
			t = t1 if t1 >= 0.0 else t2
	if t < 0.0:
		return Vector2(-1, -1)
	var local := origin + ray * t
	var normal := Vector3(-2.0 * k * local.x, 0, 1)
	if normal.dot(ray) >= -0.00001:
		return Vector2(-1, -1)
	return Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)

# Project a desktop point onto the captured image. Extending UV outside the
# target lets the pointer cross the bezel continuously while bounds reject clicks.
static func console_pointer(camera: Camera3D, screen: Node3D, desktop: Vector2, window: Rect2, content: Vector2) -> Vector2:
	var uv := (desktop - window.position) / window.size
	var size := surface_size(screen)
	var fitted := fitted_rect(size, content)
	var point := fitted.position + fitted.size * uv
	var x := point.x - size.x * 0.5
	var depth: float = screen.get_meta("curve_depth", 0.0)
	var z := depth * pow(2.0 * x / size.x, 2.0)
	return camera.unproject_position(screen.to_global(Vector3(x, size.y * 0.5 - point.y, z)))
