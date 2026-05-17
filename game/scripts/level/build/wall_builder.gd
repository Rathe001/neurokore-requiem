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
	# Wall center is offset OUTWARD by half-thickness from `cd.width / 2` so
	# the wall's INNER face sits at ±cd.width/2 (= the corridor's walkable
	# half-width). This means cd.width is the corridor's walkable interior
	# width, and when corridor.width = door.opening_width (synced in
	# graph_solver) the corridor wall's inner face lines up exactly with the
	# door jamb edge. Without the +thick/2 offset, cd.width was wall-center
	# distance and the walkable corridor was narrower than the door by
	# wall_thickness — a visible step at the door/corridor junction.
	var hw := cd.width * 0.5 + thick * 0.5
	var wall_y := CORRIDOR_WALL_Y_BIAS
	# Length extension: walls butt against each room's outer wall face exactly.
	# graph_solver puts the corridor's nominal endpoints at the connecting
	# rooms' BOUNDARIES (= wall centerlines). The room outer face is `thick/2`
	# closer to the corridor center than the boundary, so to end the corridor
	# wall AT the outer face we shorten each end by `thick/2` → ext = -thick.
	# Earlier we kept a SEAM overlap "into" the room wall to seal sub-pixel
	# gaps, but with the new mitred room geometry that overlap puts both
	# walls' top faces coplanar at y=h in a 0.4×0.02m strip and z-fights
	# visibly. Clean butt-join (zero overlap) gives a single shared edge at
	# the outer-face plane, which renders consistently.
	var ext := -thick
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
# via SurfaceTool. Corners are mitred at 45°: each wall's footprint is a
# trapezoid whose inner edge stops at ±ix and outer edge stops at ±ox. Two
# perpendicular walls' trapezoids meet along the same diagonal seam at each
# room corner — no overlap, no gap, no exposed mitre face (the seam is the
# shared boundary between the two walls' material, hidden from every
# reachable viewpoint). Door openings split the wall into two segments,
# each mitred at the corner end and flat at the door-jamb end; jamb
# reveals are added at the door-opening sides. Collision is built
# separately by _build_room_wall_collisions().

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
	var hg: float = rd.opening_width * 0.5

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Room corner points (outer + inner) at y=0. Two perpendicular walls'
	# trapezoids share the diagonal from `*_i` to `*_o` at each corner.
	var nw_o := Vector3(cx - ox, 0, cz - oz)
	var nw_i := Vector3(cx - ix, 0, cz - iz)
	var ne_o := Vector3(cx + ox, 0, cz - oz)
	var ne_i := Vector3(cx + ix, 0, cz - iz)
	var se_o := Vector3(cx + ox, 0, cz + oz)
	var se_i := Vector3(cx + ix, 0, cz + iz)
	var sw_o := Vector3(cx - ox, 0, cz + oz)
	var sw_i := Vector3(cx - ix, 0, cz + iz)

	# NORTH wall (z=-oz outer, z=-iz inner, runs along X from NW to NE).
	_add_mitred_wall(st, h,
		nw_o, nw_i, ne_o, ne_i,
		Vector3(cx - hg, 0, cz - oz), Vector3(cx - hg, 0, cz - iz),
		Vector3(cx + hg, 0, cz - oz), Vector3(cx + hg, 0, cz - iz),
		RoomDef.Wall.NORTH in rd.openings)
	# SOUTH wall (z=+iz inner, z=+oz outer, runs along X from SW to SE).
	_add_mitred_wall(st, h,
		sw_o, sw_i, se_o, se_i,
		Vector3(cx - hg, 0, cz + oz), Vector3(cx - hg, 0, cz + iz),
		Vector3(cx + hg, 0, cz + oz), Vector3(cx + hg, 0, cz + iz),
		RoomDef.Wall.SOUTH in rd.openings)
	# EAST wall (x=+ox outer, x=+ix inner, runs along Z from NE to SE).
	_add_mitred_wall(st, h,
		ne_o, ne_i, se_o, se_i,
		Vector3(cx + ox, 0, cz - hg), Vector3(cx + ix, 0, cz - hg),
		Vector3(cx + ox, 0, cz + hg), Vector3(cx + ix, 0, cz + hg),
		RoomDef.Wall.EAST in rd.openings)
	# WEST wall (x=-ox outer, x=-ix inner, runs along Z from NW to SW).
	_add_mitred_wall(st, h,
		nw_o, nw_i, sw_o, sw_i,
		Vector3(cx - ox, 0, cz - hg), Vector3(cx - ix, 0, cz - hg),
		Vector3(cx - ox, 0, cz + hg), Vector3(cx - ix, 0, cz + hg),
		RoomDef.Wall.WEST in rd.openings)

	# No separate corner-mitre faces: each wall's trapezoidal top + outer/inner
	# faces tile flush with its neighbour at the diagonal seam. The mitre is
	# the shared boundary between two adjacent walls' material, hidden from
	# every reachable viewpoint. Replaces the corner-cube baffles from the
	# old overlap geometry — no overlap means no sub-pixel sightline blockers
	# are needed.

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
# generate_normals() averages vertices that share the same position. UVs are
# set 0–1 over the quad so debug/PBR shaders that key off UV (e.g. the
# debug-block border) render correctly.
static func _vquad(st: SurfaceTool, bl: Vector3, br: Vector3, h: float) -> void:
	# Extend below the floor plane so the wall-floor junction overlaps
	# rather than meeting at a shared edge (seals rasterizer precision gaps).
	bl = Vector3(bl.x, bl.y - ROOM_WALL_FLOOR_SINK, bl.z)
	br = Vector3(br.x, br.y - ROOM_WALL_FLOOR_SINK, br.z)
	var tl := bl + Vector3(0, h + ROOM_WALL_FLOOR_SINK, 0)
	var top_right := br + Vector3(0, h + ROOM_WALL_FLOOR_SINK, 0)
	var n := (br - bl).cross(tl - bl).normalized()
	st.set_normal(n)
	# UVs: bl=(0,0), br=(1,0), top_right=(1,1), tl=(0,1).
	st.set_uv(Vector2(0, 0)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(top_right)
	st.set_uv(Vector2(1, 0)); st.add_vertex(br)
	st.set_uv(Vector2(0, 0)); st.add_vertex(bl)
	st.set_uv(Vector2(0, 1)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(top_right)


# Adds a horizontal quad at height y with normal +Y (CCW from above).
# x1>x0, z1>z0 required.
static func _hquad_top(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	var a := Vector3(x0, y, z0)
	var b := Vector3(x0, y, z1)
	var c := Vector3(x1, y, z1)
	var d := Vector3(x1, y, z0)
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 1)); st.add_vertex(b)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(d)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)


