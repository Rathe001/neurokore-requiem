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
# Legacy / fallback pool — used when a room doesn't specify a theme,
# also kept as the default for the old random-mix behaviour. Lighter
# than before: dropped the multi-tile pile variants and the flavor
# specials (scorch / oil / dried_blood / glass), since the random mix
# made every floor read as "junk yard". Themed pools below carry the
# specials per-room theme.
const POOL_PATHS: Array[String] = [
	"res://resources/decals/floor/paper_scatter.tres",
	"res://resources/decals/floor/debris_scatter.tres",
]

# Named themed pools keyed by RoomDef.decal_pool. A room sets
# decal_pool = &"medical" and gets a curated set; &"" or &"general"
# falls back to POOL_PATHS; &"none" explicitly disables decals even
# if decal_density > 0. All paths still live under
# res://resources/decals/floor/.
const THEMED_POOLS: Dictionary = {
	# Sterile / patrolled facility — no clutter, no signage litter.
	&"none": [] as Array[String],
	# Generic facility floor — light paper + debris scatter only.
	&"general": [
		"res://resources/decals/floor/paper_scatter.tres",
		"res://resources/decals/floor/debris_scatter.tres",
	],
	# Office / records area — paper-heavy with the occasional drift.
	&"office": [
		"res://resources/decals/floor/paper_scatter.tres",
		"res://resources/decals/floor/paper_scatter_large.tres",
	],
	# Medical wing — gauze + vials + ambient dried blood.
	&"medical": [
		"res://resources/decals/floor/medwaste_scatter.tres",
		"res://resources/decals/floor/medwaste_scatter_large.tres",
		"res://resources/decals/floor/dried_blood_old.tres",
		"res://resources/decals/floor/broken_glass.tres",
	],
	# Damaged / fought-in rooms — debris piles, scorch marks, glass,
	# old blood. Reads as "something happened here".
	&"damaged": [
		"res://resources/decals/floor/debris_scatter.tres",
		"res://resources/decals/floor/debris_pile_large.tres",
		"res://resources/decals/floor/scorch_marks.tres",
		"res://resources/decals/floor/broken_glass.tres",
		"res://resources/decals/floor/dried_blood_old.tres",
	],
	# Industrial / machine room — oil stains + debris.
	&"industrial": [
		"res://resources/decals/floor/oil_stain_dry.tres",
		"res://resources/decals/floor/debris_scatter.tres",
		"res://resources/decals/floor/debris_pile_large.tres",
	],
	# Abandoned / disused — paper drift + dust patches + light debris.
	&"abandoned": [
		"res://resources/decals/floor/paper_scatter.tres",
		"res://resources/decals/floor/paper_scatter_large.tres",
		"res://resources/decals/floor/debris_scatter.tres",
	],
}

# Stencil pool — kept separate from the random-scatter pool. Stencils
# are intentional painted signage and need to be placed AT doorways,
# axis-aligned, not scattered like litter. _place_stencils() runs after
# scatter_decals and handles them with door-aware placement + yaw.
const STENCIL_PATHS: Array[String] = [
	"res://resources/decals/floor/floor_warning_radiation.tres",
	"res://resources/decals/floor/floor_warning_slippery.tres",
	"res://resources/decals/floor/floor_warning_biohazard.tres",
]
# How far inside the room (from doorway, measured along inward normal)
# the stencil sits. Far enough that the door frame doesn't crop it,
# close enough that the player sees it on approach.
const STENCIL_STANDOFF_M: float = 2.0
# Per-opening odds of placing a stencil. Below 100% so the marking
# reads as intentional but not blanket-applied to every door.
const STENCIL_PLACE_CHANCE: float = 0.55

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

# Lazily-loaded pools of FloorDecalDefs, keyed by theme name (&"" or
# &"general" for the legacy POOL_PATHS, named keys from THEMED_POOLS
# otherwise). Resolved once per theme, reused every room.
static var _pools_by_theme: Dictionary = {}
# Per-def StandardMaterial3D cache (built once, reused at commit).
static var _material_cache: Dictionary = {}
# Per-id procedural placeholder texture cache (for defs with no art yet).
static var _placeholder_cache: Dictionary = {}


static func scatter_decals(ctx: LevelBuildContext, center: Vector3, hx: float, hz: float, rd: RoomDef, room_id: StringName = &"") -> void:
	# &"none" theme disables decals even when density > 0 — lets the
	# author keep density nonzero on a base RoomDef and override it
	# to clean per-room without resetting both fields.
	if rd.decal_pool == &"none":
		_place_stencils(ctx, center, hx, hz, rd, _stencil_rng(rd, room_id))
		return
	if rd.decal_density <= 0:
		_place_stencils(ctx, center, hx, hz, rd, _stencil_rng(rd, room_id))
		return
	var pool := _load_pool(rd.decal_pool)
	if pool.is_empty():
		_place_stencils(ctx, center, hx, hz, rd, _stencil_rng(rd, room_id))
		return

	var rng := _stencil_rng(rd, room_id)

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
	# Door-aligned painted signage pass — distinct from the random
	# scatter above. Stencils need an explicit position (centred on
	# doorway, set back into the room) and an axis-aligned yaw so the
	# symbol reads correctly on approach; the scatter path can't do
	# either of those without contaminating the litter logic.
	_place_stencils(ctx, center, hx, hz, rd, rng)


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


