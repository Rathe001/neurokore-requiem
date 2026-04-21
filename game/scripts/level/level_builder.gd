extends Node3D
class_name LevelBuilder

const ENEMY_SCENE_DEFAULT: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")
const DOOR_SCENE: PackedScene = preload("res://scenes/prototype/prototype_door.tscn")
const _DOOR_MESH_WIDTH := 4.0  # door scene mesh Z-extent
const _SEAM := 0.02  # anti-z-fight gap for corridor walls abutting room geometry

@export var layout: LevelLayout

var _wall_material: Material
var _floor_material: Material
var _wall_meshes: Dictionary = {}
var _wall_shapes: Dictionary = {}
var _doors: Dictionary = {}
var _fog_material: FogMaterial

func _ready() -> void:
	if layout == null:
		push_warning("[LevelBuilder] No layout assigned.")
		return
	_init_shared_resources()
	_build_ground()
	for piece: LevelPiece in layout.pieces:
		if piece.room != null:
			_build_room(piece)
		elif piece.corridor != null:
			_build_corridor(piece)

# ── Shared Resources ─────────────────────────────────────────────────────

func _init_shared_resources() -> void:
	var t := layout.theme
	if t == null:
		push_warning("[LevelBuilder] Layout has no theme.")
		return

	if t.wall_shader != null:
		_wall_material = ShaderMaterial.new()
		_wall_material.shader = t.wall_shader
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = t.wall_color
		mat.metallic = t.wall_metallic
		mat.roughness = t.wall_roughness
		_wall_material = mat

	if t.floor_shader != null:
		_floor_material = ShaderMaterial.new()
		_floor_material.shader = t.floor_shader
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = t.floor_color
		mat.metallic = t.floor_metallic
		mat.roughness = t.floor_roughness
		_floor_material = mat

	_fog_material = FogMaterial.new()
	_fog_material.density = 0.001
	_fog_material.albedo = Color(1, 1, 1, 1)

# ── Ground ────────────────────────────────────────────────────────────────

func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = layout.ground_size
	if _floor_material != null:
		mesh.material = _floor_material
	var inst := MeshInstance3D.new()
	inst.name = &"Ground"
	inst.mesh = mesh
	add_child(inst)
	inst.add_to_group(&"structures")

# ── Walls ─────────────────────────────────────────────────────────────────

func _get_wall_mesh(size_x: float, size_z: float) -> BoxMesh:
	var key := "%s_%s" % [size_x, size_z]
	if _wall_meshes.has(key):
		return _wall_meshes[key]
	var mesh := BoxMesh.new()
	var t := layout.theme
	mesh.size = Vector3(size_x, t.wall_height, size_z)
	if _wall_material != null:
		mesh.material = _wall_material
	_wall_meshes[key] = mesh
	return mesh

func _get_wall_shape(size_x: float, size_z: float) -> BoxShape3D:
	var key := "%s_%s" % [size_x, size_z]
	if _wall_shapes.has(key):
		return _wall_shapes[key]
	var shape := BoxShape3D.new()
	var t := layout.theme
	shape.size = Vector3(size_x, t.wall_height, size_z)
	_wall_shapes[key] = shape
	return shape

func _create_wall(pos: Vector3, size_x: float, size_z: float) -> StaticBody3D:
	var t := layout.theme
	var body := StaticBody3D.new()
	body.transform.origin = pos + Vector3(0, t.wall_height * 0.5, 0)
	body.input_ray_pickable = false

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = &"Mesh"
	mesh_inst.mesh = _get_wall_mesh(size_x, size_z)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = _get_wall_shape(size_x, size_z)
	body.add_child(col)

	add_child(body)
	body.add_to_group(&"structures")
	return body

func _create_wall_body(pos: Vector3, size_x: float, size_z: float) -> void:
	var t := layout.theme
	var body := StaticBody3D.new()
	body.transform.origin = pos + Vector3(0, t.wall_height * 0.5, 0)
	body.input_ray_pickable = false
	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = _get_wall_shape(size_x, size_z)
	body.add_child(col)
	add_child(body)
	body.add_to_group(&"structures")

# ── Room Mesh Generation ─────────────────────────────────────────────────

