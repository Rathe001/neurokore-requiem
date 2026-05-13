extends RefCounted
class_name ClutterBuilder
## Scatters destructible and indestructible props inside rooms. Follows the
## DecalBuilder pattern: static methods, deterministic RNG seeded by room id,
## wall margin, opening avoidance. All geometry is built from primitive meshes.

# ── Destructible prop pool ─────────────────────────────────────────────────
# Each entry defines a prop type. "weight" controls how often it's picked
# relative to other entries. All destructibles are StaticBody3D on the
# ENEMY collision layer so player attacks hit them.

const DESTRUCTIBLE_POOL: Array[Dictionary] = [
	{ "name": "Barrel",   "mesh": "cylinder", "radius": 0.4, "height": 0.9,
	  "hp": 10, "loot": true,  "credits": true,  "credit_min": 1, "credit_max": 3,
	  "color": Color(0.55, 0.35, 0.15), "weight": 3 },
	{ "name": "Crate",    "mesh": "box", "size": Vector3(0.7, 0.7, 0.7),
	  "hp": 15, "loot": true,  "credits": true,  "credit_min": 1, "credit_max": 4,
	  "color": Color(0.50, 0.40, 0.20), "weight": 3 },
	{ "name": "Monitor",  "mesh": "box", "size": Vector3(0.5, 0.4, 0.1),
	  "hp": 5,  "loot": false, "credits": false, "credit_min": 0, "credit_max": 0,
	  "color": Color(0.20, 0.20, 0.25), "weight": 2, "y_offset": 0.5 },
	{ "name": "Chair",    "mesh": "box", "size": Vector3(0.4, 0.5, 0.4),
	  "hp": 5,  "loot": false, "credits": false, "credit_min": 0, "credit_max": 0,
	  "color": Color(0.30, 0.30, 0.30), "weight": 2 },
	{ "name": "Terminal",  "mesh": "box", "size": Vector3(0.4, 0.6, 0.3),
	  "hp": 8,  "loot": false, "credits": true,  "credit_min": 1, "credit_max": 2,
	  "color": Color(0.15, 0.22, 0.15), "weight": 1 },
]

# ── Indestructible prop pool ──────────────────────────────────────────────

const INDESTRUCTIBLE_POOL: Array[Dictionary] = [
	{ "name": "Barrier",    "mesh": "box", "size": Vector3(1.2, 0.6, 0.5),
	  "blocking": true,  "color": Color(0.40, 0.40, 0.40), "weight": 2 },
	{ "name": "ServerRack", "mesh": "box", "size": Vector3(0.6, 1.8, 0.5),
	  "blocking": true,  "color": Color(0.15, 0.15, 0.22), "weight": 2 },
	{ "name": "HeavyPipe",  "mesh": "cylinder", "radius": 0.2, "height": 2.0,
	  "blocking": true,  "color": Color(0.35, 0.30, 0.25), "weight": 1,
	  "horizontal": true },
	{ "name": "FloorGrate", "mesh": "plane", "size": Vector2(1.0, 1.0),
	  "blocking": false, "color": Color(0.25, 0.25, 0.25), "weight": 2 },
]

const MARGIN := 1.5           ## min distance from wall edge
const OPENING_CLEARANCE := 1.0 ## extra clearance around openings
const MIN_SPACING := 1.0      ## min distance between placed props
const EMISSION_ENERGY := 0.3  ## subtle cyberpunk glow


