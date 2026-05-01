extends Node

## Hides enemies, pickups, and interactibles from rendering when the player has
## no line of sight to them. Each physics frame, raycasts player → target at
## chest height against the World physics layer (walls). When the ray hits a
## wall, the target's `visible` is set to false; otherwise true.
##
## For interactibles that are themselves StaticBody3D on the World layer (doors,
## loot crates, exits), the target's own RID is excluded from the raycast so
## the door/crate isn't its own occluder.
##
## Performance:
## - Distance gate: targets past MAX_DIST_SQ are forced invisible without a raycast.
## - Cell cache: static interactibles only re-raycast when the player crosses a
##   cell boundary; otherwise the cached visibility persists.
## - Stagger: dynamic targets (enemies, pickups) split across STAGGER_GROUPS
##   physics frames so each frame raycasts roughly half the population.

const WORLD_LAYER_MASK := 1  # physics layer 1 ("World") — walls + floors
const RAY_HEIGHT := 1.0      # chest-height sample so the ray clears floor/ceiling colliders
const PICKUP_RAY_HEIGHT := 0.5  # pickups settle low; sample closer to ground
# Squared distance beyond which targets are forced invisible without a raycast.
# The fixed isometric camera frustum tops out around 30m on the diagonal — past
# 40m a target is offscreen anyway, so skip the physics query at horde density.
const MAX_DIST_SQ := 40.0 * 40.0
# 4m cells — large enough that the player crosses a boundary infrequently
# (every few seconds at walking speed) but small enough that the visibility
# state stays accurate as they move.
const CELL_SIZE := 4.0
const _INV_CELL_SIZE := 1.0 / CELL_SIZE
# Sentinel cell forces a full re-test on first physics frame.
const _UNSET_CELL := Vector2i(2147483647, 2147483647)
# Spread dynamic raycasts across this many physics frames. At 2, half the
# population is tested each tick — visibility lag is at most one physics step
# (~16ms), invisible to the eye.
const STAGGER_GROUPS := 2

var _query := PhysicsRayQueryParameters3D.new()
var _visible_to_player: Dictionary = {}
var _last_player_cell: Vector2i = _UNSET_CELL
var _stagger_frame: int = 0

func _ready() -> void:
	_query.collision_mask = WORLD_LAYER_MASK
	_query.collide_with_areas = false
	_query.collide_with_bodies = true

func _physics_process(_delta: float) -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var player := players[0] as Node3D
	if player == null:
		return
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return
	# Both ray endpoints anchor to player Y, keeping each ray horizontal so it
	# can't graze ceilings/floors when targets settle at different heights
	# (e.g. crouch tunnels, pickups on the ground vs. enemies at chest height).
	var player_pos := player.global_position
	var from := player_pos + Vector3(0, RAY_HEIGHT, 0)
	var pickup_from := player_pos + Vector3(0, PICKUP_RAY_HEIGHT, 0)
	var player_cell := Vector2i(
		int(floor(player_pos.x * _INV_CELL_SIZE)),
		int(floor(player_pos.z * _INV_CELL_SIZE)),
	)
	var cell_changed := player_cell != _last_player_cell
	_last_player_cell = player_cell

	var stagger := _stagger_frame
	_stagger_frame = (_stagger_frame + 1) % STAGGER_GROUPS

	# Enemies — dynamic; stagger across STAGGER_GROUPS frames.
	# Newly seen enemies (no cache entry) are tested immediately so they don't
	# pop in for up to a frame after spawning.
	var index := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Node3D
		if enemy == null:
			continue
		var first_seen := not _visible_to_player.has(enemy)
		if first_seen or (index + stagger) % STAGGER_GROUPS == 0:
			var enemy_los: bool
			if enemy.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
				enemy_los = false
			else:
				_query.exclude = []
				_query.from = from
				_query.to = Vector3(enemy.global_position.x, from.y, enemy.global_position.z)
				enemy_los = space.intersect_ray(_query).is_empty()
			_apply_visibility(enemy, enemy_los)
		index += 1
	# Pickups — dynamic during pop, static once settled. Same staggered pass.
	index = 0
	for p in get_tree().get_nodes_in_group(&"pickups"):
		var pickup := p as Node3D
		if pickup == null:
			continue
		var first_seen := not _visible_to_player.has(pickup)
		if first_seen or (index + stagger) % STAGGER_GROUPS == 0:
			var pickup_los: bool
			if pickup.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
				pickup_los = false
			else:
				_query.exclude = []
				_query.from = pickup_from
				_query.to = Vector3(pickup.global_position.x, pickup_from.y, pickup.global_position.z)
				pickup_los = space.intersect_ray(_query).is_empty()
			_apply_visibility(pickup, pickup_los)
		index += 1
	# Interactibles — static (doors, switches, crates). Re-raycast only when the
	# player crosses a cell boundary, since neither side is moving otherwise.
	for i in get_tree().get_nodes_in_group(&"interactables"):
		var body := i as CollisionObject3D
		if body == null:
			continue
		# UVRevealable owns the visible flag for items in the "uv_hidden" group;
		# don't fight it.
		if body.is_in_group(&"uv_hidden"):
			continue
		var first_seen := not _visible_to_player.has(body)
		if not (cell_changed or first_seen):
			continue
		var body_los: bool
		if body.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
			body_los = false
		else:
			_query.exclude = [body.get_rid()]
			_query.from = from
			_query.to = Vector3(body.global_position.x, from.y, body.global_position.z)
			body_los = space.intersect_ray(_query).is_empty()
		_apply_visibility(body, body_los)

## Toggles both rendering and pickability. Hidden Area3D / StaticBody3D children
## still receive mouse picks unless input_ray_pickable is also disabled — at the
## fixed angled camera, the camera ray can clear walls and reach a hidden target
## on the other side, so visibility alone isn't enough to gate clicks.
func _apply_visibility(node: Node3D, los: bool) -> void:
	node.visible = los
	if node is CollisionObject3D:
		(node as CollisionObject3D).input_ray_pickable = los
	for child in node.get_children():
		if child is CollisionObject3D:
			(child as CollisionObject3D).input_ray_pickable = los
	_visible_to_player[node] = los

## True if `node` had line of sight to the player as of the most recent physics
## tick. Returns false for nodes that haven't been tested yet — callers should
## treat "unknown" as occluded, which is the safe default for AI gates.
func has_los_to_player(node: Node) -> bool:
	return _visible_to_player.get(node, false)
