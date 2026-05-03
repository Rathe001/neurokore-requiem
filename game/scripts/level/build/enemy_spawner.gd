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


static func spawn_in_bounds(ctx: LevelBuildContext, piece: LevelPiece, center: Vector3, hx: float, hz: float, count: int, scene: PackedScene, level_range: Vector2i = Vector2i.ZERO) -> void:
	if scene == null:
		scene = ENEMY_SCENE_DEFAULT

	if piece.enemy_positions.size() > 0:
		for epos: Vector3 in piece.enemy_positions:
			_spawn_with_pack_chance(ctx, center + epos, hx, hz, scene, _roll_level(level_range), center)
		return

	var margin := 1.0
	var spawned := 0
	while spawned < count:
		var ex := center.x + randf_range(-hx + margin, hx - margin)
		var ez := center.z + randf_range(-hz + margin, hz - margin)
		var pack_size := _spawn_with_pack_chance(ctx, Vector3(ex, 0, ez), hx, hz, scene, _roll_level(level_range), center)
		spawned += pack_size


static func _roll_level(level_range: Vector2i) -> int:
	if level_range.x <= 0 or level_range.y <= 0:
		return 0
	return randi_range(level_range.x, level_range.y)


# Returns the number of enemies actually spawned (1 for solo, N for a pack).
# Caller uses this to decrement the piece's enemy budget so a packed spawn
# doesn't also count as one slot.
static func _spawn_with_pack_chance(ctx: LevelBuildContext, pos: Vector3, hx: float, hz: float, scene: PackedScene, level_override: int, room_center: Vector3 = Vector3.ZERO) -> int:
	if randf() >= PACK_CHANCE:
		_spawn(ctx, pos, scene, level_override, [])
		return 1
	# Pack — roll affix list and companion count, spawn leader + companions
	# all sharing the same affixes.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var lvl := level_override if level_override > 0 else 1
	var affix_count := randi_range(PACK_MIN_AFFIXES, PACK_MAX_AFFIXES)
	var affixes := MonsterAffixTable.roll_affixes(affix_count, lvl, rng)
	if affixes.is_empty():
		# Affix table couldn't satisfy the request — fall back to a solo
		# spawn so the slot isn't wasted.
		_spawn(ctx, pos, scene, level_override, [])
		return 1
	var companion_total := randi_range(PACK_MIN_COMPANIONS, PACK_MAX_COMPANIONS)
	_spawn(ctx, pos, scene, level_override, affixes)
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
		_spawn(ctx, cpos, scene, level_override, affixes)
	return companion_total


static func _spawn(ctx: LevelBuildContext, pos: Vector3, scene: PackedScene, level_override: int = 0, affixes: Array[MonsterAffix] = []) -> void:
	var enemy := EntityPool.acquire(scene)
	ctx.root.add_child(enemy)
	enemy.global_position = pos
	if level_override > 0 and "level" in enemy:
		enemy.level = level_override
	# Set affixes BEFORE reset() so _apply_level_stats sees them when it
	# multiplies the rolled HP / damage. An empty list is the explicit
	# "no modifiers — non-pack solo spawn" signal that wipes the prior
	# pool occupant's affix list.
	if "affixes" in enemy:
		enemy.affixes = affixes
	if enemy.has_method(&"reset"):
		enemy.reset()
