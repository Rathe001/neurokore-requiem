extends RefCounted
class_name WallBuilder
## Wall geometry: cached collision/mesh boxes for simple wall segments,
## procedural single-mesh per room (one draw call per room's walls),
## corridor walls, low-ceiling crawl blocks, and trim boxes (used at pit
## edges). Material/shape caches live on BuildContext.

const SEAM := 0.02  ## anti-z-fight gap for corridor walls abutting room geometry
# Sub-millimetre vertical bias applied to corridor wall tops so the corridor
# loses the depth tie wherever it overlaps room geometry under a shared wall
# — invisible at the fixed top-down camera but eliminates flicker.
const CORRIDOR_WALL_Y_BIAS := -0.001


static func get_wall_mesh(ctx: LevelBuildContext, size_x: float, size_z: float) -> BoxMesh:
	var key := "%s_%s" % [size_x, size_z]
	if ctx.wall_meshes.has(key):
		return ctx.wall_meshes[key]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size_x, ctx.theme.wall_height, size_z)
	ctx.wall_meshes[key] = mesh
	return mesh


static func get_wall_shape(ctx: LevelBuildContext, size_x: float, size_z: float) -> BoxShape3D:
	var key := "%s_%s" % [size_x, size_z]
	if ctx.wall_shapes.has(key):
		return ctx.wall_shapes[key]
	var shape := BoxShape3D.new()
	shape.size = Vector3(size_x, ctx.theme.wall_height, size_z)
	ctx.wall_shapes[key] = shape
	return shape


