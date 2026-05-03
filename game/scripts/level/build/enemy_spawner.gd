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

const ENEMY_SCENE_DEFAULT: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")


static func spawn_in_bounds(ctx: LevelBuildContext, piece: LevelPiece, center: Vector3, hx: float, hz: float, count: int, scene: PackedScene, level_range: Vector2i = Vector2i.ZERO) -> void:
	if scene == null:
		scene = ENEMY_SCENE_DEFAULT

	if piece.enemy_positions.size() > 0:
		for epos: Vector3 in piece.enemy_positions:
			_spawn(ctx, center + epos, scene, _roll_level(level_range))
		return

	var margin := 1.0
	for i in count:
		var ex := center.x + randf_range(-hx + margin, hx - margin)
		var ez := center.z + randf_range(-hz + margin, hz - margin)
		_spawn(ctx, Vector3(ex, 0, ez), scene, _roll_level(level_range))


static func _roll_level(level_range: Vector2i) -> int:
	if level_range.x <= 0 or level_range.y <= 0:
		return 0
	return randi_range(level_range.x, level_range.y)


static func _spawn(ctx: LevelBuildContext, pos: Vector3, scene: PackedScene, level_override: int = 0) -> void:
	var enemy := EntityPool.acquire(scene)
	ctx.root.add_child(enemy)
	enemy.global_position = pos
	if level_override > 0 and "level" in enemy:
		enemy.level = level_override
	if enemy.has_method(&"reset"):
		enemy.reset()
