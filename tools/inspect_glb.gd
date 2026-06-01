extends SceneTree

# Quick tree dump of a few GLBs so we can decide what node paths the
# scenes that load them should reference.

const PATHS: Array[String] = [
	"res://assets/models/objects/elevator/elevator.glb",
	"res://assets/models/objects/switch_console/switch_console.glb",
]


func _init() -> void:
	for p in PATHS:
		print("\n══ %s ══" % p)
		var packed: PackedScene = load(p) as PackedScene
		if packed == null:
			print("  (failed to load)")
			continue
		var inst: Node = packed.instantiate()
		if inst == null:
			print("  (failed to instantiate)")
			continue
		_walk(inst, "")
		inst.queue_free()
	quit()


func _walk(node: Node, indent: String) -> void:
	var extra := ""
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var tris := 0 if mi.mesh == null else mi.mesh.get_faces().size() / 3
		var aabb: AABB = AABB() if mi.mesh == null else mi.mesh.get_aabb()
		extra = " [tris=%d aabb=%s]" % [tris, aabb]
	print("%s%s (%s)%s" % [indent, node.name, node.get_class(), extra])
	for c in node.get_children():
		_walk(c, indent + "  ")
