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

# Default mixed-pack composition — delegates to EnemyClassTable autoload
# which owns the explicit file list (same pattern as MonsterAffixTable).
# To narrow what spawns in a specific zone, set RoomDef.enemy_classes.
static func _get_default_class_pool() -> Array[EnemyClass]:
	return EnemyClassTable.get_all()

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

# Per-piece cap on heal-support enemies. Two healers with overlapping
# radii loop-heal each other (and the rest of the pack) faster than a
# focused player can burn anyone down — the room becomes unkillable.
# One healer per room reads as "kill the medic first" priority pick;
# more reads as a softlock.
const MAX_HEALERS_PER_PIECE := 1

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


static func spawn_in_bounds(ctx: LevelBuildContext, piece: LevelPiece, center: Vector3, hx: float, hz: float, count: int, scene: PackedScene, level_range: Vector2i = Vector2i.ZERO, class_pool: Array[EnemyClass] = [], pack_chance_override: float = -1.0) -> void:
	# MP clients receive enemies via EnemiesContainer's MultiplayerSpawner —
	# spawning locally would create duplicates.
	if NetState.is_in_lobby() and NetState.is_client():
		return
	if scene == null:
		scene = ENEMY_SCENE_DEFAULT

	# Per-piece spawn limits, threaded through every _pick_class call below.
	# Dictionary so the counter mutates by reference across the static call
	# chain (plain int would copy at every hop).
	var limits := {"healers_remaining": MAX_HEALERS_PER_PIECE}

	if piece.enemy_positions.size() > 0:
		# Hand-placed enemy positions skip the area-density bump — those
		# coordinates are authored for specific events (encounters, ambush
		# triggers) and adding random extras would muddle the intent.
		for epos: Vector3 in piece.enemy_positions:
			_spawn_with_pack_chance(ctx, center + epos, hx, hz, scene, _roll_level(level_range), center, class_pool, limits, pack_chance_override)
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
		var pack_size := _spawn_with_pack_chance(ctx, Vector3(ex, 0, ez), hx, hz, scene, _roll_level(level_range), center, class_pool, limits, pack_chance_override)
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
static func _spawn_with_pack_chance(ctx: LevelBuildContext, pos: Vector3, hx: float, hz: float, scene: PackedScene, level_override: int, room_center: Vector3 = Vector3.ZERO, class_pool: Array[EnemyClass] = [], limits: Dictionary = {}, pack_chance_override: float = -1.0) -> int:
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
	var effective_pack_chance := pack_chance_override if pack_chance_override >= 0.0 else PACK_CHANCE
	if randf() >= effective_pack_chance:
		_spawn(ctx, pos, scene, level_override, [], null, _pick_class(class_pool, limits))
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
		_spawn(ctx, pos, scene, level_override, [], null, _pick_class(class_pool, limits))
		return 1
	var companion_total := randi_range(PACK_MIN_COMPANIONS, PACK_MAX_COMPANIONS)
	_spawn(ctx, pos, scene, level_override, affixes, null, _pick_class(class_pool, limits))
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
		_spawn(ctx, cpos, scene, level_override, affixes, null, _pick_class(class_pool, limits))
	return companion_total


# Pick one class from the pool. Caller can pass a per-room override; an
# empty override falls back to the global default pool so every spawn
# benefits from mixed-class composition without needing every RoomDef
# to opt in. Returns null only when both pools are empty (in which case
# the caller leaves the scene's baked-in class alone).
##
## `limits.healers_remaining` (when present) caps how many heal-support
## enemies the caller will accept from this pool. When the cap is hit,
## healer rolls re-pick from the non-healer subset; the counter ticks
## down each time a healer is actually emitted.
static func _pick_class(pool: Array[EnemyClass], limits: Dictionary = {}) -> EnemyClass:
	var effective := pool if not pool.is_empty() else _get_default_class_pool()
	if effective.is_empty():
		return null
	var pick: EnemyClass = effective[randi_range(0, effective.size() - 1)]
	if pick != null and pick.support_role == EnemyClass.SupportRole.HEAL and limits.has("healers_remaining"):
		if int(limits["healers_remaining"]) <= 0:
			# Cap hit — re-roll from the non-healer subset of the pool.
			# If the pool is exclusively healers we leave the pick alone
			# (no fallback class available); the cap silently breaks
			# rather than spawning nothing.
			var non_healers: Array[EnemyClass] = []
			for c: EnemyClass in effective:
				if c != null and c.support_role != EnemyClass.SupportRole.HEAL:
					non_healers.append(c)
			if not non_healers.is_empty():
				pick = non_healers[randi_range(0, non_healers.size() - 1)]
		else:
			limits["healers_remaining"] = int(limits["healers_remaining"]) - 1
	return pick


static func _spawn(ctx: LevelBuildContext, pos: Vector3, scene: PackedScene, level_override: int = 0, affixes: Array[MonsterAffix] = [], named: NamedMonster = null, class_override: EnemyClass = null) -> void:
	var enemy := EntityPool.acquire(scene)
	if enemy == null:
		return
	ctx.enemies.add_child(enemy)
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
	# Assign special skills AFTER reset() — reset clears _special_skills.
	# Named monsters use their authored skill list; everyone else rolls
	# from the class's skill pool based on level and rarity.
	if "_special_skills" in enemy:
		if named != null and not named.special_skills.is_empty():
			enemy._special_skills = named.special_skills.duplicate()
		else:
			var ec: EnemyClass = enemy.enemy_class if "enemy_class" in enemy else null
			if ec != null and not ec.skill_pool.is_empty():
				var lv: int = enemy.level if "level" in enemy else 1
				var is_pack := not affixes.is_empty()
				var count_sk := _roll_skill_count(lv, is_pack, enemy.is_boss if "is_boss" in enemy else false)
				enemy._special_skills = _pick_skills(ec.skill_pool, count_sk, lv)


# Roll how many special skills an enemy gets based on level and spawn type.
# Higher levels and pack-rares get more specials; bosses always get 2-3.
static func _roll_skill_count(level: int, is_pack: bool, is_boss: bool) -> int:
	if is_boss:
		return randi_range(2, 3)
	# Level 1 enemies get no specials; L2+ roll 0-1.
	var base: int = 0 if level <= 1 else randi_range(0, 1)
	if is_pack:
		base += 1
	return base


# Pick `count` distinct skills from a pool, weighted and filtered by min_level.
static func _pick_skills(pool: Array[EnemySkill], count: int, level: int) -> Array[EnemySkill]:
	if count <= 0 or pool.is_empty():
		return []
	# Filter to eligible skills, build weighted candidates.
	var eligible: Array[EnemySkill] = []
	var weights: Array[int] = []
	var total_weight := 0
	for skill in pool:
		if skill == null:
			continue
		if level < skill.min_level:
			continue
		eligible.append(skill)
		weights.append(skill.weight)
		total_weight += skill.weight
	if eligible.is_empty():
		return []
	var picked: Array[EnemySkill] = []
	for _i in mini(count, eligible.size()):
		if total_weight <= 0:
			break
		var roll := randi() % total_weight
		var cum := 0
		for j in eligible.size():
			cum += weights[j]
			if roll < cum:
				picked.append(eligible[j])
				total_weight -= weights[j]
				eligible.remove_at(j)
				weights.remove_at(j)
				break
	# Sort by priority so _pick_skill iterates in the right order.
	picked.sort_custom(func(a: EnemySkill, b: EnemySkill) -> bool: return a.priority < b.priority)
	return picked
