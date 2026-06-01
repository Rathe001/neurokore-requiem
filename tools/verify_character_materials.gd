extends SceneTree

# Quick verification that the post-import script wired up Meshy textures
# correctly on each character FBX. Loads each imported scene, walks its
# MeshInstance3D's, reports the surface material's albedo texture.
#
# Run:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script ../tools/verify_character_materials.gd

const PATHS: Array[String] = [
	"res://assets/characters/player_analog_male/player_analog_male.fbx",
	"res://assets/characters/player_cyborg_female/player_cyborg_female.fbx",
	"res://assets/characters/player_forged_male/player_forged_male.fbx",
	"res://assets/characters/crimson_vein_titan/crimson_vein_titan.fbx",
	"res://assets/characters/riot_guard_male_1/riot_guard_male_1.fbx",
	"res://assets/characters/riot_guard_female_2/riot_guard_female_2.fbx",
]


func _init() -> void:
	for p in PATHS:
		print("\n══ %s ══" % p)
		var packed: PackedScene = load(p) as PackedScene
		if packed == null:
			print("  failed to load")
			continue
		var inst: Node = packed.instantiate()
		if inst == null:
			print("  failed to instantiate")
			continue
		_walk(inst, "")
		inst.queue_free()
	quit()


func _walk(node: Node, indent: String) -> void:
	if node is AnimationPlayer:
		var ap: AnimationPlayer = node
		print("%s%s (AnimationPlayer) anims=%s" % [indent, ap.name, ap.get_animation_list()])
	if node is Skeleton3D:
		var sk: Skeleton3D = node
		var sample_bones: Array = []
		for i in mini(5, sk.get_bone_count()):
			sample_bones.append(sk.get_bone_name(i))
		print("%s%s (Skeleton3D) unique_name=%s bone_count=%d sample=%s" % [
			indent, sk.name, sk.unique_name_in_owner, sk.get_bone_count(), sample_bones])
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		print("%s%s (%s)" % [indent, mi.name, mi.get_class()])
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for surf in range(mesh.get_surface_count()):
				var m: Material = mi.get_active_material(surf)
				if m == null:
					print("%s  surf %d: <null>" % [indent, surf])
					continue
				var albedo: String = "?"
				if m is BaseMaterial3D:
					var tex: Texture2D = (m as BaseMaterial3D).albedo_texture
					albedo = "<none>" if tex == null else tex.resource_path
				print("%s  surf %d: %s albedo=%s" % [indent, surf, m.get_class(), albedo])
	for c in node.get_children():
		_walk(c, indent + "  ")
