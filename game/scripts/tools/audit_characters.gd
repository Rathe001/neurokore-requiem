extends SceneTree
## One-shot audit: tri counts, texture refs, material/surface counts for
## every character FBX. Run:
##   godot --headless --path game --script tools/audit_characters.gd

func _init() -> void:
	var dirs := DirAccess.get_directories_at("res://assets/characters")
	for d in dirs:
		var base := "res://assets/characters/%s" % d
		var files := DirAccess.get_files_at(base)
		for f in files:
			if not f.ends_with(".fbx"):
				continue
			var path := "%s/%s" % [base, f]
			var ps := load(path) as PackedScene
			if ps == null:
				print("%s  LOAD FAILED" % path)
				continue
			var root := ps.instantiate()
			# Dictionary accumulator — GDScript lambdas capture ints by
			# value, so plain counters silently stay 0.
			var acc := {"tris": 0, "meshes": 0, "surfaces": 0, "tex": {}, "shadow": []}
			_walk(root, func(n: Node) -> void:
				var mi := n as MeshInstance3D
				if mi == null or mi.mesh == null:
					return
				acc["meshes"] += 1
				acc["shadow"].append(mi.cast_shadow)
				for s in mi.mesh.get_surface_count():
					acc["surfaces"] += 1
					var arr: Array = mi.mesh.surface_get_arrays(s)
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
					if idx.size() > 0:
						acc["tris"] += idx.size() / 3
					else:
						var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
						acc["tris"] += v.size() / 3
					var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
					if mat != null:
						for tex_kind in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_EMISSION]:
							var t := mat.get_texture(tex_kind)
							if t != null and t.resource_path != "":
								acc["tex"][t.resource_path] = true
			)
			print("%-55s tris=%-8d meshes=%d surfaces=%d shadow=%s" % [
				d + "/" + f, acc["tris"], acc["meshes"], acc["surfaces"], str(acc["shadow"])])
			root.free()
	quit()


func _walk(n: Node, cb: Callable) -> void:
	cb.call(n)
	for c in n.get_children():
		_walk(c, cb)
