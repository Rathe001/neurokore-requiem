extends RefCounted
class_name EnemySpawner
## Per-piece enemy placement. If a LevelPiece carries explicit enemy_positions
## (relative to the piece centre), spawn at exactly those points; otherwise
## drop `count` enemies at random positions inside the piece bounds.
##
## level_range rolls a level for each spawned enemy. Used by:
##   - initial spawn for procgen pieces (BranchingGenerator sets per-piece
##     bands by depth — chain index, branch base level, boss arena top-out)
##   - respawn (LevelBuilder.respawn_enemies) to scale around the player's
##     current power band so the demo stays challenging as the player levels.
## (0,0) means "use scene defaults" — what hand-authored pieces want.
##
## Pack rolls: each spawn point has PACK_CHANCE to become a rare-pack lead.
## When it does, a small group spawns sharing the same MonsterAffix list
## (Diablo-2 pattern — companions inherit leader modifiers). The pack
## counts against the piece's enemy count budget so a packed room isn't
## also a fully-stocked room on top of that.

const ENEMY_SCENE_DEFAULT: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")

# Default mixed-pack composition used when a room/corridor doesn't
# specify its own enemy_classes pool. Loaded lazily on first use so a
# missing .tres at startup doesn't crash the autoload chain. Order
# doesn't matter — each spawn samples uniformly. To narrow what spawns
# in a specific zone, set RoomDef.enemy_classes (overrides this list).
const _DEFAULT_CLASS_PATHS: Array[String] = [
	"res://resources/enemies/classes/basic_melee.tres",
	"res://resources/enemies/classes/basic_ranged.tres",
	"res://resources/enemies/classes/melee_healer.tres",
	"res://resources/enemies/classes/ranged_buffer.tres",
]
static var _default_class_pool: Array[EnemyClass] = []
static var _default_pool_loaded: bool = false


static func _get_default_class_pool() -> Array[EnemyClass]:
	if _default_pool_loaded:
		return _default_class_pool
	_default_pool_loaded = true
	for path in _DEFAULT_CLASS_PATHS:
		if not ResourceLoader.exists(path):
			push_warning("[EnemySpawner] missing default class .tres: %s" % path)
			continue
		var c := load(path) as EnemyClass
		if c != null:
			_default_class_pool.append(c)
	return _default_class_pool

# Pack tuning. PACK_CHANCE is per spawn point — at 6%, an 8-enemy room hits
# at least one pack ~40% of the time (1 - 0.94^8). PACK_*_AFFIXES bounds
# the modifier count on the leader (companions inherit the same set).
# PACK_*_COMPANIONS includes the leader → 2 means leader + 1 companion.
const PACK_CHANCE := 0.06
const PACK_MIN_AFFIXES := 1
const PACK_MAX_AFFIXES := 2
const PACK_MIN_COMPANIONS := 2
const PACK_MAX_COMPANIONS := 4
const PACK_COMPANION_RADIUS := 2.5

# Auto-density target — 1 enemy per N square metres of room floor. The
# spawner bumps a room's effective enemy_count to at least this when the
# room is big enough, so larger rooms feel populated without having to
# hand-tune the count per piece. Existing hand-authored counts win when
# they're already higher (the explicit author always trumps the auto
# minimum). enemy_count = 0 stays at 0 — that's the opt-out for safe
# rooms (start, vendors, puzzle-only).
#
# 48 was tuned in playtest as the "feels populated, not packed" sweet
# spot — at 24 the open arena (768 sqm = 32 enemies) read as a bullet
# hell instead of a fight. Pack rolls layer additional enemies on top
# of this baseline.
const DEFAULT_AREA_PER_ENEMY := 48.0

# Named-monster tuning. Per spawn point — preempts the pack roll, so a hit
# spawns ONE solo named encounter (no companions). At 0.5%, a 200-enemy
# session sees ~1 named on average; high enough to feel like a discovery
# without being routine.
const NAMED_CHANCE := 0.005


static func spawn_in_bounds(ctx: LevelBuildContext, piece: LevelPiece, center: Vector3, hx: float, hz: float, count: int, scene: PackedScene, level_range: Vector2i = Vector2i.ZERO, class_pool: Array[EnemyClass] = []) -> void:
	if scene == null:
		scene = ENEMY_SCENE_DEFAULT

	if piece.enemy_positions.size() > 0:
		# Hand-placed enemy positions skip the area-density bump — those
		# coordinates are authored for specific events (encounters, ambush
		# triggers) and adding random extras would muddle the intent.
		for epos: Vector3 in piece.enemy_positions:
			_spawn_with_pack_chance(ctx, center + epos, hx, hz, scene, _roll_level(level_range), center, class_pool)
		return

	# Auto-density: any room that opted in with a positive enemy_count
	# gets bumped to at least the area-target, so larger rooms feel
	# proportionally populated without per-room hand-tuning. count=0
	# preserves the explicit "this is a safe room" opt-out.
	if count > 0:
		var area := (hx * 2.0) * (hz * 2.0)
		var density_target := int(ceil(area / DEFAULT_AREA_PER_ENEMY))
		count = maxi(count, density_target)

	var margin := 1.0
	var spawned := 0
	while spawned < count:
		var ex := center.x + randf_range(-hx + margin, hx - margin)
		var ez := center.z + randf_range(-hz + margin, hz - margin)
		var pack_size := _spawn_with_pack_chance(ctx, Vector3(ex, 0, ez), hx, hz, scene, _roll_level(level_range), center, class_pool)
		spawned += pack_size


