extends RefCounted
class_name FloorDecalBuilder
## Scatters flat, collision-free litter (papers, debris, medical waste) across
## room floors. Follows the DecalBuilder / ClutterBuilder pattern: static
## methods, deterministic RNG seeded by room id, wall margin, opening
## avoidance.
##
## Runtime shape: per-room placement accumulates Transform3Ds into
## ctx.floor_decal_visuals keyed by FloorDecalDef. After the whole level is
## built, commit_floor_decals() collapses each def into ONE
## MultiMeshInstance3D of flat quads — one draw call per decal texture for
## the entire level, zero collision, zero per-frame cost.
##
## See docs/floor-decal-scatter-spec.md for the full rationale.

# Explicit pool list. NEVER enumerate res:// with DirAccess — it returns
# nothing in exported Godot 4 builds (project_resource_loader_gotcha, bit us
# 4 times). Add a path here when a new FloorDecalDef .tres is authored.
const POOL_PATHS: Array[String] = [
	# Small per-tile scatter — most common, weight 1-3
	"res://resources/decals/floor/paper_scatter.tres",
	"res://resources/decals/floor/debris_scatter.tres",
	"res://resources/decals/floor/medwaste_scatter.tres",
	# Multi-tile variants. Paper stays a loose scatter (just covering
	# more area) so it reads as a wider abandoned mess, not a pile.
	# Debris uses a denser pile silhouette by intent. Medwaste large
	# is a wide-area discarded spread (different art from the pile).
	# All weight 1 so small versions still dominate; bigger min_spacing
	# keeps multi-tile placements distinct from each other.
	"res://resources/decals/floor/paper_scatter_large.tres",
	"res://resources/decals/floor/debris_pile_large.tres",
	"res://resources/decals/floor/medwaste_scatter_large.tres",
	# Special-flavor decals — landed 2026-06-09. Lower weights so they
	# stay flavor accents rather than dominating the floor. Stencils
	# clamp aspect_jitter low + reduce yaw range so they read as
	# painted signage rather than scattered litter.
	"res://resources/decals/floor/scorch_marks.tres",
	"res://resources/decals/floor/oil_stain_dry.tres",
	"res://resources/decals/floor/dried_blood_old.tres",
	"res://resources/decals/floor/broken_glass.tres",
	"res://resources/decals/floor/floor_warning_radiation.tres",
	"res://resources/decals/floor/floor_warning_slippery.tres",
	"res://resources/decals/floor/floor_warning_biohazard.tres",
]

# Tiny lift off the floor. Above the puddle layer (0.005), below the
# LiquidLayer floor mesh (0.015) so blood pools render on top of litter.
# Decal materials use ALPHA_SCISSOR (opaque pass, writes depth), so the
# blend-mode liquid at higher Y depth-tests correctly over them — no
# render_priority hack needed.
const FLOOR_DECAL_Y: float = 0.006
# Per-instance Y jitter ceiling so two overlapping decals don't share an
# exact plane and z-fight. Sub-mm — reads as flat.
const Y_EPSILON: float = 0.004
const MARGIN: float = 0.6            # litter can sit closer to walls than props
const OPENING_CLEARANCE: float = 0.8
# Placement attempts per density unit. Higher than ClutterBuilder's ×2 — litter
# is meant to read dense and overlaps freely.
const ATTEMPTS_PER_DENSITY: int = 6

# Lazily-loaded pool of FloorDecalDefs (resolved once, reused every room).
static var _pool: Array[FloorDecalDef] = []
static var _pool_loaded: bool = false
# Per-def StandardMaterial3D cache (built once, reused at commit).
static var _material_cache: Dictionary = {}
# Per-id procedural placeholder texture cache (for defs with no art yet).
static var _placeholder_cache: Dictionary = {}


