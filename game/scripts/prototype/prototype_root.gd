extends Node3D

func _ready() -> void:
	print("[prototype_root] scene loaded, child count: ", get_child_count())
	for child in get_children():
		print("  - ", child.name, " (", child.get_class(), ")")
