extends SceneTree
## Print the material slot wiring for one character mesh.

func _init() -> void:
	var ps := load("res://assets/characters/player_analog_male/player_analog_male.fbx") as PackedScene
	var root := ps.instantiate()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				print("surface %d: null material" % s)
				continue
			print("surface %d (%s):" % [s, mat.resource_name])
			var slots := {
				"albedo": BaseMaterial3D.TEXTURE_ALBEDO,
				"normal": BaseMaterial3D.TEXTURE_NORMAL,
				"metallic": BaseMaterial3D.TEXTURE_METALLIC,
				"roughness": BaseMaterial3D.TEXTURE_ROUGHNESS,
				"emission": BaseMaterial3D.TEXTURE_EMISSION,
				"ao": BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION,
			}
			for key: String in slots:
				var t := mat.get_texture(slots[key])
				print("  %-10s %s" % [key, t.resource_path.get_file() if t != null else "—"])
			print("  metallic=%.2f roughness=%.2f spec=%.2f normal_enabled=%s emission_enabled=%s" % [
				mat.metallic, mat.roughness, mat.metallic_specular,
				str(mat.normal_enabled), str(mat.emission_enabled)])
	root.free()
	quit()