static func scatter_decals(ctx: LevelBuildContext, center: Vector3, hx: float, hz: float, rd: RoomDef, room_id: StringName = &"") -> void:
	if rd.decal_density <= 0:
		return
	var pool := _load_pool()
	if pool.is_empty():
		return

	# Per-instance room_id keeps each room's litter stable across re-entry
	# and distinct between rooms that share a RoomDef template.
	var id_for_seed: StringName = room_id if room_id != &"" else rd.id
	var seed_hash := _hash_id(id_for_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash if seed_hash != 0 else 1

	var placed: Array[Vector3] = []
	var weights := _build_weights(pool)
	var attempts := rd.decal_density * ATTEMPTS_PER_DENSITY
	for i in attempts:
		var def := _weighted_pick(pool, weights, rng)
		var pos := _pick_position(rng, center, hx, hz, rd, placed, def.min_spacing, def.size_range.y)
		if pos == Vector3.INF:
			continue
		placed.append(pos)
		_queue_decal(ctx, def, pos, i, rng)


# ── Placement ──────────────────────────────────────────────────────────────

static func _pick_position(rng: RandomNumberGenerator, center: Vector3, hx: float, hz: float, rd: RoomDef, placed: Array[Vector3], min_spacing: float, max_decal_size: float = 0.0) -> Vector3:
	# Size-aware margin: small scatter (≤MARGIN diameter) uses the
	# default MARGIN; multi-tile piles get an extra half-size buffer so
	# their edge can't slide past the wall. Without this a 6m pile
	# centered 0.6m from a wall would clip ~2.4m through the wall.
	var size_buffer: float = maxf(0.0, max_decal_size * 0.5 - MARGIN)
	var effective_margin: float = MARGIN + size_buffer
	# If the room is too small to fit the buffered area, this decal
	# can't go here — fall through to INF and the caller skips it.
	if hx <= effective_margin or hz <= effective_margin:
		return Vector3.INF
	for _attempt in 8:
		var px := center.x + rng.randf_range(-hx + effective_margin, hx - effective_margin)
		var pz := center.z + rng.randf_range(-hz + effective_margin, hz - effective_margin)
		var pos := Vector3(px, 0, pz)
		if _is_near_opening(pos, center, hx, hz, rd):
			continue
		if _too_close(pos, placed, min_spacing):
			continue
		return pos
	return Vector3.INF


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


static func _too_close(pos: Vector3, placed: Array[Vector3], min_spacing: float) -> bool:
	for p: Vector3 in placed:
		if pos.distance_to(p) < min_spacing:
			return true
	return false


# Build a flat-quad transform (position + Y rotation + non-uniform scale) and
# append it to the per-def accumulator on the build context.
static func _queue_decal(ctx: LevelBuildContext, def: FloorDecalDef, pos: Vector3, index: int, rng: RandomNumberGenerator) -> void:
	var base_size := rng.randf_range(def.size_range.x, def.size_range.y)
	var jitter := def.aspect_jitter
	var size_x := base_size * (1.0 + rng.randf_range(-jitter, jitter))
	var size_z := base_size * (1.0 + rng.randf_range(-jitter, jitter))
	var yaw := rng.randf_range(-def.random_yaw_range, def.random_yaw_range)
	# Stagger Y by a sub-mm amount per placement so overlapping decals don't
	# z-fight. index-derived so it's deterministic with the seed.
	var y := FLOOR_DECAL_Y + float(index % 7) / 7.0 * Y_EPSILON
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(size_x, 1.0, size_z))
	var xform := Transform3D(basis, Vector3(pos.x, y, pos.z))

	if not ctx.floor_decal_visuals.has(def):
		ctx.floor_decal_visuals[def] = [] as Array[Transform3D]
	(ctx.floor_decal_visuals[def] as Array[Transform3D]).append(xform)


# ── Commit ───────────────────────────────────────────────────────────────

# Collapse every accumulated def into one MultiMeshInstance3D. Called once
# from LevelBuilder alongside WallBuilder.commit_batched_mmi.
static func commit_floor_decals(ctx: LevelBuildContext) -> void:
	var unit_mesh := _get_unit_plane(ctx)
	for def in ctx.floor_decal_visuals.keys():
		var xforms: Array = ctx.floor_decal_visuals[def]
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = unit_mesh
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = StringName("FloorDecals_%s" % String((def as FloorDecalDef).id))
		mmi.multimesh = mm
		mmi.material_override = _get_material(def as FloorDecalDef)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		ctx.root.add_child(mmi)
		# &"structures" ONLY — never &"clutter". This is one level-wide MMI per
		# texture sitting at the origin; the LoS culler's clutter loop room-gates
		# by node.global_position, which for an origin-anchored whole-level batch
		# resolves to the wrong room and fades the whole thing to invisible.
		# (Corridor-wall MMIs are &"structures"-only for the same reason.) Litter
		# is 3 draw calls total, so always-drawn is the right trade anyway.
		mmi.add_to_group(&"structures")
	ctx.floor_decal_visuals.clear()


# Shared 1×1 PlaneMesh (XZ plane, +Y normal) — cached on the context like
# WallBuilder's batched_unit_mesh. Per-instance scale handles real size.
static func _get_unit_plane(ctx: LevelBuildContext) -> PlaneMesh:
	if ctx.floor_decal_unit_mesh == null:
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE
		pm.orientation = PlaneMesh.FACE_Y
		ctx.floor_decal_unit_mesh = pm
	return ctx.floor_decal_unit_mesh


static func _get_material(def: FloorDecalDef) -> StandardMaterial3D:
	if _material_cache.has(def):
		return _material_cache[def]
	var mat := StandardMaterial3D.new()
	var tex: Texture2D = def.albedo_texture if def.albedo_texture != null else _placeholder_texture(def.id)
	mat.albedo_texture = tex
	# ALPHA_SCISSOR renders in the opaque pass (writes depth) → overlapping
	# decals sort via the depth buffer and the blend-mode blood layer at a
	# higher Y draws over them correctly. Hard edge is fine for litter.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL  # stay lit
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_BACK  # camera always above; one-sided up
	if def.normal_texture != null:
		mat.normal_enabled = true
		mat.normal_texture = def.normal_texture
	_material_cache[def] = mat
	return mat


# ── Pool loading ───────────────────────────────────────────────────────────