static func scatter_clutter(ctx: LevelBuildContext, center: Vector3, hx: float, hz: float, rd: RoomDef) -> void:
	if rd.clutter_density <= 0:
		return

	var seed_hash := _hash_id(rd.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash if seed_hash != 0 else 1

	var placed: Array[Vector3] = []

	# Destructibles: density * 2 attempts.
	var dest_count := rd.clutter_density * 2
	var dest_weights := _build_weights(DESTRUCTIBLE_POOL)
	for _i in dest_count:
		var pos := _pick_position(rng, center, hx, hz, rd, placed)
		if pos == Vector3.INF:
			continue
		var def := _weighted_pick(DESTRUCTIBLE_POOL, dest_weights, rng)
		_create_destructible(ctx, pos, def)
		placed.append(pos)

	# Indestructibles: density * 1 attempts.
	var indest_count := rd.clutter_density
	var indest_weights := _build_weights(INDESTRUCTIBLE_POOL)
	for _i in indest_count:
		var pos := _pick_position(rng, center, hx, hz, rd, placed)
		if pos == Vector3.INF:
			continue
		var def := _weighted_pick(INDESTRUCTIBLE_POOL, indest_weights, rng)
		_create_indestructible(ctx, pos, def)
		placed.append(pos)


# ── Prop creation ─────────────────────────────────────────────────────────

static func _create_destructible(ctx: LevelBuildContext, pos: Vector3, def: Dictionary) -> void:
	var body := DestructibleProp.new()
	body.name = StringName("Prop_%s" % def["name"])
	body.max_health = int(def["hp"])
	body.drops_loot = bool(def["loot"])
	body.drops_credits = bool(def["credits"])
	body.credit_range = Vector2i(int(def["credit_min"]), int(def["credit_max"]))
	body.prop_color = def["color"] as Color
	body.input_ray_pickable = false

	var y_offset: float = def.get("y_offset", 0.0)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = &"Mesh"
	mesh_inst.mesh = _make_mesh(def)
	mesh_inst.material_override = _make_material(def)
	var mesh_height := _get_height(def)
	mesh_inst.position = Vector3(0, mesh_height * 0.5 + y_offset, 0)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = _make_shape(def)
	col.position = Vector3(0, mesh_height * 0.5 + y_offset, 0)
	body.add_child(col)

	body.position = pos
	ctx.root.add_child(body)


static func _create_indestructible(ctx: LevelBuildContext, pos: Vector3, def: Dictionary) -> void:
	var blocking: bool = def.get("blocking", true)
	var horizontal: bool = def.get("horizontal", false)

	if not blocking:
		# Non-blocking: bare mesh, no physics.
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = StringName("Decor_%s" % def["name"])
		mesh_inst.mesh = _make_mesh(def)
		mesh_inst.material_override = _make_material(def)
		mesh_inst.position = pos + Vector3(0, 0.005, 0)  # tiny lift off floor
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ctx.root.add_child(mesh_inst)
		mesh_inst.add_to_group(&"structures")
		return

	# Blocking: StaticBody3D on PILLAR layer (128).
	var body := StaticBody3D.new()
	body.name = StringName("Prop_%s" % def["name"])
	body.collision_layer = 128  # PILLAR — blocks movement and bullets
	body.collision_mask = 0
	body.input_ray_pickable = false

	var mesh_height := _get_height(def)
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = &"Mesh"
	mesh_inst.mesh = _make_mesh(def)
	mesh_inst.material_override = _make_material(def)
	mesh_inst.position = Vector3(0, mesh_height * 0.5, 0)
	if horizontal:
		mesh_inst.rotation_degrees.z = 90.0
		mesh_inst.position = Vector3(0, mesh_height * 0.5, 0)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = _make_shape(def)
	col.position = mesh_inst.position
	if horizontal:
		col.rotation_degrees.z = 90.0
	body.add_child(col)

	body.position = pos
	ctx.root.add_child(body)
	body.add_to_group(&"structures")


# ── Mesh / shape / material factories ─────────────────────────────────────

static func _make_mesh(def: Dictionary) -> Mesh:
	var kind: String = def["mesh"]
	if kind == "cylinder":
		var m := CylinderMesh.new()
		m.top_radius = float(def["radius"])
		m.bottom_radius = float(def["radius"])
		m.height = float(def["height"])
		return m
	elif kind == "plane":
		var m := PlaneMesh.new()
		m.size = def["size"] as Vector2
		return m
	else:  # box
		var m := BoxMesh.new()
		m.size = def["size"] as Vector3
		return m


static func _make_shape(def: Dictionary) -> Shape3D:
	var kind: String = def["mesh"]
	if kind == "cylinder":
		var s := CylinderShape3D.new()
		s.radius = float(def["radius"])
		s.height = float(def["height"])
		return s
	elif kind == "plane":
		# Planes are non-blocking visual only — shouldn't have shapes.
		var s := BoxShape3D.new()
		s.size = Vector3(1.0, 0.01, 1.0)
		return s
	else:  # box
		var s := BoxShape3D.new()
		s.size = def["size"] as Vector3
		return s


static func _make_material(def: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var c: Color = def["color"]
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = EMISSION_ENERGY
	mat.roughness = 0.85
	return mat


static func _get_height(def: Dictionary) -> float:
	var kind: String = def["mesh"]
	if kind == "cylinder":
		return float(def["height"])
	elif kind == "plane":
		return 0.01
	else:  # box
		return (def["size"] as Vector3).y


# ── Placement helpers ─────────────────────────────────────────────────────

static func _pick_position(rng: RandomNumberGenerator, center: Vector3, hx: float, hz: float, rd: RoomDef, placed: Array[Vector3]) -> Vector3:
	# Up to 10 attempts to find a non-conflicting spot.
	for _attempt in 10:
		var px := center.x + rng.randf_range(-hx + MARGIN, hx - MARGIN)
		var pz := center.z + rng.randf_range(-hz + MARGIN, hz - MARGIN)
		var pos := Vector3(px, 0, pz)
		if _is_near_opening(pos, center, hx, hz, rd):
			continue
		if _too_close_to_placed(pos, placed):
			continue
		return pos
	return Vector3.INF  # give up


static func _is_near_opening(pos: Vector3, center: Vector3, hx: float, hz: float, rd: RoomDef) -> bool:
	var half_gap := rd.opening_width * 0.5 + OPENING_CLEARANCE
	for wall: RoomDef.Wall in rd.openings:
		match wall:
			RoomDef.Wall.NORTH:
				if absf(pos.z - (center.z - hz)) < MARGIN + 0.5 and absf(pos.x - center.x) < half_gap:
					return true
			RoomDef.Wall.SOUTH:
				if absf(pos.z - (center.z + hz)) < MARGIN + 0.5 and absf(pos.x - center.x) < half_gap:
					return true
			RoomDef.Wall.EAST:
				if absf(pos.x - (center.x + hx)) < MARGIN + 0.5 and absf(pos.z - center.z) < half_gap:
					return true
			RoomDef.Wall.WEST:
				if absf(pos.x - (center.x - hx)) < MARGIN + 0.5 and absf(pos.z - center.z) < half_gap:
					return true
	return false


static func _too_close_to_placed(pos: Vector3, placed: Array[Vector3]) -> bool:
	for p: Vector3 in placed:
		if pos.distance_to(p) < MIN_SPACING:
			return true
	return false


static func _hash_id(id: StringName) -> int:
	var h := 0
	for c in String(id):
		h = (h * 31 + c.unicode_at(0)) & 0x7FFFFFFF
	return h


static func _build_weights(pool: Array[Dictionary]) -> Array[int]:
	var weights: Array[int] = []
	for def: Dictionary in pool:
		weights.append(int(def["weight"]))
	return weights


static func _weighted_pick(pool: Array[Dictionary], weights: Array[int], rng: RandomNumberGenerator) -> Dictionary:
	var total := 0
	for w: int in weights:
		total += w
	if total <= 0:
		return pool[0]
	var roll := rng.randi() % total
	var cum := 0
	for i in pool.size():
		cum += weights[i]
		if roll < cum:
			return pool[i]
	return pool[pool.size() - 1]