# Adds a vertical quad. bl/br are the two bottom corners; the face normal is
# derived from the cross product and the winding is CCW from the normal side
# (Godot's front-face convention). Normals are set explicitly because
# generate_normals() averages vertices that share the same position.
static func _vquad(st: SurfaceTool, bl: Vector3, br: Vector3, h: float) -> void:
	var tl := bl + Vector3(0, h, 0)
	var tr := br + Vector3(0, h, 0)
	var n := (br - bl).cross(tl - bl).normalized()
	st.set_normal(n)
	st.add_vertex(bl); st.add_vertex(tr); st.add_vertex(br)
	st.add_vertex(bl); st.add_vertex(tl); st.add_vertex(tr)

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

func _build_room_mesh(center: Vector3, rd: RoomDef) -> MeshInstance3D:
	var hx := rd.size.x * 0.5
	var hz := rd.size.y * 0.5
	var t := layout.theme
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
	if _wall_material != null:
		inst.material_override = _wall_material
	return inst

# North/South wall faces.  outer_z/inner_z are world-space z of the two planes.
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
		# Inner segments
		if is_north:
			_vquad(st, Vector3(cx - ix, 0, inner_z), Vector3(cx - hg, 0, inner_z), h)
			_vquad(st, Vector3(cx + hg, 0, inner_z), Vector3(cx + ix, 0, inner_z), h)
		else:
			_vquad(st, Vector3(cx - hg, 0, inner_z), Vector3(cx - ix, 0, inner_z), h)
			_vquad(st, Vector3(cx + ix, 0, inner_z), Vector3(cx + hg, 0, inner_z), h)
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
			_vquad(st, Vector3(cx - ix, 0, inner_z), Vector3(cx + ix, 0, inner_z), h)
		else:
			_vquad(st, Vector3(cx - ox, 0, outer_z), Vector3(cx + ox, 0, outer_z), h)
			_vquad(st, Vector3(cx + ix, 0, inner_z), Vector3(cx - ix, 0, inner_z), h)
		_hquad_top(st, cx - ox, z0, cx + ox, z1, h)

# East/West wall faces.  outer_x/inner_x are world-space x of the two planes.
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
		# Inner segments
		if is_east:
			_vquad(st, Vector3(inner_x, 0, cz - iz), Vector3(inner_x, 0, cz - hg), h)
			_vquad(st, Vector3(inner_x, 0, cz + hg), Vector3(inner_x, 0, cz + iz), h)
		else:
			_vquad(st, Vector3(inner_x, 0, cz - hg), Vector3(inner_x, 0, cz - iz), h)
			_vquad(st, Vector3(inner_x, 0, cz + iz), Vector3(inner_x, 0, cz + hg), h)
		# Reveal faces
		_vquad(st, Vector3(min_x, 0, cz - hg), Vector3(max_x, 0, cz - hg), h)
		_vquad(st, Vector3(max_x, 0, cz + hg), Vector3(min_x, 0, cz + hg), h)
		# Top segments
		_hquad_top(st, min_x, cz - iz, max_x, cz - hg, h)
		_hquad_top(st, min_x, cz + hg, max_x, cz + iz, h)
	else:
		if is_east:
			_vquad(st, Vector3(outer_x, 0, cz + oz), Vector3(outer_x, 0, cz - oz), h)
			_vquad(st, Vector3(inner_x, 0, cz - iz), Vector3(inner_x, 0, cz + iz), h)
		else:
			_vquad(st, Vector3(outer_x, 0, cz - oz), Vector3(outer_x, 0, cz + oz), h)
			_vquad(st, Vector3(inner_x, 0, cz + iz), Vector3(inner_x, 0, cz - iz), h)
		_hquad_top(st, min_x, cz - iz, max_x, cz + iz, h)

# ── Ceiling Lights ────────────────────────────────────────────────────────
# Invisible omni lights mounted just below the ceiling (ceiling is never seen
# by the fixed top-down camera, so no fixture mesh is needed).

const CEILING_CLEARANCE := 0.1
const CEILING_LIGHT_ENERGY_MIN := 4.0
const CEILING_LIGHT_ENERGY_MAX := 11.0
const CEILING_LIGHT_RANGE_MIN := 9.0
const CEILING_LIGHT_RANGE_MAX := 14.0
const CEILING_LIGHT_ATTENUATION := 1.3