static func _roll_level(level_range: Vector2i) -> int:
	if level_range.x <= 0 or level_range.y <= 0:
		return 0
	return randi_range(level_range.x, level_range.y)


# Returns the number of enemies actually spawned (1 for solo / named,
# N for a pack). Caller uses this to decrement the piece's enemy budget
# so a packed spawn doesn't also count as one slot. `class_pool` is the
# room's mixed-pack composition — when non-empty, every spawned enemy
# (solo or pack member) draws an EnemyClass from it independently, so
# a pack reads as melee + ranged + support instead of N copies of the
# leader's class.
static func _spawn_with_pack_chance(ctx: LevelBuildContext, pos: Vector3, hx: float, hz: float, scene: PackedScene, level_override: int, room_center: Vector3 = Vector3.ZERO, class_pool: Array[EnemyClass] = []) -> int:
	# Hoisted so both the named-monster branch and the pack branch share
	# one definition — declaring `var lvl` in each arm fires the
	# "declared below in the parent block" GDScript warning.
	var lvl := level_override if level_override > 0 else 1
	# Named-monster roll runs first and preempts everything else. Failure
	# falls through to the pack roll. Named monsters carry their own
	# enemy_class (NamedMonster.enemy_class), so they bypass class_pool.
	if randf() < NAMED_CHANCE:
		var named_rng := RandomNumberGenerator.new()
		named_rng.randomize()
		var named := NamedMonsterTable.roll_random(lvl, named_rng)
		if named != null:
			_spawn(ctx, pos, scene, level_override, [], named, null)
			return 1
		# Named pool empty for this level — fall through to the regular
		# pack/solo path so we don't waste the slot.
	if randf() >= PACK_CHANCE:
		_spawn(ctx, pos, scene, level_override, [], null, _pick_class(class_pool))
		return 1
	# Pack — roll affix list and companion count, spawn leader + companions
	# all sharing the same affixes. Each member picks its OWN class from
	# the pool, so a pack of 4 might be 1 melee leader + 1 ranged + 2
	# healers; affix list is uniform across the pack regardless.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var affix_count := randi_range(PACK_MIN_AFFIXES, PACK_MAX_AFFIXES)
	var affixes := MonsterAffixTable.roll_affixes(affix_count, lvl, rng)
	if affixes.is_empty():
		# Affix table couldn't satisfy the request — fall back to a solo
		# spawn so the slot isn't wasted.
		_spawn(ctx, pos, scene, level_override, [], null, _pick_class(class_pool))
		return 1
	var companion_total := randi_range(PACK_MIN_COMPANIONS, PACK_MAX_COMPANIONS)
	_spawn(ctx, pos, scene, level_override, affixes, null, _pick_class(class_pool))
	# Spread companions on a ring around the leader; clamp to the piece
	# bounds when we know them so a pack near a wall doesn't punch members
	# into geometry.
	var companion_count := companion_total - 1
	for i in companion_count:
		var angle := (TAU / float(companion_count)) * float(i) + rng.randf_range(-0.3, 0.3)
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * PACK_COMPANION_RADIUS
		var cpos := pos + offset
		if hx > 0.0 and hz > 0.0:
			cpos.x = clampf(cpos.x, room_center.x - hx + 0.6, room_center.x + hx - 0.6)
			cpos.z = clampf(cpos.z, room_center.z - hz + 0.6, room_center.z + hz - 0.6)
		_spawn(ctx, cpos, scene, level_override, affixes, null, _pick_class(class_pool))
	return companion_total


# Pick one class from the pool. Caller can pass a per-room override; an
# empty override falls back to the global default pool so every spawn
# benefits from mixed-class composition without needing every RoomDef
# to opt in. Returns null only when both pools are empty (in which case
# the caller leaves the scene's baked-in class alone).
static func _pick_class(pool: Array[EnemyClass]) -> EnemyClass:
	var effective := pool if not pool.is_empty() else _get_default_class_pool()
	if effective.is_empty():
		return null
	return effective[randi_range(0, effective.size() - 1)]


static func _spawn(ctx: LevelBuildContext, pos: Vector3, scene: PackedScene, level_override: int = 0, affixes: Array[MonsterAffix] = [], named: NamedMonster = null, class_override: EnemyClass = null) -> void:
	var enemy := EntityPool.acquire(scene)
	ctx.root.add_child(enemy)
	enemy.global_position = pos
	if level_override > 0 and "level" in enemy:
		enemy.level = level_override
	# Set affixes + named + class_override BEFORE reset() so
	# _apply_level_stats sees them when it multiplies the rolled HP /
	# damage and applies identity. All fields are explicitly set on
	# every spawn (named=null + affixes=[] for vanilla) so a pool-
	# recycled body never inherits the previous occupant's modifiers.
	# class_override is intentionally only applied when non-null —
	# named monsters set their own class via NamedMonster.enemy_class
	# inside _apply_level_stats, and pool-default classes (the ones
	# baked onto the scene template) are left in place when no pool
	# is configured for the room.
	if "affixes" in enemy:
		enemy.affixes = affixes
	if "named_monster" in enemy:
		enemy.named_monster = named
	if class_override != null and "enemy_class" in enemy:
		enemy.enemy_class = class_override
	if enemy.has_method(&"reset"):
		enemy.reset()
