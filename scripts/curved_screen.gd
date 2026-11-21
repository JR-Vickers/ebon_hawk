extends MeshInstance3D

# The display bends toward the viewer at the edges. Keep UVs linear across
# the width so captured content and the pointer use the same coordinates.
const SEGMENTS := 48

func _ready() -> void:
	var dimensions: Vector2 = get_meta("surface_size", Vector2(1.6, 0.9))
	var depth: float = get_meta("curve_depth", 0.2)
	var old_material: Material = mesh.material if mesh is QuadMesh else null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in SEGMENTS + 1:
		var u := float(i) / SEGMENTS
		var x := (u - 0.5) * dimensions.x
		var z := depth * pow(2.0 * x / dimensions.x, 2.0)
		var normal := Vector3(-8.0 * depth * x / (dimensions.x * dimensions.x), 0, 1).normalized()
		for row in 2:
			vertices.append(Vector3(x, dimensions.y * (0.5 - row), z))
			normals.append(normal)
			uvs.append(Vector2(u, row))
		if i < SEGMENTS:
			var a := i * 2
			indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var curved := ArrayMesh.new()
	curved.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	curved.surface_set_material(0, old_material)
	mesh = curved