func _create_ceiling_light(pos: Vector3, lc: LightColor) -> void:
	var fixture := FluorescentFlicker.new()
	fixture.position = pos

	var light := OmniLight3D.new()
	light.light_color = lc.color
	light.light_energy = randf_range(CEILING_LIGHT_ENERGY_MIN, CEILING_LIGHT_ENERGY_MAX)
	light.omni_range = randf_range(CEILING_LIGHT_RANGE_MIN, CEILING_LIGHT_RANGE_MAX)
	light.omni_attenuation = CEILING_LIGHT_ATTENUATION
	light.shadow_enabled = lc.shadows
	light.light_volumetric_fog_energy = 0.0
	fixture.add_child(light)

	_randomize_flicker_profile(fixture)
	fixture.setup(light, null)
	add_child(fixture)

# Roll a flicker profile per fixture: most lights are steady, some twitch
# subtly, a few are outright broken with fast / deep flickers.
func _randomize_flicker_profile(fixture: FluorescentFlicker) -> void:
	var roll := randf()
	if roll < 0.6:
		# Steady — no flicker at all.
		fixture.flicker_chance = 0.0
		return
	if roll < 0.9:
		# Minor twitch — rare, subtle, fairly quick.
		fixture.flicker_chance = randf_range(0.003, 0.012)
		fixture.flicker_depth = randf_range(0.15, 0.35)
		fixture.flicker_duration = randf_range(0.04, 0.1)
		return
	# Broken — frequent, deep, and varied durations.
	fixture.flicker_chance = randf_range(0.03, 0.08)
	fixture.flicker_depth = randf_range(0.5, 0.85)
	fixture.flicker_duration = randf_range(0.06, 0.22)

func _place_room_fluorescents(center: Vector3, rd: RoomDef) -> void:
	var lc := rd.light_color
	if lc == null:
		return
	var y := layout.theme.wall_height - CEILING_CLEARANCE
	_create_ceiling_light(center + Vector3(0, y, 0), lc)

func _place_corridor_fluorescents(center: Vector3, cd: CorridorDef) -> void:
	var lc := cd.light_color
	if lc == null or cd.light_interval <= 0.0:
		return
	var y := layout.theme.wall_height - CEILING_CLEARANCE
	var hl := cd.length * 0.5
	var along_z := cd.axis == CorridorDef.Axis.Z

	var v := -hl + cd.light_interval * 0.5
	while v < hl:
		var pos: Vector3
		if along_z:
			pos = Vector3(center.x, y, center.z + v)
		else:
			pos = Vector3(center.x + v, y, center.z)
		_create_ceiling_light(pos, lc)
		v += cd.light_interval

# ── Rooms ─────────────────────────────────────────────────────────────────

func _build_room(piece: LevelPiece) -> void:
	var rd := piece.room
	var center := piece.position
	var hx := rd.size.x * 0.5
	var hz := rd.size.y * 0.5
	var t := layout.theme
	var thick := t.wall_thickness

	# Single procedural wall mesh for the entire room.
	var mesh_inst := _build_room_mesh(center, rd)
	add_child(mesh_inst)
	mesh_inst.add_to_group(&"structures")

	# Collision shapes and interactive objects per wall.
	var walls: Array[Dictionary] = [
		{"side": RoomDef.Wall.NORTH, "pos": center + Vector3(0, 0, -hz), "span": rd.size.x + thick, "sx": 1.0, "sz": 0.0},
		{"side": RoomDef.Wall.SOUTH, "pos": center + Vector3(0, 0, hz), "span": rd.size.x + thick, "sx": 1.0, "sz": 0.0},
		{"side": RoomDef.Wall.EAST, "pos": center + Vector3(hx, 0, 0), "span": rd.size.y + thick, "sx": 0.0, "sz": 1.0},
		{"side": RoomDef.Wall.WEST, "pos": center + Vector3(-hx, 0, 0), "span": rd.size.y + thick, "sx": 0.0, "sz": 1.0},
	]

	for w: Dictionary in walls:
		var side: RoomDef.Wall = w["side"]
		var wpos: Vector3 = w["pos"]
		var span: float = w["span"]
		var sx: float = w["sx"]
		var sz: float = w["sz"]

		var has_opening := side in rd.openings
		if has_opening:
			var gap := rd.opening_width
			var jamb_len := (span - gap) * 0.5
			if jamb_len > 0.0:
				var offset := (gap + jamb_len) * 0.5
				var wall_sx := jamb_len * sx + thick * sz
				var wall_sz := jamb_len * sz + thick * sx
				var dir := Vector3(sx, 0, sz)
				_create_wall_body(wpos + dir * offset, wall_sx, wall_sz)
				_create_wall_body(wpos - dir * offset, wall_sx, wall_sz)

			if side in rd.door_openings:
				var door := DOOR_SCENE.instantiate() as Node3D
				door.transform.origin = wpos
				if side == RoomDef.Wall.NORTH or side == RoomDef.Wall.SOUTH:
					door.rotation_degrees.y = 90.0
				var perp := rd.size.x - thick if (side == RoomDef.Wall.NORTH or side == RoomDef.Wall.SOUTH) else rd.size.y - thick
				door.scale.z = minf(rd.opening_width, perp) / _DOOR_MESH_WIDTH
				if side in rd.locked_doors and door is PrototypeDoor:
					(door as PrototypeDoor).locked = true
				add_child(door)
				_doors[StringName("%s_%s" % [rd.id, RoomDef.Wall.keys()[side]])] = door
		else:
			var wall_sx := span * sx + thick * sz
			var wall_sz := span * sz + thick * sx
			_create_wall_body(wpos, wall_sx, wall_sz)

	_place_room_fluorescents(center, rd)
	_create_fill_light(center, rd.size.x, rd.size.y)
	_create_fog_volume(center, rd.size.x, rd.size.y)
	_spawn_enemies_in_bounds(piece, center, hx, hz, rd.enemy_count, rd.enemy_scene)

