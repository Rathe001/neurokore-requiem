extends SceneTree

# Headless inspector. Loads a weapon glb and dumps its MeshInstance3D
# tree with names, AABBs, and material counts. Run with:
#   godot --headless --script tools/inspect_weapon_glb.gd <glb_path>
# (path is relative to project root)

func _init() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty():
		print("usage: --script inspect_weapon_glb.gd -- <res-path>")
		quit()
		return
	var path: String = argv[0]
	if not path.begins_with("res://"):
		path = "res://" + path
	if not ResourceLoader.exists(path):
		print("not found: ", path)
		quit()
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("not a PackedScene: ", path)
		quit()
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		print("instantiate failed")
		quit()
		return
	print("=== ", path, " ===")
	_dump(root, 0)
	quit()


func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var label := "%s%s : %s" % [indent, node.name, node.get_class()]
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var aabb := mi.get_aabb()
		label += "  AABB pos=%s size=%s" % [aabb.position, aabb.size]
		if mi.mesh != null:
			label += "  surfaces=%d" % mi.mesh.get_surface_count()
	print(label)
	for child in node.get_children():
		_dump(child, depth + 1)
