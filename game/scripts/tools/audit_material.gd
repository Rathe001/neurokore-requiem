extends SceneTree
## Print the ACTIVE material slot wiring (surface override wins — the
## meshy_character_import post-import script applies the real PBR set as
## an override; the inner FBX material is dormant) + loaded texture
## dimensions, for a player mesh, a riot guard, the titan, and a weapon.

const PATHS := [
	"res://assets/characters/player_analog_male/player_analog_male.fbx",
	"res://assets/characters/riot_guard_female_1/riot_guard_female_1.fbx",
	"res://assets/characters/crimson_vein_titan/crimson_vein_titan.fbx",
	"res://assets/models/weapons/rpg/rpg.glb",
]


func _init() -> void:
	for p: String in PATHS:
		print("=== %s ===" % p.get_file())
		var ps := load(p) as PackedScene
		if ps == null:
			print("  LOAD FAILED")
			continue
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
				var mat := mi.get_active_material(s) as BaseMaterial3D
				if mat == null:
					print("  surface %d: null/non-standard material" % s)
					continue
				var slots := {
					"albedo": BaseMaterial3D.TEXTURE_ALBEDO,
					"normal": BaseMaterial3D.TEXTURE_NORMAL,
					"metallic": BaseMaterial3D.TEXTURE_METALLIC,
					"roughness": BaseMaterial3D.TEXTURE_ROUGHNESS,
					"emission": BaseMaterial3D.TEXTURE_EMISSION,
				}
				for key: String in slots:
					var t := mat.get_texture(slots[key])
					if t != null:
						print("  %-10s %-55s %s" % [key, t.resource_path.get_file(), str(t.get_size())])
					else:
						print("  %-10s —" % key)
		root.free()
	quit()