# Stencil placement — distinct from random litter scatter. Walks the
# room's openings list and drops one painted sign per door (gated by
# STENCIL_PLACE_CHANCE so not every door gets one). Position is set
# back into the room from the doorway by STENCIL_STANDOFF_M; yaw is
# axis-aligned so the symbol reads correctly when approaching from the
# door direction. Pulls from the dedicated STENCIL_PATHS pool so the
# litter weights don't dilute it.
static func _place_stencils(ctx: LevelBuildContext, center: Vector3, hx: float, hz: float, rd: RoomDef, rng: RandomNumberGenerator) -> void:
	if rd.openings.is_empty():
		return
	var stencils: Array[FloorDecalDef] = []
	for path in STENCIL_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var d := load(path) as FloorDecalDef
		if d != null:
			stencils.append(d)
	if stencils.is_empty():
		return
	var stamp_index := 0
	for wall: RoomDef.Wall in rd.openings:
		if rng.randf() > STENCIL_PLACE_CHANCE:
			continue
		var def := stencils[rng.randi() % stencils.size()]
		var pos := Vector3.ZERO
		# Yaw aligns the stencil so its texture's "up" points OUT of the
		# room — i.e. the player walking in from the door sees the symbol
		# right-side up. Yaw is measured CCW around +Y from the texture's
		# default +Z forward.
		var yaw := 0.0
		match wall:
			RoomDef.Wall.NORTH:
				pos = Vector3(center.x, 0.0, center.z - hz + STENCIL_STANDOFF_M)
				yaw = 0.0
			RoomDef.Wall.SOUTH:
				pos = Vector3(center.x, 0.0, center.z + hz - STENCIL_STANDOFF_M)
				yaw = PI
			RoomDef.Wall.EAST:
				pos = Vector3(center.x + hx - STENCIL_STANDOFF_M, 0.0, center.z)
				yaw = -PI * 0.5
			RoomDef.Wall.WEST:
				pos = Vector3(center.x - hx + STENCIL_STANDOFF_M, 0.0, center.z)
				yaw = PI * 0.5
		_queue_decal_at(ctx, def, pos, yaw, stamp_index, rng)
		stamp_index += 1


# Same shape as _queue_decal but accepts an explicit yaw, bypassing
# random_yaw_range. Used by the stencil pass so signage stays
# axis-aligned. aspect_jitter is still honoured because authored
# stencil defs clamp it tight (≤0.05) — keeps painted signs square.
static func _queue_decal_at(ctx: LevelBuildContext, def: FloorDecalDef, pos: Vector3, yaw: float, index: int, rng: RandomNumberGenerator) -> void:
	var base_size := rng.randf_range(def.size_range.x, def.size_range.y)
	var jitter := def.aspect_jitter
	var size_x := base_size * (1.0 + rng.randf_range(-jitter, jitter))
	var size_z := base_size * (1.0 + rng.randf_range(-jitter, jitter))
	var y := FLOOR_DECAL_Y + float(index % 7) / 7.0 * Y_EPSILON
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(size_x, 1.0, size_z))
	var xform := Transform3D(basis, Vector3(pos.x, y, pos.z))
	if not ctx.floor_decal_visuals.has(def):
		ctx.floor_decal_visuals[def] = [] as Array[Transform3D]
	(ctx.floor_decal_visuals[def] as Array[Transform3D]).append(xform)


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
	# Tone the decal albedo down ~60% so paper/debris/glass don't outshine
	# the floor under the level's low ambient. StandardMaterial3D's
	# default ambient term reads brighter than the floor procedural
	# shader's, which made cream-white textures pop as if self-illuminated.
	# Without this, real-paper-coloured decals (highly reflective in real
	# life) look unshaded against the dim floor.
	mat.albedo_color = Color(0.6, 0.6, 0.6, 1.0)
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_BACK  # camera always above; one-sided up
	if def.normal_texture != null:
		mat.normal_enabled = true
		mat.normal_texture = def.normal_texture
	_material_cache[def] = mat
	return mat


# ── Pool loading ───────────────────────────────────────────────────────────

static func _load_pool(theme: StringName = &"") -> Array[FloorDecalDef]:
	# &"none" is an explicit disable — returns empty even if THEMED_POOLS
	# happened to define it (which it does, to make the disable explicit
	# at the data layer too). scatter_decals short-circuits on empty.
	if _pools_by_theme.has(theme):
		return _pools_by_theme[theme]
	var paths: Array[String]
	if theme == &"" or theme == &"general":
		paths = POOL_PATHS
	elif THEMED_POOLS.has(theme):
		paths = THEMED_POOLS[theme]
	else:
		push_warning("[FloorDecalBuilder] Unknown decal_pool theme: %s — falling back to general" % theme)
		paths = POOL_PATHS
	var pool: Array[FloorDecalDef] = []
	for path in paths:
		# ResourceLoader.exists guards against missing files; explicit list
		# (not DirAccess) keeps it working in exported builds.
		if not ResourceLoader.exists(path):
			push_warning("[FloorDecalBuilder] Missing decal def: %s" % path)
			continue
		var def := load(path) as FloorDecalDef
		if def != null:
			pool.append(def)
	_pools_by_theme[theme] = pool
	return pool


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


# Per-instance RNG seeded by room id (or the runtime piece id when set,
# so two pieces sharing a RoomDef template still get distinct layouts).
# Shared by the litter scatter pass and the stencil pass so both stay
# deterministic with the level seed.
static func _stencil_rng(rd: RoomDef, room_id: StringName) -> RandomNumberGenerator:
	var id_for_seed: StringName = room_id if room_id != &"" else rd.id
	var seed_hash := _hash_id(id_for_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash if seed_hash != 0 else 1
	return rng


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
