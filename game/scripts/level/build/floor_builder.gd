extends RefCounted
class_name FloorBuilder
## Floor surfaces for rooms and corridors. Three entry points:
##   build_piece_floor   — full-room floor with overlap into wall thickness
##   build_exact_floor   — exact-sized floor (used for pit perimeter strips)
##   build_corridor_floor — corridor floor, with optional pit-gap split
##
## Pit interiors (the shaft and ooze/spike floor) are owned by PitBuilder;
## this file only handles the surface plane(s) and the perimeter trim.

const FLOOR_OVERLAP := 0.2  ## extends piece floors to cover under walls (= wall_thickness * 0.5)
const PIT_TRIM_H := 0.12    ## height of raised lip at pit edges
# Sub-millimetre vertical bias applied to corridor floors so the corridor
# loses the depth tie wherever it overlaps room geometry under shared walls
# — invisible at the fixed top-down camera but eliminates flicker.
const CORRIDOR_FLOOR_Y_BIAS := -0.0015


static func build_piece_floor(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float, mat: Material = null) -> void:
	build_exact_floor(ctx, center, size_x + FLOOR_OVERLAP * 2.0, size_z + FLOOR_OVERLAP * 2.0, mat)


static func build_exact_floor(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float, mat: Material = null) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size_x, size_z)
	var floor_mat := mat if mat != null else ctx.floor_material
	if floor_mat != null:
		mesh.material = floor_mat
	var body := StaticBody3D.new()
	body.name = &"Floor"
	body.input_ray_pickable = false
	body.transform.origin = center
	var inst := MeshInstance3D.new()
	inst.name = &"Mesh"
	inst.mesh = mesh
	body.add_child(inst)
	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(size_x, 0.1, size_z)
	col.position.y = -0.05
	body.add_child(col)
	ctx.root.add_child(body)
	body.add_to_group(&"structures")


static func build_corridor_floor(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var along_z := cd.axis == CorridorDef.Axis.Z
	var sw := cd.width   # perpendicular to travel
	var sl := cd.length  # along travel axis
	var floor_center := center + Vector3(0.0, CORRIDOR_FLOOR_Y_BIAS, 0.0)

	if cd.pit_width <= 0.0:
		var sx := sw if along_z else sl
		var sz := sl if along_z else sw
		build_piece_floor(ctx, floor_center, sx, sz, ctx.floor_material_alt)
		return

	# Two floor sections flanking the pit gap (no overlap toward the gap edge).
	var section_len := (sl - cd.pit_width) * 0.5
	if section_len < 0.01:
		return
	var half_gap := cd.pit_width * 0.5
	var offset := section_len * 0.5 + half_gap
	if along_z:
		build_exact_floor(ctx, floor_center + Vector3(0.0, 0.0, -offset), sw, section_len, ctx.floor_material_alt)
		build_exact_floor(ctx, floor_center + Vector3(0.0, 0.0,  offset), sw, section_len, ctx.floor_material_alt)
		for s in [-1.0, 1.0]:
			WallBuilder.create_trim_box(ctx,
				center + Vector3(0.0, PIT_TRIM_H * 0.5, s * half_gap),
				sw, PIT_TRIM_H, ctx.theme.wall_thickness, ctx.wall_material_alt)
	else:
		build_exact_floor(ctx, floor_center + Vector3(-offset, 0.0, 0.0), section_len, sw, ctx.floor_material_alt)
		build_exact_floor(ctx, floor_center + Vector3( offset, 0.0, 0.0), section_len, sw, ctx.floor_material_alt)
		for s in [-1.0, 1.0]:
			WallBuilder.create_trim_box(ctx,
				center + Vector3(s * half_gap, PIT_TRIM_H * 0.5, 0.0),
				ctx.theme.wall_thickness, PIT_TRIM_H, sw, ctx.wall_material_alt)

	# Pit interior cross-section is the corridor's perpendicular width × the
	# pit gap along the travel axis.
	var inner_x: float = cd.width if along_z else cd.pit_width
	var inner_z: float = cd.pit_width if along_z else cd.width
	PitBuilder.build_pit_shaft(ctx, center, inner_x, inner_z)
