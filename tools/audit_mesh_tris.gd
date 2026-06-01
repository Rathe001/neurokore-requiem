extends SceneTree

# Counts triangles in every .fbx / .glb / .gltf under game/assets/.
# Run via:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script ../tools/audit_mesh_tris.gd
# Output appears on stdout.

const ROOTS: Array[String] = [
	"res://assets/characters",
	"res://assets/models",
	"res://assets/animations",
]


func _init() -> void:
	var rows: Array = []
	for root in ROOTS:
		_walk(root, rows)
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("\n════ Triangle audit (sorted by tri count, descending) ════")
	print("    tris       MB  path")
	for r in rows:
		print("%9d  %6.1f  %s" % [r[0], r[2], r[1]])
	var total_tris := 0
	for r in rows:
		total_tris += r[0]
	print("\nTotal: %d tris across %d files" % [total_tris, rows.size()])
	quit()


func _walk(dir_path: String, rows: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name == "." or name == "..":
			name = d.get_next()
			continue
		var full := dir_path + "/" + name
		if d.current_is_dir():
			_walk(full, rows)
		elif full.ends_with(".fbx") or full.ends_with(".glb") or full.ends_with(".gltf"):
			var tris := _count_tris_in_file(full)
			var mb: float = 0.0
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				mb = float(f.get_length()) / (1024.0 * 1024.0)
				f.close()
			if tris > 0:
				rows.append([tris, full, mb])
		name = d.get_next()
	d.list_dir_end()


func _count_tris_in_file(path: String) -> int:
	var packed := load(path) as PackedScene
	if packed == null:
		return 0
	var inst := packed.instantiate()
	if inst == null:
		return 0
	var tris := _count_tris(inst)
	inst.queue_free()
	return tris


func _count_tris(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			total += mi.mesh.get_faces().size() / 3
	for c in node.get_children():
		total += _count_tris(c)
	return total