static func _load_pool() -> Array[FloorDecalDef]:
	if _pool_loaded:
		return _pool
	_pool_loaded = true
	for path in POOL_PATHS:
		# ResourceLoader.exists guards against missing files; explicit list
		# (not DirAccess) keeps it working in exported builds.
		if not ResourceLoader.exists(path):
			push_warning("[FloorDecalBuilder] Missing decal def: %s" % path)
			continue
		var def := load(path) as FloorDecalDef
		if def != null:
			_pool.append(def)
	return _pool


static func _build_weights(pool: Array[FloorDecalDef]) -> Array[int]:
	var weights: Array[int] = []
	for def in pool:
		weights.append(maxi(def.weight, 1))
	return weights


static func _weighted_pick(pool: Array[FloorDecalDef], weights: Array[int], rng: RandomNumberGenerator) -> FloorDecalDef:
	var total := 0
	for w in weights:
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


static func _hash_id(id: StringName) -> int:
	var h := 0
	for c in String(id):
		h = (h * 31 + c.unicode_at(0)) & 0x7FFFFFFF
	return h


# ── Procedural placeholders ────────────────────────────────────────────────
# Distinct-per-id alpha-cutout textures so the scatter reads correctly in
# engine before real art lands. Each draws several small shapes on a
# transparent background; the alpha is what the ALPHA_SCISSOR material keys on.

const PLACEHOLDER_PX: int = 256

static func _placeholder_texture(id: StringName) -> ImageTexture:
	if _placeholder_cache.has(id):
		return _placeholder_cache[id]
	var img: Image
	match id:
		&"paper_scatter":   img = _gen_paper_placeholder()
		&"debris_scatter":  img = _gen_debris_placeholder()
		&"medwaste_scatter": img = _gen_medwaste_placeholder()
		_:                  img = _gen_generic_placeholder()
	var tex := ImageTexture.create_from_image(img)
	_placeholder_cache[id] = tex
	return tex


static func _blank_image() -> Image:
	var img := Image.create(PLACEHOLDER_PX, PLACEHOLDER_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # fully transparent
	return img


# Scattered cream rectangles = sheets of paper.
static func _gen_paper_placeholder() -> Image:
	var img := _blank_image()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1001
	for _i in 9:
		var w := rng.randi_range(40, 78)
		var h := rng.randi_range(50, 90)
		var ox := rng.randi_range(0, PLACEHOLDER_PX - w)
		var oy := rng.randi_range(0, PLACEHOLDER_PX - h)
		var shade := rng.randf_range(0.78, 0.95)
		var col := Color(shade, shade, shade * 0.95, 1.0)
		for y in range(oy, oy + h):
			for x in range(ox, ox + w):
				# a few darker "text" lines across each sheet
				var c := col
				if (y - oy) % 9 < 1 and (x - ox) > 5 and (x - ox) < w - 5:
					c = Color(0.35, 0.35, 0.35, 1.0)
				img.set_pixel(x, y, c)
	return img


# Scattered grey angular shards = glass/rubble debris.
static func _gen_debris_placeholder() -> Image:
	var img := _blank_image()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2002
	for _i in 26:
		var cx := rng.randi_range(10, PLACEHOLDER_PX - 10)
		var cy := rng.randi_range(10, PLACEHOLDER_PX - 10)
		var r := rng.randi_range(4, 14)
		var shade := rng.randf_range(0.30, 0.62)
		var col := Color(shade, shade, shade * 1.05, 1.0)
		# crude filled triangle/diamond
		for y in range(cy - r, cy + r):
			if y < 0 or y >= PLACEHOLDER_PX:
				continue
			var span := r - absi(y - cy)
			for x in range(cx - span, cx + span):
				if x < 0 or x >= PLACEHOLDER_PX:
					continue
				img.set_pixel(x, y, col)
	return img


# Small thin shapes in off-white + red tint = syringes / gauze / gloves.
static func _gen_medwaste_placeholder() -> Image:
	var img := _blank_image()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3003
	for _i in 14:
		var cx := rng.randi_range(8, PLACEHOLDER_PX - 40)
		var cy := rng.randi_range(8, PLACEHOLDER_PX - 12)
		var length := rng.randi_range(18, 46)
		var thick := rng.randi_range(3, 7)
		var reddish := rng.randf() < 0.4
		var col := Color(0.75, 0.30, 0.30, 1.0) if reddish else Color(0.88, 0.90, 0.92, 1.0)
		for y in range(cy, cy + thick):
			if y < 0 or y >= PLACEHOLDER_PX:
				continue
			for x in range(cx, cx + length):
				if x < 0 or x >= PLACEHOLDER_PX:
					continue
				img.set_pixel(x, y, col)
	return img


# Magenta checker = "no art, fix me" generic fallback.
static func _gen_generic_placeholder() -> Image:
	var img := _blank_image()
	for y in PLACEHOLDER_PX:
		for x in PLACEHOLDER_PX:
			if ((x / 32) + (y / 32)) % 2 == 0:
				img.set_pixel(x, y, Color(1.0, 0.0, 1.0, 1.0))
	return img
