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
	  "color": Color(0.55, 0.35, 0.15), "weight": 3, "cover": true,
	  "texture": &"barrel" },
	{ "name": "Crate",    "mesh": "box", "size": Vector3(0.7, 0.7, 0.7),
	  "hp": 15, "loot": true,  "credits": true,  "credit_min": 1, "credit_max": 4,
	  "color": Color(0.50, 0.40, 0.20), "weight": 3, "cover": true,
	  "texture": &"crate" },
	{ "name": "Monitor",  "mesh": "box", "size": Vector3(0.5, 0.4, 0.1),
	  "hp": 5,  "loot": false, "credits": false, "credit_min": 0, "credit_max": 0,
	  "color": Color(0.20, 0.20, 0.25), "weight": 2, "y_offset": 0.5, "cover": true,
	  "texture": &"screen" },
	{ "name": "Chair",    "mesh": "box", "size": Vector3(0.4, 0.4, 0.4),
	  "hp": 5,  "loot": false, "credits": false, "credit_min": 0, "credit_max": 0,
	  "color": Color(0.30, 0.30, 0.30), "weight": 2, "cover": false,
	  "texture": &"metal" },
	{ "name": "Terminal",  "mesh": "box", "size": Vector3(0.4, 0.6, 0.3),
	  "hp": 8,  "loot": false, "credits": true,  "credit_min": 1, "credit_max": 2,
	  "color": Color(0.15, 0.22, 0.15), "weight": 1, "cover": true,
	  "texture": &"screen" },
]

# ── Indestructible prop pool ──────────────────────────────────────────────

const INDESTRUCTIBLE_POOL: Array[Dictionary] = [
	{ "name": "Barrier",    "mesh": "box", "size": Vector3(1.2, 0.6, 0.5),
	  "blocking": true,  "color": Color(0.40, 0.40, 0.40), "weight": 2,
	  "texture": &"hazard" },
	{ "name": "ServerRack", "mesh": "box", "size": Vector3(0.6, 1.8, 0.5),
	  "blocking": true,  "color": Color(0.15, 0.15, 0.22), "weight": 2,
	  "texture": &"server" },
	{ "name": "HeavyPipe",  "mesh": "cylinder", "radius": 0.2, "height": 2.0,
	  "blocking": false,  "color": Color(0.35, 0.30, 0.25), "weight": 1,
	  "horizontal": true, "texture": &"metal" },
	{ "name": "FloorGrate", "mesh": "plane", "size": Vector2(1.0, 1.0),
	  "blocking": false, "color": Color(0.25, 0.25, 0.25), "weight": 2,
	  "texture": &"grate" },
]

const MARGIN := 1.5           ## min distance from wall edge
const OPENING_CLEARANCE := 1.0 ## extra clearance around openings
const MIN_SPACING := 1.0      ## min distance between placed props
const EMISSION_ENERGY := 0.3  ## subtle cyberpunk glow
## Destructible collision height. Player projectiles spawn at chest level
## (~1.0m, see PlayerCombat._spawn_projectile) and travel horizontally; a
## 0.4–0.9m visual prop never intersects them with mesh-sized collision, so
## "I aim at the barrel and the bullet flies right over" was the dominant
## complaint. Extending collision upward gives the prop an invisible
## bullet-catch column while the visual mesh stays short. Side effect:
## cover props now block enemy fire at standing height as well as crouch —
## intentional given the same shape sits on the PILLAR layer.
const DESTRUCTIBLE_COLLISION_HEIGHT := 1.6


static func scatter_clutter(ctx: LevelBuildContext, center: Vector3, hx: float, hz: float, rd: RoomDef, room_id: StringName = &"") -> void:
	if rd.clutter_density <= 0:
		return

	# Per-instance room_id gives each room unique clutter even when they
	# share the same RoomDef template. Falls back to rd.id for legacy callers.
	var id_for_seed: StringName = room_id if room_id != &"" else rd.id
	var seed_hash := _hash_id(id_for_seed)
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
	# Cover props sit on ENEMY + PILLAR — blocks enemy projectiles and LoS
	# rays when the player crouches behind them. Non-cover props (chairs) are
	# ENEMY-only and short enough for StepUp to clear. DestructibleProp._ready
	# derives collision_layer / collision_mask from provides_cover, so we only
	# set the flag here — writing the layers again would just shadow the
	# (identical) _ready computation and invite drift.
	body.provides_cover = def.get("cover", false)

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
	col.shape = _make_destructible_shape(def)
	# Anchor the bullet-catch column at the ground so it intercepts both
	# horizontal player fire at 1.0m and downward enemy fire from 1.4m.
	col.position = Vector3(0, DESTRUCTIBLE_COLLISION_HEIGHT * 0.5, 0)
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
		mesh_inst.add_to_group(&"clutter")
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
	if horizontal:
		# Horizontal cylinders lie on the ground — center at radius height,
		# not half the cylinder length. Otherwise a 2m-long pipe sits at
		# y=1.0 and blocks LoS rays at chest height.
		var radius: float = def.get("radius", 0.2)
		mesh_inst.rotation_degrees.z = 90.0
		mesh_inst.position = Vector3(0, radius, 0)
	else:
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
	body.add_to_group(&"clutter")


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


# Same footprint as _make_shape, but with the vertical extent stretched to
# DESTRUCTIBLE_COLLISION_HEIGHT so the prop is bullet-catchable at standing
# fire height. Used only for destructibles — indestructibles keep their
# mesh-sized shape via _make_shape (their height varies by design, e.g.
# server racks are already 1.8m).
static func _make_destructible_shape(def: Dictionary) -> Shape3D:
	var kind: String = def["mesh"]
	if kind == "cylinder":
		var s := CylinderShape3D.new()
		s.radius = float(def["radius"])
		s.height = DESTRUCTIBLE_COLLISION_HEIGHT
		return s
	else:  # box — covers everything not cylinder; no plane destructibles exist
		var s := BoxShape3D.new()
		var orig: Vector3 = def["size"] as Vector3
		s.size = Vector3(orig.x, DESTRUCTIBLE_COLLISION_HEIGHT, orig.z)
		return s


