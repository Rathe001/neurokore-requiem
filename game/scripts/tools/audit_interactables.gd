extends SceneTree
## Compare visual AABB vs collision-shape AABB for every interactable
## scene, in scene-root local space. Run:
##   godot --headless --path game --script scripts/tools/audit_interactables.gd

const PATHS := [
	"res://scenes/prototype/prototype_switch.tscn",
	"res://scenes/prototype/prototype_loot_crate.tscn",
	"res://scenes/prototype/prototype_exit.tscn",
	"res://scenes/prototype/prototype_door.tscn",
]


func _init() -> void:
	for p: String in PATHS:
		var ps := load(p) as PackedScene
		if ps == null:
			print("%s LOAD FAILED" % p)
			continue
		var root := ps.instantiate() as Node3D
		var visual := _visual_aabb(root)
		print("=== %s ===" % p.get_file())
		print("  visual AABB:    pos=%s size=%s  (x: %.2f..%.2f, z: %.2f..%.2f)" % [
			str(visual.position.snappedf(0.01)), str(visual.size.snappedf(0.01)),
			visual.position.x, visual.position.x + visual.size.x,
			visual.position.z, visual.position.z + visual.size.z])
		for cs_node in _find_collision_shapes(root):
			var cs := cs_node as CollisionShape3D
			var box := cs.shape as BoxShape3D
			if box == null:
				print("  collision: non-box shape %s" % str(cs.shape))
				continue
			var cmin := cs.position - box.size * 0.5
			var cmax := cs.position + box.size * 0.5
			print("  collision box:  pos=%s size=%s  (x: %.2f..%.2f, z: %.2f..%.2f)" % [
				str((cs.position - box.size * 0.5).snappedf(0.01)), str(box.size),
				cmin.x, cmax.x, cmin.z, cmax.z])
		root.free()
	quit()


func _visual_aabb(root: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xform: Transform3D = entry[1]
		var n3 := n as Node3D
		var local: Transform3D = xform
		if n3 != null and n != root:
			local = xform * n3.transform
		var vi := n as VisualInstance3D
		if vi != null:
			var aabb: AABB = local * vi.get_aabb()
			if first:
				combined = aabb
				first = false
			else:
				combined = combined.merge(aabb)
		for c in n.get_children():
			stack.append([c, local])
	return combined


func _find_collision_shapes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionShape3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
