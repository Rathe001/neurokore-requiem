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


# Tile the floor area with theme.floor_model instances on a grid. Each tile
# is floor_grid_size meters square. Collision + minimap registration come
# from a single hidden body covering the whole area (same approach as the
# procedural floor) so layout-cell registration and footstep audio still
# work. Visual is the model instances only.
static func build_piece_floor_kit(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float, mesh_y_bias: float = 0.0) -> void:
	var t := ctx.theme
	if t.floor_model == null:
		return
	var mesh := WallBuilder._get_kit_mesh(ctx, t.floor_model, false)
	if mesh == null:
		return
	# Same FLOOR_OVERLAP the procedural path uses — extends the floor +0.3m
	# past the room/corridor edge so it overlaps into the wall thickness and
	# adjacent piece's floor. Without this, the rasterizer sees a seam at
	# every piece boundary (visible as a thin dark line at iso, fall-
	# through gap in collision).
	size_x += FLOOR_OVERLAP * 2.0
	size_z += FLOOR_OVERLAP * 2.0
	var grid: float = t.floor_grid_size
	# Adaptive tiling — fit any size with no edge gaps. n = round(size/grid)
	# (min 1), then actual_grid = size/n. Each tile is scaled to fill its
	# actual cell exactly, regardless of the model's native footprint.
	var nx: int = max(1, int(round(size_x / grid)))
	var nz: int = max(1, int(round(size_z / grid)))
	var actual_grid_x: float = size_x / float(nx)
	var actual_grid_z: float = size_z / float(nz)
	# Container body — hosts collision + group memberships. The MMI rides
	# along as a child so the visuals follow the body's transform.
	var body := StaticBody3D.new()
	body.name = &"Floor"
	body.input_ray_pickable = false
	body.transform.origin = center
	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(size_x, 0.1, size_z)
	col.position.y = -0.05
	body.add_child(col)
	# Build transforms for every tile, then a single MultiMesh covers them
	# all with one draw call per material surface.
	var origin_x := -size_x * 0.5 + actual_grid_x * 0.5
	var origin_z := -size_z * 0.5 + actual_grid_z * 0.5
	var n := nx * nz
	# Scale each tile to fill actual_grid × actual_grid exactly. Combines
	# the room-fit scaling with the native_size correction (model is 1.92m
	# × 2m, scaling per-axis avoids gaps).
	var native: Vector2 = t.floor_model_native_size
	var sx: float = actual_grid_x / maxf(0.01, native.x)
	var sz: float = actual_grid_z / maxf(0.01, native.y)
	var tile_basis := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK).scaled(Vector3(sx, 1.0, sz))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	var i := 0
	for ix in range(nx):
		for iz in range(nz):
			var pos := Vector3(origin_x + ix * actual_grid_x, mesh_y_bias, origin_z + iz * actual_grid_z)
			mm.set_instance_transform(i, Transform3D(tile_basis, pos))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	body.add_child(mmi)
	ctx.root.add_child(body)
	body.add_to_group(&"structures")
	body.add_to_group(&"minimap_walkable")
	# Floor-type tag for material-specific footstep audio.
	body.add_to_group(&"floor_metal")
	# Room-gated visibility hook — LoS culler hides this body (and the
	# MMI children that render the tiles) when the player is far from
	# this room. Major perf win at horde density since hidden floors
	# skip both their vertex pass and shadow-map contribution.
	body.add_to_group(&"room_geometry")


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


# Kit-bash version of corridor floor. Quantizes corridor length to the
# grid, then delegates to build_piece_floor_kit which tiles the area
# with floor model instances via MultiMesh.
static func build_corridor_floor_kit(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var t := ctx.theme
	if t.floor_model == null:
		return
	var along_z := cd.axis == CorridorDef.Axis.Z
	var sw := cd.width
	var sl := cd.length
	var sx := sw if along_z else sl
	var sz := sl if along_z else sw
	build_piece_floor_kit(ctx, center, sx, sz, CORRIDOR_FLOOR_MESH_Y_BIAS)


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