static func _make_material(def: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var c: Color = def["color"]
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = EMISSION_ENERGY
	mat.roughness = 0.85
	var tex_id: StringName = def.get("texture", &"")
	if tex_id != &"":
		var tex := _get_texture(tex_id)
		if tex != null:
			mat.albedo_texture = tex
			mat.uv1_scale = Vector3(1, 1, 1)
			# Screens get stronger emission from the texture itself.
			if tex_id == &"screen":
				mat.emission_energy_multiplier = 1.5
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


# ── Procedural textures ──────────────────────────────────────────────────
# Small textures generated once and cached. Each gives a prop type visual
# detail (rivets, grating, scan lines, etc.) without external image files.
# Textures multiply with albedo_color so they darken/lighten the base hue.

const TEX_SIZE := 64
static var _texture_cache: Dictionary = {}


static func _get_texture(id: StringName) -> ImageTexture:
	if _texture_cache.has(id):
		return _texture_cache[id]
	var img: Image = null
	match id:
		&"barrel":  img = _gen_barrel_tex()
		&"crate":   img = _gen_crate_tex()
		&"screen":  img = _gen_screen_tex()
		&"metal":   img = _gen_metal_tex()
		&"hazard":  img = _gen_hazard_tex()
		&"server":  img = _gen_server_tex()
		&"grate":   img = _gen_grate_tex()
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[id] = tex
	return tex


# Barrel: horizontal bands with rivet dots.
static func _gen_barrel_tex() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := 0.85
			# Horizontal bands every 8px — darkened grooves.
			if y % 16 < 2:
				v = 0.55
			# Rivet dots at band intersections.
			if y % 16 < 2 and x % 12 < 3:
				v = 1.0
			# Subtle vertical grain.
			if x % 4 == 0:
				v *= 0.95
			img.set_pixel(x, y, Color(v, v, v))
	return img


# Crate: plank grid lines with corner brackets.
static func _gen_crate_tex() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := 0.82
			# Plank seams: vertical and horizontal dividers.
			if x % 32 < 2 or y % 32 < 2:
				v = 0.50
			# Corner reinforcement brackets (L-shapes in each corner quadrant).
			var cx: int = x if x < 32 else TEX_SIZE - 1 - x
			var cy: int = y if y < 32 else TEX_SIZE - 1 - y
			if (cx < 6 and cy < 2) or (cx < 2 and cy < 6):
				v = 1.0
			# Wood grain noise (simple striping).
			if (x + y * 3) % 7 == 0:
				v *= 0.92
			img.set_pixel(x, y, Color(v, v, v))
	return img


# Screen: horizontal scan lines with a bright center glow.
static func _gen_screen_tex() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var half := TEX_SIZE * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			# Distance from center for vignette.
			var dx: float = (float(x) - half) / half
			var dy: float = (float(y) - half) / half
			var d: float = sqrt(dx * dx + dy * dy)
			var vignette: float = clampf(1.0 - d * 0.4, 0.5, 1.0)
			# Scan lines — alternating bright/dim rows.
			var scan: float = 0.9 if y % 4 < 2 else 1.1
			# Combine: bright center, dimmer edges, scan line modulation.
			var v: float = clampf(vignette * scan, 0.0, 1.3)
			# Slight green/cyan tint for CRT feel (via separate channels).
			img.set_pixel(x, y, Color(v * 0.8, v, v * 0.9))
	return img


# Metal: brushed steel with scratches.
static func _gen_metal_tex() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := 0.78
			# Horizontal brushing.
			if (x * 7 + y) % 11 < 2:
				v = 0.68
			# Occasional bright scratch.
			if (x * 13 + y * 7) % 67 == 0:
				v = 1.0
			# Subtle grid.
			if x % 32 < 1 or y % 32 < 1:
				v *= 0.80
			img.set_pixel(x, y, Color(v, v, v))
	return img


# Hazard: diagonal warning stripes (yellow-on-dark).
static func _gen_hazard_tex() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var stripe: int = (x + y) % 16
			if stripe < 8:
				# Yellow-ish stripe (multiplied with gray albedo → muted amber).
				img.set_pixel(x, y, Color(1.2, 1.1, 0.5))
			else:
				img.set_pixel(x, y, Color(0.45, 0.45, 0.45))
	return img


# Server rack: vertical LED columns with blinking dots.
static func _gen_server_tex() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var v := 0.6
			# Vertical dividers (rack unit seams).
			if y % 16 < 1:
				v = 0.35
			# LED indicator dots — bright green/cyan spots.
			if x % 8 == 3 and y % 8 == 4:
				img.set_pixel(x, y, Color(0.4, 1.4, 0.8))
				continue
			# Ventilation slots.
			if x % 4 < 2 and y % 16 > 12:
				v = 0.45
			img.set_pixel(x, y, Color(v, v, v * 1.1))
	return img


# Floor grate: grid of holes (dark squares in a lighter frame).
static func _gen_grate_tex() -> Image:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var gx: int = x % 8
			var gy: int = y % 8
			# Hole: inner 5×5 of each 8×8 cell is dark.
			if gx >= 1 and gx <= 5 and gy >= 1 and gy <= 5:
				img.set_pixel(x, y, Color(0.25, 0.25, 0.25))
			else:
				# Frame bars — lighter metal.
				img.set_pixel(x, y, Color(0.95, 0.95, 0.90))
	return img
