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


# Collision-only wall (no visible mesh) — room walls draw their geometry from
# the kit panel MMI (or the procedural room mesh), so jamb segments only need
# physics bodies. A SHADOW-ONLY BoxMesh child is attached so the wall still
# occludes light from the per-room ceiling fluorescents — without this, kit-
# panel MMIs (cast_shadow OFF) would let light leak through walls into
# adjacent rooms. The shadow box matches the collision dims exactly.
static func create_wall_body(ctx: LevelBuildContext, pos: Vector3, size_x: float, size_z: float) -> void:
	var body := StaticBody3D.new()
	body.transform.origin = pos + Vector3(0, ctx.theme.wall_height * 0.5, 0)
	body.input_ray_pickable = false
	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = get_wall_shape(ctx, size_x, size_z)
	body.add_child(col)
	_add_shadow_caster(body, size_x, ctx.theme.wall_height, size_z)
	ctx.root.add_child(body)
	body.add_to_group(&"structures")
	# room_geometry → LoS culler hides this body when the room is offscreen.
	# Shadow-only meshes still incur shadow-pass cost when their parent is
	# visible, so culling them with the rest of the room geometry is what
	# actually buys the perf win.
	body.add_to_group(&"room_geometry")


# Attaches an invisible BoxMesh child to `parent` that casts shadow only.
# 12-tri silhouette; the per-cubemap-face cost is negligible compared to the
# detailed kit panel geometry it replaces in the shadow pass.
static func _add_shadow_caster(parent: Node3D, sx: float, sy: float, sz: float) -> void:
	var caster := MeshInstance3D.new()
	caster.name = &"ShadowCaster"
	var box := BoxMesh.new()
	box.size = Vector3(sx, sy, sz)
	caster.mesh = box
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(caster)


# Corner-cube shadow caster: a `thick × h × thick` invisible BoxMesh at a
# room corner. Plugs the gap between two perpendicular wall bodies (which
# stop at the room boundary, `span/2` from center) and the kit-panel MMIs
# (which extend `thick/2` past that into the corner cube). Without it,
# ceiling fluorescents in adjacent rooms light through the corner.
static func create_corner_cube_shadow(ctx: LevelBuildContext, world_xz: Vector3) -> void:
	var thick: float = ctx.theme.wall_thickness
	var h: float = ctx.theme.wall_height
	var caster := MeshInstance3D.new()
	caster.name = &"CornerCubeShadow"
	var box := BoxMesh.new()
	box.size = Vector3(thick, h, thick)
	caster.mesh = box
	caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.position = Vector3(world_xz.x, h * 0.5, world_xz.z)
	ctx.root.add_child(caster)
	caster.add_to_group(&"structures")
	caster.add_to_group(&"room_geometry")


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
# Instances theme.wall_model once per wall segment, stretching the panel to
# exactly fit the collision box (length, height, thickness all sized from
# the corresponding collision dims). Mesh AABB is read at runtime so the
# scaling is correct regardless of what dimensions the .glb actually has —
# wall_model_native_* fields on LevelTheme are ignored. Doors split a wall
# into two segments; each segment gets one stretched panel.
# Collision is built separately by _build_room_wall_collisions in
# level_builder; these MMIs are visual-only.

