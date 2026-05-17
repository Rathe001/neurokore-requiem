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
# Room wall faces share the y=0 edge with the floor PlaneMesh. Without
# overlap, the GPU rasterizer can leave sub-pixel gaps at that edge —
# visible as thin dark lines at every wall base from the isometric camera.
# Extending the mesh below y=0 turns the shared edge into an overlap,
# sealing the junction. Corridor walls already handle this via their
# BoxMesh bottom sitting at CORRIDOR_WALL_Y_BIAS below the floor.
const ROOM_WALL_FLOOR_SINK := 0.02


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
	else:
		# Fallback dark grey for trim boxes when no wall_material is set
		# (e.g. kit-bash themes that dropped the procedural materials).
		# Without this, trim renders as default white BoxMesh which is
		# very visible from iso.
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.12, 0.12, 0.14)
		fallback.metallic = 0.3
		fallback.roughness = 0.7
		mesh_inst.material_override = fallback
	body.add_child(mesh_inst)
	ctx.root.add_child(body)
	body.add_to_group(&"structures")


static func build_corridor_walls(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var thick := ctx.theme.wall_thickness
	var hw := cd.width * 0.5
	var wall_y := CORRIDOR_WALL_Y_BIAS
	# Extend by ~thick (full room-wall-thickness) on each end instead of
	# half. Previously the corridor wall reached only halfway into the
	# room wall thickness, leaving a sub-pixel sliver between the wall
	# end and the room's inner face that showed as a thin "gap" at every
	# door opening. SEAM stays sub-millimetre so the now-larger overlap
	# still avoids z-fight against the room geometry it abuts.
	var ext := thick * 2.0 - SEAM * 2.0
	if cd.axis == CorridorDef.Axis.Z:
		create_wall(ctx, center + Vector3(hw, wall_y, 0), thick, cd.length + ext, ctx.wall_material_alt)
		create_wall(ctx, center + Vector3(-hw, wall_y, 0), thick, cd.length + ext, ctx.wall_material_alt)
	else:
		create_wall(ctx, center + Vector3(0, wall_y, hw), cd.length + ext, thick, ctx.wall_material_alt)
		create_wall(ctx, center + Vector3(0, wall_y, -hw), cd.length + ext, thick, ctx.wall_material_alt)


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
	# Layer 8 (Pillars) — its own physics layer so player/enemy/projectile
	# movement + impacts ALL collide with pillars (their masks include
	# Layer 8) while LoS culling and ProximityLighting (which mask Layer 1
	# only) ignore them. End result: pillars block bullets and bodies
	# without darkening the screen by eating proximity-light raycasts.
	body.collision_layer = 128
	body.collision_mask = 0

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(size.x, height, size.y)
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	(mesh_inst.mesh as BoxMesh).size = Vector3(size.x, height, size.y)
	if ctx.wall_material_alt != null:
		mesh_inst.material_override = ctx.wall_material_alt
	else:
		# Fallback when no wall_material_alt is set (e.g. kit-bash themes).
		# Plain dark grey BoxMesh so pillars don't render as default white
		# spikes. If we ever want kit-styled pillars, replace this with a
		# kit_pillar_model field on LevelTheme.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.12, 0.14)
		mat.metallic = 0.3
		mat.roughness = 0.7
		mesh_inst.material_override = mat
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


# ── Kit-Bash Room Walls ─────────────────────────────────────────────────
# Instances theme.wall_model along each wall in grid steps. Each panel is
# wall_grid_size meters wide (X), scaled vertically to wall_height. Doors
# get skipped by leaving a gap of `opening_width` centered on the wall.
# Collision is still handled by _build_room_wall_collisions in level_builder
# (panels are visual-only).

# Kit-bash version of corridor walls. Two parallel rows along the corridor's
# travel axis. No openings (doors live at the corridor's endpoints where it
# joins the rooms). Builds a single MMI per corridor.
static func build_corridor_walls_kit(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var t := ctx.theme
	if t.wall_model == null:
		return
	var mesh := _get_kit_mesh(ctx, t.wall_model, true)
	if mesh == null:
		return
	var grid: float = t.wall_grid_size
	var native_w: float = maxf(0.01, t.wall_model_native_width)
	var native_h: float = maxf(0.01, t.wall_model_native_height)
	var wall_h: float = t.wall_height
	var y_scale: float = wall_h / native_h
	var thick_half: float = t.wall_thickness * 0.5
	var along_z := cd.axis == CorridorDef.Axis.Z
	var half_w := cd.width * 0.5

	var sides: Array[Dictionary]
	if along_z:
		sides = [
			{"axis": Vector3.FORWARD, "base_pos": Vector3(half_w - thick_half, 0, 0), "y_rot": PI * 0.5},
			{"axis": Vector3.FORWARD, "base_pos": Vector3(-half_w + thick_half, 0, 0), "y_rot": -PI * 0.5},
		]
	else:
		sides = [
			{"axis": Vector3.RIGHT, "base_pos": Vector3(0, 0, half_w - thick_half), "y_rot": PI},
			{"axis": Vector3.RIGHT, "base_pos": Vector3(0, 0, -half_w + thick_half), "y_rot": 0.0},
		]

	var transforms: Array[Transform3D] = []
	for s: Dictionary in sides:
		_add_wall_segment(transforms, s["base_pos"], s["axis"], cd.length, s["y_rot"], wall_h, y_scale, grid, native_w)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	ctx.root.add_child(mmi)
	mmi.add_to_group(&"structures")
	mmi.add_to_group(&"room_geometry")


static func build_room_walls_kit(ctx: LevelBuildContext, center: Vector3, rd: RoomDef) -> void:
	var t := ctx.theme
	if t.wall_model == null:
		return
	var mesh := _get_kit_mesh(ctx, t.wall_model, true)
	if mesh == null:
		return
	var hx := rd.size.x * 0.5
	var hz := rd.size.y * 0.5
	var grid: float = t.wall_grid_size
	var wall_h: float = t.wall_height
	var native_h: float = maxf(0.01, t.wall_model_native_height)
	var native_w: float = maxf(0.01, t.wall_model_native_width)
	var y_scale: float = wall_h / native_h
	var gap: float = rd.opening_width

	# Panels positioned exactly at the room boundary. Earlier code used
	# `±hz - thick_half` to align with the collision wall's interior face,
	# but that put the visual panel 0.2m INSIDE the room, leaving a strip
	# of floor (which extends FLOOR_OVERLAP past the boundary) visible
	# beyond the wall from iso. With the panel at the boundary, the floor
	# overlap hides behind the wall geometry instead.
	var sides: Array[Dictionary] = [
		{"side": RoomDef.Wall.NORTH, "axis": Vector3.RIGHT, "base_pos": Vector3(0, 0, -hz), "length": rd.size.x, "y_rot": 0.0},
		{"side": RoomDef.Wall.SOUTH, "axis": Vector3.RIGHT, "base_pos": Vector3(0, 0, hz), "length": rd.size.x, "y_rot": PI},
		{"side": RoomDef.Wall.EAST, "axis": Vector3.FORWARD, "base_pos": Vector3(hx, 0, 0), "length": rd.size.y, "y_rot": PI * 0.5},
		{"side": RoomDef.Wall.WEST, "axis": Vector3.FORWARD, "base_pos": Vector3(-hx, 0, 0), "length": rd.size.y, "y_rot": -PI * 0.5},
	]

	# Collect all panel transforms first; then build a single MultiMesh
	# with one draw call covering every wall panel in the room. Walls with
	# door openings split into two segments (left + right of the gap),
	# each independently adaptive — so the opening is exactly empty and
	# the panel widths shrink to fit the remaining wall sections.
	var transforms: Array[Transform3D] = []
	for s: Dictionary in sides:
		var side: RoomDef.Wall = s["side"] as RoomDef.Wall
		var axis: Vector3 = s["axis"]
		var base_pos: Vector3 = s["base_pos"]
		var length: float = s["length"]
		var y_rot: float = s["y_rot"]
		var has_opening: bool = side in rd.openings
		if has_opening:
			# Two segments flanking the opening. Each segment runs from one
			# wall end to the opening edge, length = (wall_length - gap)/2.
			# Segment centers are offset from base_pos by half-segment-length
			# plus half-gap, so each segment sits flush against the opening.
			var seg_len: float = (length - gap) * 0.5
			if seg_len > 0.01:
				var seg_offset: float = (length + gap) * 0.25  # midpoint of left seg
				_add_wall_segment(transforms, base_pos - axis * seg_offset, axis, seg_len, y_rot, wall_h, y_scale, grid, native_w)
				_add_wall_segment(transforms, base_pos + axis * seg_offset, axis, seg_len, y_rot, wall_h, y_scale, grid, native_w)
		else:
			_add_wall_segment(transforms, base_pos, axis, length, y_rot, wall_h, y_scale, grid, native_w)
	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	# Group tag — LoS culler reads &"room_geometry" each physics tick and
	# hides MMIs whose room isn't adjacent to the player's. Big perf win
	# at horde density since each hidden MMI skips its vertex pass + any
	# shadow-map contribution.
	ctx.root.add_child(mmi)
	mmi.add_to_group(&"structures")
	mmi.add_to_group(&"room_geometry")


# Append wall-panel transforms for a continuous wall segment of `length`
# meters, centered at `segment_center`, running along `axis`. Uses
# adaptive placement (n_panels = round(length/grid), step = length/n)
# so segments fit exactly with no end gaps. Shared by room walls (split
# at doors) and corridor walls (one segment per side).
static func _add_wall_segment(out: Array[Transform3D], segment_center: Vector3, axis: Vector3, length: float, y_rot: float, wall_h: float, y_scale: float, grid: float, native_w: float) -> void:
	var n_panels: int = max(1, int(round(length / grid)))
	var actual_step: float = length / float(n_panels)
	var x_scale: float = actual_step / native_w
	# Rotate -90° around X so the model's long Z axis (native 2m) becomes
	# world +Y (height). +90° would have flipped it to -Y, leaving the
	# panel upside-down. With this rotation:
	#   local X (width) → world X (wall axis) — scale by x_scale
	#   local Y (thickness) → world -Z — leave at native 0.15m
	#   local Z (height) → world Y — scale by y_scale
	# Note y_scale goes in the *third* slot of the scale vector because
	# it applies to local Z (the height axis after rotation), not local Y
	# (which is the thin axis).
	var basis_x_up := Basis(Vector3.RIGHT, -PI * 0.5)
	var basis := Basis(Vector3.UP, y_rot) * basis_x_up
	basis = basis.scaled(Vector3(x_scale, 1.0, y_scale))
	for i in range(n_panels):
		var slot_center: float = (i + 0.5) * actual_step - length * 0.5
		var pos := segment_center + axis * slot_center + Vector3(0, wall_h * 0.5, 0)
		out.append(Transform3D(basis, pos))


# Walks a PackedScene to extract its first MeshInstance3D's Mesh. Caches
# on ctx so we don't repeatedly instantiate the .glb across rooms.
static func _get_kit_mesh(ctx: LevelBuildContext, scene: PackedScene, is_wall: bool) -> Mesh:
	if is_wall and ctx.wall_kit_mesh != null:
		return ctx.wall_kit_mesh
	if not is_wall and ctx.floor_kit_mesh != null:
		return ctx.floor_kit_mesh
	var inst := scene.instantiate()
	var mesh := _find_first_mesh_in_kit(inst)
	inst.queue_free()
	if is_wall:
		ctx.wall_kit_mesh = mesh
	else:
		ctx.floor_kit_mesh = mesh
	return mesh


static func _find_first_mesh_in_kit(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh
	for child in node.get_children():
		var m := _find_first_mesh_in_kit(child)
		if m != null:
			return m
	return null


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

	# Diagonal baffle quads inside each corner cube — seals any sub-pixel
	# sightline that could pass between perpendicular wall faces meeting at
	# a shared edge. Double-sided (two opposing vquads) so the face is
	# visible regardless of camera angle.
	_add_corner_baffles(st, cx, cz, ox, oz, ix, iz, h)

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
	# Extend below the floor plane so the wall-floor junction overlaps
	# rather than meeting at a shared edge (seals rasterizer precision gaps).
	bl = Vector3(bl.x, bl.y - ROOM_WALL_FLOOR_SINK, bl.z)
	br = Vector3(br.x, br.y - ROOM_WALL_FLOOR_SINK, br.z)
	var tl := bl + Vector3(0, h + ROOM_WALL_FLOOR_SINK, 0)
	var top_right := br + Vector3(0, h + ROOM_WALL_FLOOR_SINK, 0)
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
		# Top segments — extended to ±oz (from ±iz) so the wall top covers
		# the corner cube directly, not relying on the N/S wall top alone.
		_hquad_top(st, min_x, cz - oz, max_x, cz - hg, h)
		_hquad_top(st, min_x, cz + hg, max_x, cz + oz, h)
	else:
		if is_east:
			_vquad(st, Vector3(outer_x, 0, cz + oz), Vector3(outer_x, 0, cz - oz), h)
			# Inner extended to ±oz (was ±iz) — covers the corner cube's
			# inside face. Same rationale as the has_opening branch above.
			_vquad(st, Vector3(inner_x, 0, cz - oz), Vector3(inner_x, 0, cz + oz), h)
		else:
			_vquad(st, Vector3(outer_x, 0, cz - oz), Vector3(outer_x, 0, cz + oz), h)
			_vquad(st, Vector3(inner_x, 0, cz + oz), Vector3(inner_x, 0, cz - oz), h)
		# Extended to ±oz (from ±iz) — same corner-coverage fix as above.
		_hquad_top(st, min_x, cz - oz, max_x, cz + oz, h)


# Adds a double-sided diagonal vertical quad inside each of the four room
# corner cubes. Each baffle runs from the inner-face edge (ix, iz) to the
# outer-face edge (ox, oz), creating an opaque plane that blocks any
# sub-pixel sightline through the corner where two perpendicular walls meet.
static func _add_corner_baffles(st: SurfaceTool, cx: float, cz: float,
		ox: float, oz: float, ix: float, iz: float, h: float) -> void:
	# NE corner: inner edge at (cx+ix, cz-iz), outer edge at (cx+ox, cz-oz)
	_vquad(st, Vector3(cx + ix, 0, cz - iz), Vector3(cx + ox, 0, cz - oz), h)
	_vquad(st, Vector3(cx + ox, 0, cz - oz), Vector3(cx + ix, 0, cz - iz), h)
	# NW corner: inner edge at (cx-ix, cz-iz), outer edge at (cx-ox, cz-oz)
	_vquad(st, Vector3(cx - ox, 0, cz - oz), Vector3(cx - ix, 0, cz - iz), h)
	_vquad(st, Vector3(cx - ix, 0, cz - iz), Vector3(cx - ox, 0, cz - oz), h)
	# SE corner: inner edge at (cx+ix, cz+iz), outer edge at (cx+ox, cz+oz)
	_vquad(st, Vector3(cx + ox, 0, cz + oz), Vector3(cx + ix, 0, cz + iz), h)
	_vquad(st, Vector3(cx + ix, 0, cz + iz), Vector3(cx + ox, 0, cz + oz), h)
	# SW corner: inner edge at (cx-ix, cz+iz), outer edge at (cx-ox, cz+oz)
	_vquad(st, Vector3(cx - ix, 0, cz + iz), Vector3(cx - ox, 0, cz + oz), h)
	_vquad(st, Vector3(cx - ox, 0, cz + oz), Vector3(cx - ix, 0, cz + iz), h)
