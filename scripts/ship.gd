extends Node3D

const VISUAL := "res://assets/generated/ship/ebon_hawk.glb"
const COLLISION := "res://assets/generated/ship/collision.glb"
const FURNITURE_COLLISION := "res://assets/generated/ship/furniture_collision.glb"
const MATERIALS := "res://assets/generated/ship/materials.json"
const LIGHTMAP_SHADER := preload("res://scripts/ship_lightmap.gdshader")
const LIGHTMAP_CUTOUT := preload("res://scripts/ship_lightmap_cutout.gdshader")
const LIGHTMAP_BLEND := preload("res://scripts/ship_lightmap_blend.gdshader")
const LIGHTMAP_ADDITIVE := preload("res://scripts/ship_lightmap_additive.gdshader")
var material_errors: Array[String] = []
var texture_cache: Dictionary = {}

func _ready() -> void:
	var visual := _load_gltf(VISUAL)
	var collision := _load_gltf(COLLISION)
	if visual == null or collision == null:
		$HUD/Instructions.text = "Ship assets missing. Follow docs/assets.md to generate them."
		return
	add_child(visual)
	_apply_lightmaps(visual)
	add_child(collision)
	_make_collision(collision)
	var furniture := _load_gltf(FURNITURE_COLLISION)
	if furniture == null:
		push_error("Missing furniture collision; follow docs/assets.md")
		return
	add_child(furniture)
	_make_collision(furniture)

func _apply_lightmaps(visual: Node) -> void:
	if not FileAccess.file_exists(MATERIALS):
		material_errors.append("Missing material manifest")
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MATERIALS))
	if not data is Dictionary or not data.has("surfaces"):
		material_errors.append("Invalid material manifest")
		return
	for node_name in data.surfaces:
		var node := visual.find_child(node_name, true, false) as MeshInstance3D
		var entry: Dictionary = data.surfaces[node_name]
		var shaders := {"opaque": LIGHTMAP_SHADER, "cutout": LIGHTMAP_CUTOUT,
			"blend": LIGHTMAP_BLEND, "additive": LIGHTMAP_ADDITIVE}
		if not shaders.has(entry.get("alpha_mode", "")):
			material_errors.append("Missing or invalid alpha mode: " + node_name)
			continue
		var lightmap := _load_texture(entry.lightmap)
		var diffuse := _load_texture(entry.diffuse)
		if node == null or node.mesh == null or lightmap == null or diffuse == null:
			material_errors.append("Missing mesh or lightmap: " + node_name)
			continue
		for surface in node.mesh.get_surface_count():
			if node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV2].is_empty():
				material_errors.append("Missing diffuse texture or UV2: " + node_name)
				continue
			var replacement := ShaderMaterial.new()
			replacement.shader = shaders[entry.alpha_mode]
			replacement.set_shader_parameter("diffuse_texture", diffuse)
			replacement.set_shader_parameter("lightmap_texture", lightmap)
			replacement.set_shader_parameter("self_illumination", Vector3(entry.self_illumination[0], entry.self_illumination[1], entry.self_illumination[2]))
			replacement.set_shader_parameter("opacity", entry.alpha)
			if entry.alpha_mode == "blend" or entry.alpha_mode == "additive":
				replacement.set_shader_parameter("alpha_is_reflectivity", entry.alpha_is_reflectivity)
			node.set_surface_override_material(surface, replacement)

func _load_texture(path: String) -> Texture2D:
	if texture_cache.has(path):
		return texture_cache[path]
	var image := Image.new()
	if image.load("res://assets/generated/ship/" + path) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	texture_cache[path] = texture
	return texture

func _load_gltf(path: String) -> Node:
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		push_error("Failed to load " + path)
		return null
	return document.generate_scene(state)

func _make_collision(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		node.create_trimesh_collision()
		node.visible = false
	for child in node.get_children():
		if not child is StaticBody3D:
			_make_collision(child)