# Kit-bash corridor walls. Two parallel walls along the corridor's travel
# axis, each tiled with panels stretched to wall_height × wall_thickness.
# Wall length splits into N panels of ~wall_grid_size each (round to fit),
# so the kit's panel detail repeats along the wall instead of stretching.
# Walls sit at ±(cd.width/2 + thick/2) perpendicular, matching the
# procedural `build_corridor_walls` (cd.width = walkable width).
static func build_corridor_walls_kit(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var t := ctx.theme
	if t.wall_model == null:
		return
	var mesh := _get_kit_mesh(ctx, t.wall_model, true)
	if mesh == null:
		return
	# Raw AABB is what MMI actually renders (scene-transform-free vertex
	# bounds). Visual AABB is what the .glb looks like in editor preview —
	# used to choose a tile step that matches the design-time panel width.
	var aabb: AABB = ctx.wall_kit_aabb
	var tile_w: float = maxf(0.01, ctx.wall_kit_aabb_visual.size.x)
	var wall_h: float = t.wall_height
	var thick: float = t.wall_thickness
	var along_z := cd.axis == CorridorDef.Axis.Z
	var hw: float = cd.width * 0.5 + thick * 0.5

	# y_rot orients the decorated face (+Y in model space) inward toward the
	# corridor center. Same face-direction logic as room walls:
	# face → (sin(y_rot), 0, cos(y_rot)) after cross rotation.
	var sides: Array[Dictionary]
	if along_z:
		# Walls at ±X (like room E/W): face ∓X.
		sides = [
			{"axis": Vector3.FORWARD, "base_pos": Vector3(hw, 0, 0), "y_rot": -PI * 0.5},
			{"axis": Vector3.FORWARD, "base_pos": Vector3(-hw, 0, 0), "y_rot": PI * 0.5},
		]
	else:
		# Walls at ±Z (like room N/S): face ∓Z.
		sides = [
			{"axis": Vector3.RIGHT, "base_pos": Vector3(0, 0, hw), "y_rot": PI},
			{"axis": Vector3.RIGHT, "base_pos": Vector3(0, 0, -hw), "y_rot": 0.0},
		]

	# Wall length: cd.length - thick so the wall butts cleanly against each
	# connecting room's outer face plane. Note: at L/X/T junctions where two
	# perpendicular corridors share a room corner, the corridor walls
	# overlap each other in a small corner cube (z-fight on coplanar tops).
	# Acceptable for now; alternative (more trim) leaves visible gaps at
	# every corridor-room junction, not just the perpendicular ones.
	var wall_len: float = maxf(0.01, cd.length - thick)
	var transforms: Array[Transform3D] = []
	var custom_data: Array[Color] = []
	for s: Dictionary in sides:
		_add_tiled_wall_segment(transforms, custom_data, s["base_pos"], s["axis"], wall_len, wall_h, thick, tile_w, s["y_rot"], aabb)

	_commit_kit_mmi(ctx, center, mesh, transforms, custom_data)

	# Collision + shadow casters for each corridor wall side. The kit MMI
	# above is visual-only (no collision, no shadow); without these the
	# player would clip through corridor walls AND fluorescents in adjacent
	# rooms would light through them. Sizing matches the procedural
	# `build_corridor_walls` extents (`thick` perpendicular, `wall_len`
	# along the corridor axis).
	for s: Dictionary in sides:
		var base_pos: Vector3 = s["base_pos"]
		var axis: Vector3 = s["axis"]
		# axis = wall-tangent (along its length). Wall extent: wall_len along
		# this axis, `thick` along the perpendicular horizontal axis.
		var col_sx: float = wall_len if absf(axis.x) > 0.5 else thick
		var col_sz: float = wall_len if absf(axis.z) > 0.5 else thick
		create_wall_body(ctx, center + base_pos, col_sx, col_sz)


# Kit-bash room walls. Each wall is tiled with panels along its length so
# the kit's natural panel-width detail repeats instead of stretching.
# Wall span includes the corner overlap (`rd.size + thick`) so the visual
# matches the per-wall collision built by _build_room_wall_collisions.
# Door openings split the wall into two jamb segments, sized to match the
# jamb collision bodies exactly.
static func build_room_walls_kit(ctx: LevelBuildContext, center: Vector3, rd: RoomDef) -> void:
	var t := ctx.theme
	if t.wall_model == null:
		return
	var mesh := _get_kit_mesh(ctx, t.wall_model, true)
	if mesh == null:
		return
	# See build_corridor_walls_kit for raw vs visual AABB rationale.
	var aabb: AABB = ctx.wall_kit_aabb
	var tile_w: float = maxf(0.01, ctx.wall_kit_aabb_visual.size.x)
	var hx := rd.size.x * 0.5
	var hz := rd.size.y * 0.5
	var wall_h: float = t.wall_height
	var thick: float = t.wall_thickness
	var gap: float = rd.opening_width

	# y_rot orients the panel so its decorated face (+Y in model space) points
	# INWARD toward the room center. After the cross rotation Basis(RIGHT,
	# PI/2) that maps model Z→world -Y (height), model +Y ends up along +Z,
	# then Basis(UP, y_rot) sweeps it to: (sin(y_rot), 0, cos(y_rot)).
	# N: at -Z, inward=+Z → cos=1 → y_rot=0.    S: at +Z, inward=-Z → y_rot=PI.
	# E: at +X, inward=-X → sin=-1 → y_rot=-PI/2.  W: at -X, inward=+X → y_rot=PI/2.
	var sides: Array[Dictionary] = [
		{"side": RoomDef.Wall.NORTH, "axis": Vector3.RIGHT, "base_pos": Vector3(0, 0, -hz), "length": rd.size.x, "y_rot": 0.0},
		{"side": RoomDef.Wall.SOUTH, "axis": Vector3.RIGHT, "base_pos": Vector3(0, 0, hz), "length": rd.size.x, "y_rot": PI},
		{"side": RoomDef.Wall.EAST, "axis": Vector3.FORWARD, "base_pos": Vector3(hx, 0, 0), "length": rd.size.y, "y_rot": -PI * 0.5},
		{"side": RoomDef.Wall.WEST, "axis": Vector3.FORWARD, "base_pos": Vector3(-hx, 0, 0), "length": rd.size.y, "y_rot": PI * 0.5},
	]

	var transforms: Array[Transform3D] = []
	var custom_data: Array[Color] = []
	for s: Dictionary in sides:
		var side: RoomDef.Wall = s["side"] as RoomDef.Wall
		var axis: Vector3 = s["axis"]
		var base_pos: Vector3 = s["base_pos"]
		var length: float = s["length"]
		var y_rot: float = s["y_rot"]
		# Visual span extends `thick` past nominal length so the leftmost and
		# rightmost panels reach into the corner cubes (where two perpendicular
		# walls meet). The mitre clip in kit_panel.gdshader then splits the
		# overlap diagonally — without this extension the corner cubes are
		# visibly empty no matter what the mitre flags say. Collision still
		# uses `rd.size` (built in _build_room_wall_collisions), so the visual
		# extension doesn't change the walkable footprint.
		var span: float = length + thick
		if side in rd.openings:
			# Two segments flanking the opening. Each jamb's length matches
			# the jamb collision body built by _build_room_wall_collisions.
			var jamb_len: float = (span - gap) * 0.5
			if jamb_len > 0.01:
				var offset: float = (gap + jamb_len) * 0.5
				_add_tiled_wall_segment(transforms, custom_data, base_pos + axis * offset, axis, jamb_len, wall_h, thick, tile_w, y_rot, aabb)
				_add_tiled_wall_segment(transforms, custom_data, base_pos - axis * offset, axis, jamb_len, wall_h, thick, tile_w, y_rot, aabb)
		else:
			_add_tiled_wall_segment(transforms, custom_data, base_pos, axis, span, wall_h, thick, tile_w, y_rot, aabb)
	if transforms.is_empty():
		return

	_commit_kit_mmi(ctx, center, mesh, transforms, custom_data)


# Tiles panels across a wall segment in BOTH dimensions. Horizontally, N
# panels of ~native width tile across `length`. Vertically, M panels of
# ~native height stack to fill `wall_h`. Stretching is minimal in each
# axis (step / native), so authored detail reads naturally instead of
# getting distorted into tall narrow strips when the panel's native size
# doesn't match the wall span (e.g. wall_panel_v6 is a 1m floor tile used
# as a 3m wall — without vertical tiling it'd stretch 3x).
#
# Mitre flags depend only on horizontal index — corner cubes are vertical
# columns at room corners, so every row of the leftmost / rightmost panel
# needs the same diagonal clip.
#
# Axis detection: Blender→glTF→Godot typically maps height to local Y
# (Y-up), but some exports keep height in local Z. We detect which axis
# is taller and choose the rotation/scale accordingly. y_rot picks which
# wall side the panel faces.
static func _add_tiled_wall_segment(out: Array[Transform3D], custom_data_out: Array[Color], segment_center: Vector3, axis: Vector3, length: float, wall_h: float, thick: float, grid: float, y_rot: float, aabb: AABB) -> void:
	var native_w: float = maxf(0.0001, aabb.size.x)
	var n_panels: int = max(1, int(round(length / maxf(0.01, grid))))
	var step: float = length / float(n_panels)
	var scale_w: float = step / native_w
	var height_in_y: bool = aabb.size.y > aabb.size.z
	var native_h: float
	if height_in_y:
		native_h = maxf(0.0001, aabb.size.y)
	else:
		native_h = maxf(0.0001, aabb.size.z)
	# Vertical tile count: round wall_h to the nearest multiple of native_h
	# so panels stack with minimal vertical squash/stretch. wall_h=3, native=1
	# gives 3 stacked rows; wall_h=3, native=3 gives 1 row (current behaviour
	# for assets authored at full wall height like wall_panel_v5).
	var n_v: int = max(1, int(round(wall_h / native_h)))
	var step_v: float = wall_h / float(n_v)
	var v_scale: float = step_v / native_h
	var rotation: Basis
	var basis: Basis
	# Panel thickness is kept at native scale — the canonical AABB.size.y is
	# the post-import-thickened value (≈ wall_thickness, see kit_panel
	# post-import). Multiplying by 1 keeps it at that authored thickness.
	if height_in_y:
		rotation = Basis(Vector3.UP, y_rot)
		# LOCAL-space scale: model x=width, y=height, z=thickness (native).
		basis = rotation * Basis.from_scale(Vector3(scale_w, v_scale, 1.0))
	else:
		# Height in Z: rotate Z→Y via Basis(RIGHT, +PI/2). Positive angle
		# keeps the panel right-side-up (model bottom → world bottom).
		rotation = Basis(Vector3.UP, y_rot) * Basis(Vector3.RIGHT, PI * 0.5)
		# LOCAL-space scale: model x=width, y=thickness (native), z=height.
		basis = rotation * Basis.from_scale(Vector3(scale_w, 1.0, v_scale))
	# AABB-center compensation: the mesh's local-space AABB center may not
	# be at the origin (a bottom-anchored panel has its center at +h/2 in
	# local Z). Computing translation = center - basis * aabb_center makes
	# the AABB center land at the slot center for each panel.
	var aabb_center_local: Vector3 = aabb.position + aabb.size * 0.5
	var rotated_center: Vector3 = basis * aabb_center_local
	for j in range(n_v):
		var v_offset: float = (j + 0.5) * step_v
		for i in range(n_panels):
			var slot_offset: float = (i + 0.5) * step - length * 0.5
			var slot_center: Vector3 = segment_center + axis * slot_offset + Vector3(0, v_offset, 0)
			out.append(Transform3D(basis, slot_center - rotated_center))
			# Mitre flags + per-instance scale:
			#   .r (x) = mitre_left  (1 if first column of the segment)
			#   .g (y) = mitre_right (1 if last column of the segment)
			#   .b (z) = scale_w     (panel's X-axis Transform3D scale)
			# Vertical rows share the same horizontal mitre status — the
			# corner cube is a vertical column running from floor to ceiling.
			var mitre_left: float = 1.0 if i == 0 else 0.0
			var mitre_right: float = 1.0 if i == n_panels - 1 else 0.0
			custom_data_out.append(Color(mitre_left, mitre_right, scale_w, 0.0))


# Wraps a transform list in a MultiMeshInstance3D parented to ctx.root at
# `center`. Tags it as both `structures` (for general world queries) and
# `room_geometry` (LoS culler hides this MMI when the player isn't near).
# `custom_data` (same length as `transforms`) supplies per-instance values
# the kit_panel.gdshader reads from INSTANCE_CUSTOM (mitre flags etc).
# Pass an empty array when not needed and custom-data export stays off.
static func _commit_kit_mmi(ctx: LevelBuildContext, center: Vector3, mesh: Mesh, transforms: Array[Transform3D], custom_data: Array[Color] = []) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var use_custom: bool = custom_data.size() == transforms.size()
	mm.use_custom_data = use_custom
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		if use_custom:
			mm.set_instance_custom_data(i, custom_data[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = center
	# Kit panels are too detailed to cast shadow per-cubemap-face on every
	# shadow-casting light. The post-import script replaces the mesh with
	# an ArrayMesh, which loses Godot's auto-generated shadow mesh — so each
	# face of each shadow cubemap renders the FULL panel geometry. At 58M
	# tri/frame that was the dominant bottleneck. Shadows are now cast by
	# invisible BoxMesh caster boxes (see create_wall_shadow_caster /
	# build_corridor_walls_kit) which are 12 tris each and reproduce the
	# same wall silhouette for shadow purposes.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ctx.root.add_child(mmi)
	mmi.add_to_group(&"structures")
	mmi.add_to_group(&"room_geometry")


# Walks a PackedScene to extract its first MeshInstance3D's Mesh, plus
# the EFFECTIVE AABB (baked with the .glb's root + intermediate-node
# transforms). The raw `mesh.get_aabb()` returns vertex bounds in mesh-
# local space and ignores the scene's transform chain — that's wrong
# whenever the .glb has a root scale (common in Godot's .glb importer).
# Caches both on ctx so we only instantiate the .glb scene once.
static func _get_kit_mesh(ctx: LevelBuildContext, scene: PackedScene, is_wall: bool) -> Mesh:
	if is_wall and ctx.wall_kit_mesh != null:
		return ctx.wall_kit_mesh
	if not is_wall and ctx.floor_kit_mesh != null:
		return ctx.floor_kit_mesh
	var inst := scene.instantiate()
	var result := _find_first_mesh_in_kit(inst)
	inst.queue_free()
	if result.is_empty():
		return null
	var mesh: Mesh = result[&"mesh"]
	var xform: Transform3D = result[&"xform"]
	var raw_aabb: AABB = mesh.get_aabb()
	var visual_aabb: AABB = xform * raw_aabb
	if is_wall:
		ctx.wall_kit_mesh = mesh
		ctx.wall_kit_aabb = raw_aabb
		ctx.wall_kit_aabb_visual = visual_aabb
	else:
		ctx.floor_kit_mesh = mesh
		ctx.floor_kit_aabb = raw_aabb
		ctx.floor_kit_aabb_visual = visual_aabb
	return mesh


# Walks a PackedScene tree to find the first MeshInstance3D, returning the
# mesh + the cumulative Transform3D from the scene root down to that node.
# Multiplying that transform into the mesh's AABB gives the visual AABB
# (what the scene would render if instantiated directly).
static func _find_first_mesh_in_kit(node: Node, parent_xform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return {&"mesh": mi.mesh, &"xform": xform}
	for child in node.get_children():
		var result := _find_first_mesh_in_kit(child, xform)
		if not result.is_empty():
			return result
	return {}


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