static func create_wall(ctx: LevelBuildContext, pos: Vector3, size_x: float, size_z: float, mat: Material = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.transform.origin = pos + Vector3(0, ctx.theme.wall_height * 0.5, 0)
	body.input_ray_pickable = false

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = &"Mesh"
	mesh_inst.mesh = get_wall_mesh(ctx, size_x, size_z)
	var wall_mat := mat if mat != null else ctx.wall_material
	if wall_mat != null:
		mesh_inst.material_override = wall_mat
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = get_wall_shape(ctx, size_x, size_z)
	body.add_child(col)

	ctx.root.add_child(body)
	body.add_to_group(&"structures")
	return body


# Collision-only wall (no mesh) — room walls draw their geometry from the
# single procedural room mesh, so jamb segments only need physics bodies.
static func create_wall_body(ctx: LevelBuildContext, pos: Vector3, size_x: float, size_z: float) -> void:
	var body := StaticBody3D.new()
	body.transform.origin = pos + Vector3(0, ctx.theme.wall_height * 0.5, 0)
	body.input_ray_pickable = false
	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = get_wall_shape(ctx, size_x, size_z)
	body.add_child(col)
	ctx.root.add_child(body)
	body.add_to_group(&"structures")


# Trim box: small wall-material box used as a raised lip at pit edges.
# Carries collision so the player can't step over the lip into the pit.
static func create_trim_box(ctx: LevelBuildContext, pos: Vector3, sx: float, sy: float, sz: float, mat: Material = null) -> void:
	var body := StaticBody3D.new()
	body.input_ray_pickable = false
	body.transform.origin = pos
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(sx, sy, sz)
	body.add_child(col)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	(mesh_inst.mesh as BoxMesh).size = Vector3(sx, sy, sz)
	var wall_mat := mat if mat != null else ctx.wall_material
	if wall_mat != null:
		mesh_inst.material_override = wall_mat
	body.add_child(mesh_inst)
	ctx.root.add_child(body)
	body.add_to_group(&"structures")


static func build_corridor_walls(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var thick := ctx.theme.wall_thickness
	var hw := cd.width * 0.5
	var wall_y := CORRIDOR_WALL_Y_BIAS
	if cd.axis == CorridorDef.Axis.Z:
		create_wall(ctx, center + Vector3(hw, wall_y, 0), thick, cd.length + thick - SEAM, ctx.wall_material_alt)
		create_wall(ctx, center + Vector3(-hw, wall_y, 0), thick, cd.length + thick - SEAM, ctx.wall_material_alt)
	else:
		create_wall(ctx, center + Vector3(0, wall_y, hw), cd.length + thick - SEAM * 2.0, thick, ctx.wall_material_alt)
		create_wall(ctx, center + Vector3(0, wall_y, -hw), cd.length + thick - SEAM * 2.0, thick, ctx.wall_material_alt)


# Full-height static column from floor to ceiling — architectural blocker
# the player walks around. Uses the alt wall material (utility cladding)
# for visual distinction from the room walls. Independent from PitBuilder's
# pillars (those rise from pit floor and act as jump platforms).
static func create_decorative_pillar(ctx: LevelBuildContext, pos: Vector3, size: Vector2) -> void:
	var t := ctx.theme
	var height := t.wall_height
	var body := StaticBody3D.new()
	body.name = &"DecorativePillar"
	body.input_ray_pickable = false
	body.transform.origin = Vector3(pos.x, height * 0.5, pos.z)

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(size.x, height, size.y)
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	(mesh_inst.mesh as BoxMesh).size = Vector3(size.x, height, size.y)
	if ctx.wall_material_alt != null:
		mesh_inst.material_override = ctx.wall_material_alt
	body.add_child(mesh_inst)

	ctx.root.add_child(body)
	body.add_to_group(&"structures")


static func build_low_ceiling(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var h := cd.ceiling_height
	var along_z := cd.axis == CorridorDef.Axis.Z
	var sw := cd.width  if along_z else cd.length  # perpendicular span
	var sl := cd.length if along_z else cd.width   # travel-axis span
	var t := ctx.theme
	var block_h := t.wall_height - h
	var block_cy := h + block_h * 0.5

	# Solid block filling the corridor from ceiling_height to wall_height.
	# Extend slightly into the side walls to eliminate coplanar z-fighting.
	var bx := sw + t.wall_thickness if along_z else sl
	var bz := sl if along_z else sw + t.wall_thickness
	var box := BoxMesh.new()
	box.size = Vector3(bx, block_h, bz)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = box
	if ctx.wall_material_alt != null:
		mesh_inst.material_override = ctx.wall_material_alt
	mesh_inst.position = center + Vector3(0.0, block_cy, 0.0)
	# Groups must be set BEFORE add_child so OverhangFader's node_added handler
	# sees the &"overhang" tag the moment the mesh enters the tree.
	mesh_inst.add_to_group(&"structures")
	mesh_inst.add_to_group(&"overhang")
	ctx.root.add_child(mesh_inst)

	var body := StaticBody3D.new()
	body.name = &"LowCeiling"
	body.input_ray_pickable = false
	body.transform.origin = center + Vector3(0.0, h + 0.05, 0.0)
	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	# Axis-aware collision dims — earlier this was always (sw, 0.1, sl)
	# regardless of corridor axis, which rotated the slab 90° on X-axis
	# corridors. Symptom: the invisible ceiling extended perpendicular to
	# the visible mesh and bled into adjacent rooms (notably reaching
	# across pit-room edges and trapping enemies / blocking the player
	# well past where the corridor visually ended).
	var col_x: float = sw if along_z else sl
	var col_z: float = sl if along_z else sw
	(col.shape as BoxShape3D).size = Vector3(col_x, 0.1, col_z)
	body.add_child(col)
	ctx.root.add_child(body)


# ── Procedural Room Mesh ────────────────────────────────────────────────
# A single mesh for all four walls of a room (with openings cut), produced
# via SurfaceTool. Front faces, jamb reveals, and wall tops included.
# Collision is built separately by build_room_collision().

static func build_room_mesh(ctx: LevelBuildContext, center: Vector3, rd: RoomDef) -> void:
	var hx := rd.size.x * 0.5
	var hz := rd.size.y * 0.5
	var t := ctx.theme
	var ht := t.wall_thickness * 0.5
	var h := t.wall_height
	var cx := center.x
	var cz := center.z
	var ox := hx + ht
	var oz := hz + ht
	var ix := hx - ht
	var iz := hz - ht

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_add_ns_faces(st, cx, cz - oz, cz - iz, ox, ix, h,
		RoomDef.Wall.NORTH in rd.openings, rd.opening_width, true)
	_add_ns_faces(st, cx, cz + oz, cz + iz, ox, ix, h,
		RoomDef.Wall.SOUTH in rd.openings, rd.opening_width, false)
	_add_ew_faces(st, cz, cx + ox, cx + ix, oz, iz, h,
		RoomDef.Wall.EAST in rd.openings, rd.opening_width, true)
	_add_ew_faces(st, cz, cx - ox, cx - ix, oz, iz, h,
		RoomDef.Wall.WEST in rd.openings, rd.opening_width, false)

	var inst := MeshInstance3D.new()
	inst.name = &"RoomWalls"
	inst.mesh = st.commit()
	if ctx.wall_material != null:
		inst.material_override = ctx.wall_material
	ctx.root.add_child(inst)
	inst.add_to_group(&"structures")


# Adds a vertical quad. bl/br are the two bottom corners; the face normal is
# derived from the cross product and the winding is CCW from the normal side
# (Godot's front-face convention). Normals are set explicitly because
# generate_normals() averages vertices that share the same position.
static func _vquad(st: SurfaceTool, bl: Vector3, br: Vector3, h: float) -> void:
	var tl := bl + Vector3(0, h, 0)
	var top_right := br + Vector3(0, h, 0)
	var n := (br - bl).cross(tl - bl).normalized()
	st.set_normal(n)
	st.add_vertex(bl); st.add_vertex(top_right); st.add_vertex(br)
	st.add_vertex(bl); st.add_vertex(tl); st.add_vertex(top_right)


# Adds a horizontal quad at height y with normal +Y (CCW from above).
# x1>x0, z1>z0 required.
static func _hquad_top(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	var a := Vector3(x0, y, z0)
	var b := Vector3(x0, y, z1)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x1, y, z0)
	st.set_normal(Vector3.UP)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)


# North/South wall faces. outer_z/inner_z are world-space z of the two planes.
static func _add_ns_faces(st: SurfaceTool, cx: float, outer_z: float, inner_z: float,
		ox: float, ix: float, h: float, has_opening: bool, gap: float, is_north: bool) -> void:
	var z0 := minf(outer_z, inner_z)
	var z1 := maxf(outer_z, inner_z)

	if has_opening:
		var hg := gap * 0.5
		# Outer segments
		if is_north:
			_vquad(st, Vector3(cx - hg, 0, outer_z), Vector3(cx - ox, 0, outer_z), h)
			_vquad(st, Vector3(cx + ox, 0, outer_z), Vector3(cx + hg, 0, outer_z), h)
		else:
			_vquad(st, Vector3(cx - ox, 0, outer_z), Vector3(cx - hg, 0, outer_z), h)
			_vquad(st, Vector3(cx + hg, 0, outer_z), Vector3(cx + ox, 0, outer_z), h)
		# Inner segments — extended to ±ox so the corner cube's inside face
		# is covered. Stopping at ±ix would leave a visible gap where the
		# perpendicular wall's inner face also stops short, producing a
		# see-through hole at every room corner.
		if is_north:
			_vquad(st, Vector3(cx - ox, 0, inner_z), Vector3(cx - hg, 0, inner_z), h)
			_vquad(st, Vector3(cx + hg, 0, inner_z), Vector3(cx + ox, 0, inner_z), h)
		else:
			_vquad(st, Vector3(cx - hg, 0, inner_z), Vector3(cx - ox, 0, inner_z), h)
			_vquad(st, Vector3(cx + ox, 0, inner_z), Vector3(cx + hg, 0, inner_z), h)
		# Reveal faces
		if is_north:
			_vquad(st, Vector3(cx - hg, 0, inner_z), Vector3(cx - hg, 0, outer_z), h)
			_vquad(st, Vector3(cx + hg, 0, outer_z), Vector3(cx + hg, 0, inner_z), h)
		else:
			_vquad(st, Vector3(cx - hg, 0, outer_z), Vector3(cx - hg, 0, inner_z), h)
			_vquad(st, Vector3(cx + hg, 0, inner_z), Vector3(cx + hg, 0, outer_z), h)
		# Top segments
		_hquad_top(st, cx - ox, z0, cx - hg, z1, h)
		_hquad_top(st, cx + hg, z0, cx + ox, z1, h)
	else:
		if is_north:
			_vquad(st, Vector3(cx + ox, 0, outer_z), Vector3(cx - ox, 0, outer_z), h)
			# Inner extended to ±ox (was ±ix) — covers the corner cube's
			# inside face. See has_opening branch above for the same fix.
			_vquad(st, Vector3(cx - ox, 0, inner_z), Vector3(cx + ox, 0, inner_z), h)
		else:
			_vquad(st, Vector3(cx - ox, 0, outer_z), Vector3(cx + ox, 0, outer_z), h)
			_vquad(st, Vector3(cx + ox, 0, inner_z), Vector3(cx - ox, 0, inner_z), h)
		_hquad_top(st, cx - ox, z0, cx + ox, z1, h)


# East/West wall faces. outer_x/inner_x are world-space x of the two planes.
static func _add_ew_faces(st: SurfaceTool, cz: float, outer_x: float, inner_x: float,
		oz: float, iz: float, h: float, has_opening: bool, gap: float, is_east: bool) -> void:
	var min_x := minf(outer_x, inner_x)
	var max_x := maxf(outer_x, inner_x)

	if has_opening:
		var hg := gap * 0.5
		# Outer segments
		if is_east:
			_vquad(st, Vector3(outer_x, 0, cz - hg), Vector3(outer_x, 0, cz - oz), h)
			_vquad(st, Vector3(outer_x, 0, cz + oz), Vector3(outer_x, 0, cz + hg), h)
		else:
			_vquad(st, Vector3(outer_x, 0, cz - oz), Vector3(outer_x, 0, cz - hg), h)
			_vquad(st, Vector3(outer_x, 0, cz + hg), Vector3(outer_x, 0, cz + oz), h)
		# Inner segments — extended to ±oz so the corner cube's inside face
		# is covered. See _add_ns_faces for the equivalent fix on N/S walls;
		# the gap looked like a small see-through patch at every room corner.
		if is_east:
			_vquad(st, Vector3(inner_x, 0, cz - oz), Vector3(inner_x, 0, cz - hg), h)
			_vquad(st, Vector3(inner_x, 0, cz + hg), Vector3(inner_x, 0, cz + oz), h)
		else:
			_vquad(st, Vector3(inner_x, 0, cz - hg), Vector3(inner_x, 0, cz - oz), h)
			_vquad(st, Vector3(inner_x, 0, cz + oz), Vector3(inner_x, 0, cz + hg), h)
		# Reveal faces
		_vquad(st, Vector3(min_x, 0, cz - hg), Vector3(max_x, 0, cz - hg), h)
		_vquad(st, Vector3(max_x, 0, cz + hg), Vector3(min_x, 0, cz + hg), h)
		# Top segments
		_hquad_top(st, min_x, cz - iz, max_x, cz - hg, h)
		_hquad_top(st, min_x, cz + hg, max_x, cz + iz, h)
	else:
		if is_east:
			_vquad(st, Vector3(outer_x, 0, cz + oz), Vector3(outer_x, 0, cz - oz), h)
			# Inner extended to ±oz (was ±iz) — covers the corner cube's
			# inside face. Same rationale as the has_opening branch above.
			_vquad(st, Vector3(inner_x, 0, cz - oz), Vector3(inner_x, 0, cz + oz), h)
		else:
			_vquad(st, Vector3(outer_x, 0, cz - oz), Vector3(outer_x, 0, cz + oz), h)
			_vquad(st, Vector3(inner_x, 0, cz + oz), Vector3(inner_x, 0, cz - oz), h)
		_hquad_top(st, min_x, cz - iz, max_x, cz + iz, h)
