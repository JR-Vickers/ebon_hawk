extends RefCounted

# All UVs have top-left origin. The shader uses the same aspect-fit rectangle.
static func fitted_rect(surface_size: Vector2, content_size: Vector2) -> Rect2:
	if surface_size.x <= 0 or surface_size.y <= 0 or content_size.x <= 0 or content_size.y <= 0:
		return Rect2()
	var scale: float = minf(surface_size.x / content_size.x, surface_size.y / content_size.y)
	var size: Vector2 = content_size * scale
	return Rect2((surface_size - size) * 0.5, size)

static func normalized(surface_uv: Vector2, content_size: Vector2) -> Vector2:
	var rect := fitted_rect(Vector2(2, 1), content_size)
	var point := surface_uv * Vector2(2, 1)
	if not rect.has_area() or not rect.has_point(point):
		return Vector2(-1, -1)
	return (point - rect.position) / rect.size

static func capture_pixel(uv: Vector2, content_pixels: Rect2) -> Vector2:
	return content_pixels.position + uv * content_pixels.size

static func native_point(pixel: Vector2, content_pixels: Rect2, window_points: Rect2) -> Vector2:
	# Ratios cancel capture downscale and Retina pixels/point, once content is cropped.
	return window_points.position + (pixel - content_pixels.position) / content_pixels.size * window_points.size

static func surface_uv(camera: Camera3D, screen: Node3D, point: Vector2) -> Vector2:
	var ray := camera.project_ray_normal(point)
	var normal := screen.global_basis.z.normalized()
	if normal.dot(ray) >= -0.00001:
		return Vector2(-1, -1)
	var hit = Plane(normal, screen.global_position).intersects_ray(camera.project_ray_origin(point), ray)
	if hit == null:
		return Vector2(-1, -1)
	var local: Vector3 = screen.to_local(hit)
	return Vector2(local.x / 2.0 + 0.5, 0.5 - local.y)