# Adds one wall (full or split by a door opening) with mitred ends at the
# room corners. Inputs are the four wall corner points at y=0:
#   *_o : outer corner (room outer boundary, ±ox/±oz)
#   *_i : inner corner (room inner boundary, ±ix/±iz)
# Plus the door-opening edge points (used only when has_opening is true).
# Wall axis direction is start→end; perpendicular thickness is outer→inner.
# Each segment renders outer face, inner face, top quad (trapezoidal at the
# mitred end), and a door-jamb reveal face when the segment terminates at
# the opening. The mitred wall ends have no end-cap face — the perpendicular
# wall's trapezoid covers that boundary from its own side.
static func _add_mitred_wall(st: SurfaceTool, h: float,
		start_o: Vector3, start_i: Vector3, end_o: Vector3, end_i: Vector3,
		gap_start_o: Vector3, gap_start_i: Vector3,
		gap_end_o: Vector3, gap_end_i: Vector3,
		has_opening: bool) -> void:
	if not has_opening:
		_add_mitred_segment(st, start_o, start_i, end_o, end_i, h)
		return
	# Two segments flanking the door opening. Each has a mitred corner end
	# and a flat door-jamb end. The flat end is where the door reveal sits.
	_add_mitred_segment(st, start_o, start_i, gap_start_o, gap_start_i, h)
	_add_mitred_segment(st, gap_end_o, gap_end_i, end_o, end_i, h)
	# Door jamb reveal faces — the two perpendicular faces inside the opening.
	# Each runs from the inner-edge gap point to the outer-edge gap point,
	# with its normal pointing into the door gap (toward the other jamb).
	_add_oriented_vquad(st, gap_start_i, gap_start_o, gap_end_i - gap_start_i, h)
	_add_oriented_vquad(st, gap_end_i, gap_end_o, gap_start_i - gap_end_i, h)


# A wall segment with arbitrary 4-corner footprint. Builds outer face, inner
# face, and top quad. End-cap faces (mitre corners, door reveals) are added
# by the caller. Corners (all at y=0):
#   so → eo : outer edge of the segment (faces outward)
#   si → ei : inner edge (faces room interior)
# Caller arranges so→si as the wall thickness vector at the start, eo→ei as
# the thickness vector at the end — these can be axis-aligned (flat end) or
# diagonal (mitred end), the helper handles both.
static func _add_mitred_segment(st: SurfaceTool, so: Vector3, si: Vector3, eo: Vector3, ei: Vector3, h: float) -> void:
	# Outer face: from so to eo, normal points outward (from inner toward outer).
	_add_oriented_vquad(st, so, eo, so - si, h)
	# Inner face: from si to ei, normal points inward (toward room interior).
	_add_oriented_vquad(st, si, ei, si - so, h)
	# Top quad: walk the segment perimeter CCW from +Y (outer→outer→inner→inner).
	_quad_top(st, so, eo, ei, si, h)


# Adds a vertical quad spanning from `a` to `b` at the base (extruded
# upward by h), with the face normal oriented to match `desired_normal_dir`
# (the helper flips winding if needed). Use this whenever the face's
# orientation matters (it always does — wrong winding = backface culled).
static func _add_oriented_vquad(st: SurfaceTool, a: Vector3, b: Vector3, desired_normal_dir: Vector3, h: float) -> void:
	# _vquad's normal = (br - bl) × UP. We want this to align with
	# desired_normal_dir. If (b - a) × UP is anti-parallel to desired_normal_dir,
	# swap a and b so _vquad's winding produces the right normal.
	var test := (b - a).cross(Vector3.UP)
	if test.dot(desired_normal_dir) < 0.0:
		_vquad(st, b, a, h)
	else:
		_vquad(st, a, b, h)


# A 4-corner horizontal quad at height h. The four points form the
# perimeter; the helper picks CCW-from-+Y winding so the normal points up.
# Handles both rectangles (uniform thickness walls) and trapezoids (mitred
# wall tops where the outer edge is longer than the inner edge).
static func _quad_top(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, h: float) -> void:
	var a := p0 + Vector3(0, h, 0)
	var b := p1 + Vector3(0, h, 0)
	var c := p2 + Vector3(0, h, 0)
	var d := p3 + Vector3(0, h, 0)
	# Test perimeter winding: (b-a) × (c-a) should have positive Y for CCW.
	if (b - a).cross(c - a).y < 0.0:
		# Currently CW from +Y — reverse perimeter direction.
		var tmp := b
		b = d
		d = tmp
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(a)
	st.set_uv(Vector2(1, 1)); st.add_vertex(c)
	st.set_uv(Vector2(0, 1)); st.add_vertex(d)
