@tool
extends SceneTree
## One-shot diagnostic: load wall_panel_v5.glb + floor_panel_v2.glb and print
## per-surface vertex/triangle count + AABB. Run with:
##   godot --headless --path game --script res://tools/inspect_kit_mesh.gd

func _init() -> void:
	_inspect("res://assets/models/objects/wall_panel_v5/wall_panel_v5.glb")
	_inspect("res://assets/models/objects/wall_panel_v6/wall_panel_v6.glb")
	_inspect("res://assets/models/objects/floor_panel_v2/floor_panel_v2.glb")
	quit()


func _inspect(path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		print("MISSING: ", path)
		return
	var inst := scene.instantiate()
	var mi := _find_mesh(inst)
	if mi == null:
		print("NO MESH: ", path)
		inst.queue_free()
		return
	var mesh := mi.mesh
	var aabb := mesh.get_aabb()
	print("=== ", path, " ===")
	print("  AABB: pos=", aabb.position, " size=", aabb.size)
	print("  Surfaces: ", mesh.get_surface_count())
	var total_tris := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var tris: int
		if indices != null and indices.size() > 0:
			tris = indices.size() / 3
		else:
			tris = verts.size() / 3
		total_tris += tris
		var mat := mesh.surface_get_material(i)
		print("    surface[", i, "] verts=", verts.size(), " tris=", tris, " mat=", mat)
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			print("      albedo_color=", bm.albedo_color,
				" albedo_tex=", bm.albedo_texture,
				" normal_tex=", bm.normal_texture,
				" roughness_tex=", bm.roughness_texture,
				" metallic=", bm.metallic, " roughness=", bm.roughness)
		elif mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			print("      albedo_tex=", sm.get_shader_parameter(&"albedo_tex"),
				" normal_tex=", sm.get_shader_parameter(&"normal_tex"),
				" roughness_tex=", sm.get_shader_parameter(&"roughness_tex"),
				" albedo_color=", sm.get_shader_parameter(&"albedo_color"))
	print("  TOTAL TRIS: ", total_tris)
	inst.queue_free()


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node as MeshInstance3D
	for child in node.get_children():
		var r := _find_mesh(child)
		if r != null:
			return r
	return null