# ── Corridors ─────────────────────────────────────────────────────────────

func _build_corridor(piece: LevelPiece) -> void:
	var cd := piece.corridor
	var center := piece.position
	var t := layout.theme
	var thick := t.wall_thickness
	var hw := cd.width * 0.5
	var hl := cd.length * 0.5

	if cd.axis == CorridorDef.Axis.Z:
		_create_wall(center + Vector3(hw, 0, 0), thick, cd.length + thick - _SEAM)
		_create_wall(center + Vector3(-hw, 0, 0), thick, cd.length + thick - _SEAM)
	else:
		_create_wall(center + Vector3(0, 0, hw), cd.length + thick - _SEAM * 2.0, thick)
		_create_wall(center + Vector3(0, 0, -hw), cd.length + thick - _SEAM * 2.0, thick)

	_place_corridor_fluorescents(center, cd)

	var hx := hw if cd.axis == CorridorDef.Axis.Z else hl
	var hz := hl if cd.axis == CorridorDef.Axis.Z else hw
	var fog_x := cd.width if cd.axis == CorridorDef.Axis.Z else cd.length
	var fog_z := cd.length if cd.axis == CorridorDef.Axis.Z else cd.width
	_create_fill_light(center, fog_x, fog_z)
	_create_fog_volume(center, fog_x, fog_z)
	_spawn_enemies_in_bounds(piece, center, hx, hz, cd.enemy_count, cd.enemy_scene)

# ── Enemies ───────────────────────────────────────────────────────────────

func _spawn_enemies_in_bounds(piece: LevelPiece, center: Vector3, hx: float, hz: float, count: int, scene: PackedScene) -> void:
	if scene == null:
		scene = ENEMY_SCENE_DEFAULT

	if piece.enemy_positions.size() > 0:
		for epos: Vector3 in piece.enemy_positions:
			_spawn_enemy(center + epos, scene)
		return

	var margin := 1.0
	for i in count:
		var ex := center.x + randf_range(-hx + margin, hx - margin)
		var ez := center.z + randf_range(-hz + margin, hz - margin)
		_spawn_enemy(Vector3(ex, 0, ez), scene)

func _spawn_enemy(pos: Vector3, scene: PackedScene) -> void:
	var enemy := EntityPool.acquire(scene)
	add_child(enemy)
	enemy.global_position = pos
	if enemy.has_method(&"reset"):
		enemy.reset()

# ── Fill Lights ───────────────────────────────────────────────────────────

func _create_fill_light(center: Vector3, size_x: float, size_z: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.55, 0.7)
	light.light_energy = 0.15
	light.omni_range = maxf(size_x, size_z) * 0.6
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	light.transform.origin = center + Vector3(0, 2.0, 0)
	add_child(light)

# ── Fog Volumes ───────────────────────────────────────────────────────────

func _create_fog_volume(_center: Vector3, _size_x: float, _size_z: float) -> void:
	# Volumetric fog is disabled at the environment level; skip FogVolume nodes.
	pass

# ── Door Access ───────────────────────────────────────────────────────────

func get_door(room_id: StringName, wall: RoomDef.Wall) -> Node:
	var key := StringName("%s_%s" % [room_id, RoomDef.Wall.keys()[wall]])
	return _doors.get(key)
