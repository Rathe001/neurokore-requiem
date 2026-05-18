@tool
extends EditorScenePostImport
## Normalizes kit-bash panel .glb assets so the level builders can assume a
## canonical axis convention regardless of how the source was authored. Saves
## per-asset manual orientation fiddling whenever a new panel is dropped in
## from Blenderkit (or any other source).
##
## Type is auto-detected from the source path:
##   - "wall_panel" in path → wall mode
##   - "floor_panel" in path → floor mode
##   - anything else → script no-ops with a warning
##
## Canonical orientations:
##   Wall:  X = length, Y = thickness, Z = height. AABB centered on origin.
##          Matches WallBuilder._add_tiled_wall_segment (height_in_y=false).
##   Floor: X = longer tile dim, Y = shorter tile dim, Z = thickness.
##          AABB centered on origin. Matches FloorBuilder.build_piece_floor_kit
##          (which then applies Basis(RIGHT,-π/2) to lay it flat).
##
## The transform is baked into the mesh vertices (positions + normals +
## tangents), so MultiMesh — which renders against the raw mesh and ignores
## any scene-graph transforms — gets a fully pre-rotated, pre-centered mesh.
## The MeshInstance3D's own transform is reset to identity.
##
## Wire-up: in the .glb.import file, set `import_script/path` to this script's
## res:// path. Re-import to apply.


func _post_import(scene: Node) -> Node:
	var src := get_source_file()
	var kit_type := _detect_kit_type(src)
	if kit_type == "":
		return scene

	var mi := _find_first_mesh_instance(scene)
	if mi == null or mi.mesh == null:
		push_warning("[kit_panel_normalizer] %s: no MeshInstance3D/mesh; skipping." % src)
		return scene

	var aabb: AABB = mi.mesh.get_aabb()
	var size := aabb.size
	var thickness_idx := _argmin_v3(size)
	var remaining := _other_two(thickness_idx)
	# Pick which non-thickness axis is "canonical X" vs "canonical Y/Z".
	# Walls:  canonical Z = the largest (height ≈ wall_height).
	#         canonical X = the remaining (length).
	# Floors: canonical X = the larger of the two non-thickness dims.
	#         canonical Y = the smaller.
	var larger_remaining := remaining[0] if size[remaining[0]] >= size[remaining[1]] else remaining[1]
	var smaller_remaining := remaining[1] if larger_remaining == remaining[0] else remaining[0]

	# Columns of the basis: each column is the canonical-space vector that the
	# source axis with that index maps onto. (Basis(x,y,z) constructor takes the
	# images of source basis vectors as its three args.)
	var cols: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	if kit_type == "wall":
		cols[smaller_remaining] = Vector3.RIGHT       # length     → canonical X
		cols[thickness_idx] = Vector3.UP              # thickness  → canonical Y
		cols[larger_remaining] = Vector3(0.0, 0.0, 1.0)  # height  → canonical Z
	else:  # floor
		cols[larger_remaining] = Vector3.RIGHT        # long tile  → canonical X
		cols[smaller_remaining] = Vector3.UP          # short tile → canonical Y
		cols[thickness_idx] = Vector3(0.0, 0.0, 1.0)  # thickness  → canonical Z

	var b := Basis(cols[0], cols[1], cols[2])
	# Right-handed enforcement: a pure axis swap can land on a reflection
	# (det = -1). Flip canonical X — mirroring along length is visually
	# neutral for symmetric panels and avoids inverting height or thickness.
	if b.determinant() < 0.0:
		b.x = -b.x

	# Translate so the AABB center lands at origin in canonical space.
	var rotated_center: Vector3 = b * (aabb.position + aabb.size * 0.5)
	var xform := Transform3D(b, -rotated_center)

	mi.mesh = _apply_transform_to_mesh(mi.mesh, xform)
	mi.transform = Transform3D.IDENTITY
	return scene


# ── Helpers ───────────────────────────────────────────────────────────────

static func _detect_kit_type(path: String) -> String:
	if "wall_panel" in path:
		return "wall"
	if "floor_panel" in path:
		return "floor"
	return ""


static func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var r := _find_first_mesh_instance(child)
		if r != null:
			return r
	return null


static func _argmin_v3(v: Vector3) -> int:
	if v.x <= v.y and v.x <= v.z:
		return 0
	if v.y <= v.z:
		return 1
	return 2


static func _other_two(excluded: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(3):
		if i != excluded:
			out.append(i)
	return out


# Bakes `xform` into a copy of the mesh: positions get full transform, normals
# and tangent directions get the rotation-only part. Returns a new ArrayMesh
# preserving primitive type and per-surface materials.
static func _apply_transform_to_mesh(mesh: Mesh, xform: Transform3D) -> ArrayMesh:
	var new_mesh := ArrayMesh.new()
	for surface_idx in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		if arrays[Mesh.ARRAY_VERTEX] != null:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(verts.size()):
				verts[i] = xform * verts[i]
			arrays[Mesh.ARRAY_VERTEX] = verts
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(normals.size()):
				normals[i] = (xform.basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		# Tangents are stored as packed float32, 4 per vertex: (x, y, z, sign).
		# Only the xyz direction needs rotating; sign is handedness, preserved.
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			var i := 0
			while i < tangents.size():
				var t := Vector3(tangents[i], tangents[i + 1], tangents[i + 2])
				t = (xform.basis * t).normalized()
				tangents[i] = t.x
				tangents[i + 1] = t.y
				tangents[i + 2] = t.z
				i += 4
			arrays[Mesh.ARRAY_TANGENT] = tangents
		var primitive := mesh.surface_get_primitive_type(surface_idx)
		var material := mesh.surface_get_material(surface_idx)
		new_mesh.add_surface_from_arrays(primitive, arrays)
		new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, material)
	return new_mesh
