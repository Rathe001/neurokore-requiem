extends SceneTree

# Load level_shell, give it a few frames for _ready chain, then dump
# the wall blood globals + verify the WallLiquidLayer instances are
# alive and in the right groups.


func _init() -> void:
	print("\n══ Loading level_shell.tscn ══")
	var packed: PackedScene = load("res://scenes/world/level_shell.tscn")
	if packed == null:
		push_error("Failed to load level_shell")
		quit(); return
	var inst: Node = packed.instantiate()
	get_root().add_child(inst)
	# Give the scene a couple of frames to settle _ready chains.
	await process_frame
	await process_frame
	await process_frame

	print("\n══ wall_liquid_layer group members ══")
	var nodes := inst.get_tree().get_nodes_in_group(&"wall_liquid_layer")
	for n in nodes:
		var wl: WallLiquidLayer = n as WallLiquidLayer
		if wl == null:
			print("  ", n.name, " (NOT WallLiquidLayer)")
			continue
		print("  ", wl.name, " fluid=", wl.fluid_id, " axis=", wl.surface_axis, " in_tree=", wl.is_inside_tree())
		var sv := wl.get_child(0) as SubViewport
		if sv != null:
			print("    SubViewport size=", sv.size, " tex=", sv.get_texture())

	print("\n══ Globals after _ready ══")
	for k in ["wall_blood_mask_x", "wall_blood_mask_z", "wall_blood_fresh_color",
			  "wall_blood_dried_color", "wall_blood_age", "wall_blood_extent_xz",
			  "wall_blood_extent_y"]:
		var v: Variant = RenderingServer.global_shader_parameter_get(k)
		print("  ", k, " = ", v)

	quit()
