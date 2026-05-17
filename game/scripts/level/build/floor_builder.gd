extends RefCounted
class_name FloorBuilder
## Floor surfaces for rooms and corridors. Three entry points:
##   build_piece_floor   — full-room floor with overlap into wall thickness
##   build_exact_floor   — exact-sized floor (used for pit perimeter strips)
##   build_corridor_floor — corridor floor, with optional pit-gap split
##
## Pit interiors (the shaft and ooze/spike floor) are owned by PitBuilder;
## this file only handles the surface plane(s) and the perimeter trim.

const FLOOR_OVERLAP := 0.3  ## extends piece floors past wall outer face (slightly > wall_thickness * 0.5)
## Subdivision density for floor PlaneMesh, in vertices per meter. The
## displacement ShaderMaterial needs subdivided geometry to actually deform —
## without subdivision a 20m floor is 4 corner verts and no displacement is
## visible. 1.0 = one extra vertex per meter (so a 20m floor gets a 20×20 grid).
## Capped via FLOOR_SUBDIV_CAP per axis to bound the triangle count for huge
## rooms. Always-on (not gated on whether the material is a displacement
## shader) because the perf hit is small and a flat PlaneMesh suffers no
## quality loss from extra verts.
const FLOOR_SUBDIV_PER_METER := 1.0
const FLOOR_SUBDIV_CAP := 32
const PIT_TRIM_H := 0.12    ## height of raised lip at pit edges
# Sub-millimetre vertical bias applied to corridor floor MESHES (not their
# colliders) so the corridor loses the depth tie wherever it overlaps room
# geometry under shared walls — invisible at the fixed top-down camera but
# eliminates flicker. Mirrors the pit-pillar pattern: collision stays at the
# nominal floor height (y=0) so enemies and the player walk smoothly across
# the room/corridor seam without a 1.5mm "step down" snagging movement.
const CORRIDOR_FLOOR_MESH_Y_BIAS := -0.0015


static func build_piece_floor(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float, mat: Material = null, mesh_y_bias: float = 0.0) -> void:
	build_exact_floor(ctx, center, size_x + FLOOR_OVERLAP * 2.0, size_z + FLOOR_OVERLAP * 2.0, mat, mesh_y_bias)


static func build_exact_floor(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float, mat: Material = null, mesh_y_bias: float = 0.0) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size_x, size_z)
	mesh.subdivide_width = clampi(int(size_x * FLOOR_SUBDIV_PER_METER), 1, FLOOR_SUBDIV_CAP)
	mesh.subdivide_depth = clampi(int(size_z * FLOOR_SUBDIV_PER_METER), 1, FLOOR_SUBDIV_CAP)
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
	# mesh_y_bias shifts ONLY the visual mesh below the body's transform, so
	# corridor floors can lose the z-fight without their collision dropping
	# below the room floor's collision (which would create a step at the seam).
	inst.position.y = mesh_y_bias
	body.add_child(inst)
	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(size_x, 0.1, size_z)
	col.position.y = -0.05
	body.add_child(col)
	ctx.root.add_child(body)
	body.add_to_group(&"structures")
	# Walked by the minimap baker to rasterize abstract walkable shapes
	# (D2-style filled-rectangle map) instead of taking a 3D screenshot.
	# Pit interiors are NOT in this group — those are built by PitBuilder
	# and aren't safe to walk on. Pillars (jump platforms inside pits)
	# are also skipped; they're too small to read at minimap scale.
	body.add_to_group(&"minimap_walkable")
	# Floor-type tag for material-specific footstep audio. Alt material
	# (corridors) = grate; primary (rooms) = metal plating.
	var is_alt := mat != null and mat == ctx.floor_material_alt
	body.add_to_group(&"floor_grate" if is_alt else &"floor_metal")


static func build_corridor_floor(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var along_z := cd.axis == CorridorDef.Axis.Z
	var sw := cd.width   # perpendicular to travel
	var sl := cd.length  # along travel axis
	# Pass the un-biased center; the mesh_y_bias arg shifts only the visual,
	# leaving the collision flush with the adjacent room floor.
	var bias := CORRIDOR_FLOOR_MESH_Y_BIAS

	if cd.pit_width <= 0.0:
		var sx := sw if along_z else sl
		var sz := sl if along_z else sw
		build_piece_floor(ctx, center, sx, sz, ctx.floor_material_alt, bias)
		return

	# Two floor sections flanking the pit gap (no overlap toward the gap edge).
	var section_len := (sl - cd.pit_width) * 0.5
	if section_len < 0.01:
		return
	var half_gap := cd.pit_width * 0.5
	var offset := section_len * 0.5 + half_gap
	if along_z:
		build_exact_floor(ctx, center + Vector3(0.0, 0.0, -offset), sw, section_len, ctx.floor_material_alt, bias)
		build_exact_floor(ctx, center + Vector3(0.0, 0.0,  offset), sw, section_len, ctx.floor_material_alt, bias)
		for s in [-1.0, 1.0]:
			WallBuilder.create_trim_box(ctx,
				center + Vector3(0.0, PIT_TRIM_H * 0.5, s * half_gap),
				sw, PIT_TRIM_H, ctx.theme.wall_thickness, ctx.wall_material_alt)
	else:
		build_exact_floor(ctx, center + Vector3(-offset, 0.0, 0.0), section_len, sw, ctx.floor_material_alt, bias)
		build_exact_floor(ctx, center + Vector3( offset, 0.0, 0.0), section_len, sw, ctx.floor_material_alt, bias)
		for s in [-1.0, 1.0]:
			WallBuilder.create_trim_box(ctx,
				center + Vector3(s * half_gap, PIT_TRIM_H * 0.5, 0.0),
				ctx.theme.wall_thickness, PIT_TRIM_H, sw, ctx.wall_material_alt)

	# Pit interior cross-section is the corridor's perpendicular width × the
	# pit gap along the travel axis.
	var inner_x: float = cd.width if along_z else cd.pit_width
	var inner_z: float = cd.pit_width if along_z else cd.width
	PitBuilder.build_pit_shaft(ctx, center, inner_x, inner_z)
