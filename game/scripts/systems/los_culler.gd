extends Node

## Hides enemies, pickups, corpses, and interactibles from rendering when the
## player has no line of sight to them. Each physics frame, raycasts player →
## target at chest height against the World physics layer (walls). The LoS
## decision sets a target state in `_target_los`; rendering visibility fades
## smoothly between opaque and transparent over ~0.13s in `_process` so things
## don't pop in/out as the player moves through doorways.
##
## For interactibles that are themselves StaticBody3D on the World layer (doors,
## loot crates, exits), the target's own RID is excluded from the raycast so
## the body isn't its own occluder.
##
## Performance:
## - Distance gate: targets past MAX_DIST_SQ are forced invisible without a raycast.
## - Cell cache: static interactibles & corpses only re-raycast when the player
##   crosses a cell boundary; otherwise the cached target persists.
## - Stagger: dynamic targets (enemies, pickups) split across STAGGER_GROUPS
##   physics frames so each frame raycasts roughly half the population.
## - Fade lerp runs every render frame, raycasts run on the physics tick.

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
# population is tested each tick — visibility lag is at most one physics step.
const STAGGER_GROUPS := 2
# Higher rate = snappier fade. ~12 gives a ~0.08s time constant, short enough
# to feel responsive when running through a doorway, long enough to mask the
# binary LoS flip and the staggered raycast cadence.
const FADE_RATE := 12.0
# Once transparency exceeds this, switch visible=false to stop rendering. We
# leave a tiny margin below 1.0 because lerp asymptotes — without the margin
# we'd render imperceptibly transparent geometry forever.
const HIDE_THRESHOLD := 0.98

var _query := PhysicsRayQueryParameters3D.new()
# node -> bool: target LoS (written by physics, read by process)
var _target_los: Dictionary = {}
# node -> float: current transparency [0=opaque, 1=invisible], lerped each frame
var _transparency: Dictionary = {}
# node -> Array[GeometryInstance3D]: cached descendants we apply transparency to.
# Cached because walking the hierarchy every frame for every tracked node would
# add up at horde density; entity meshes are static after spawn.
var _geom_cache: Dictionary = {}
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
	# Newly seen enemies (no cache entry) are tested immediately so their target
	# state is correct from frame 0.
	var index := 0
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var enemy := e as Node3D
		if enemy == null:
			continue
		var first_seen := not _target_los.has(enemy)
		if first_seen or (index + stagger) % STAGGER_GROUPS == 0:
			var enemy_los: bool
			if enemy.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
				enemy_los = false
			else:
				_query.exclude = []
				_query.from = from
				_query.to = Vector3(enemy.global_position.x, from.y, enemy.global_position.z)
				enemy_los = space.intersect_ray(_query).is_empty()
			_set_target(enemy, enemy_los)
		index += 1
	# Pickups are intentionally NOT LoS-culled — loot should always be visible
	# so players can see what's in a level even before clearing it. We still
	# track them in _target_los so the visibility fade in _process picks up
	# any newly-spawned pickup as visible.
	for p in get_tree().get_nodes_in_group(&"pickups"):
		var pickup := p as Node3D
		if pickup == null:
			continue
		_set_target(pickup, true)
	# Corpses — static after the death-hold transition. Same low-ray sample as
	# pickups (corpses lie on the floor) and same cell-cached cadence as the
	# other static targets — re-raycast only when the player crosses a cell.
	for c in get_tree().get_nodes_in_group(&"corpses"):
		var corpse := c as Node3D
		if corpse == null:
			continue
		var corpse_first := not _target_los.has(corpse)
		if not (cell_changed or corpse_first):
			continue
		var corpse_los: bool
		if corpse.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
			corpse_los = false
		else:
			_query.exclude = []
			_query.from = pickup_from
			_query.to = Vector3(corpse.global_position.x, pickup_from.y, corpse.global_position.z)
			corpse_los = space.intersect_ray(_query).is_empty()
		_set_target(corpse, corpse_los)
	# Static glows — emissive meshes that aren't proper Light3Ds (pit ooze, etc).
	# ProximityLighting only dims OmniLight3D/SpotLight3D, so emissive surfaces
	# stay bright through walls without this. Same low-ray + cell-cache cadence
	# as corpses since they're tied to floor-level features.
	for s in get_tree().get_nodes_in_group(&"static_glows"):
		var glow := s as Node3D
		if glow == null:
			continue
		var glow_first := not _target_los.has(glow)
		if not (cell_changed or glow_first):
			continue
		var glow_los: bool
		if glow.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
			glow_los = false
		else:
			_query.exclude = []
			_query.from = pickup_from
			_query.to = Vector3(glow.global_position.x, pickup_from.y, glow.global_position.z)
			glow_los = space.intersect_ray(_query).is_empty()
		_set_target(glow, glow_los)
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
		var body_first := not _target_los.has(body)
		if not (cell_changed or body_first):
			continue
		var body_los: bool
		if body.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
			body_los = false
		else:
			_query.exclude = [body.get_rid()]
			_query.from = from
			if body is PrototypeDoor:
				# Doors sit flush in the wall plane with jambs flanking them
				# on the same World layer. Aiming at the door's centre lets
				# an off-axis ray clip a jamb before reaching the excluded
				# door, falsely reporting occluded. We offset the test point
				# along the door's local X (wall normal) by 0.6m onto the
				# player's side of the wall — that always lands ~0.4m past
				# the wall surface regardless of approach angle, where a
				# fixed offset along the player-direction would stay inside
				# the wall at glancing angles.
				#
				# We also test two endpoints offset along the door's local Z
				# (along the door width) at ±1.5m. A single central ray can
				# still clip a jamb corner at glancing angles even when the
				# door itself is plainly visible; if any of the three
				# endpoints clears, the door is considered visible.
				var wall_normal := body.global_transform.basis.x
				var door_along := body.global_transform.basis.z
				var to_player := player_pos - body.global_position
				var side: float = signf(to_player.dot(wall_normal))
				if side == 0.0:
					side = 1.0
				var base := body.global_position + wall_normal * (side * 0.6)
				var endpoints: Array[Vector3] = [
					base,
					base + door_along * 1.5,
					base - door_along * 1.5,
				]
				body_los = false
				for ep: Vector3 in endpoints:
					_query.to = Vector3(ep.x, from.y, ep.z)
					if space.intersect_ray(_query).is_empty():
						body_los = true
						break
			else:
				var to_player_xz := Vector3(
					player_pos.x - body.global_position.x,
					0.0,
					player_pos.z - body.global_position.z,
				)
				if to_player_xz.length_squared() > 0.0001:
					to_player_xz = to_player_xz.normalized() * 0.6
				var target_pos := body.global_position + to_player_xz
				_query.to = Vector3(target_pos.x, from.y, target_pos.z)
				body_los = space.intersect_ray(_query).is_empty()
				# Fallback: if the offset-point ray failed, try the body's
				# centre directly. The body's RID is excluded, so a clear ray
				# to centre means nothing else on the World layer sits
				# between player and body. Catches cases where the offset
				# point lands inside another collider while the body itself
				# is visible.
				if not body_los:
					_query.to = Vector3(body.global_position.x, from.y, body.global_position.z)
					body_los = space.intersect_ray(_query).is_empty()
		_set_target(body, body_los)

func _process(delta: float) -> void:
	# Framerate-independent damping: weight = 1 - e^(-rate * dt). Catches up
	# ~63% of the gap each ~0.08s, masking the binary physics-tick LoS flip.
	var weight: float = 1.0 - exp(-FADE_RATE * delta)
	var to_remove: Array = []
	for key in _target_los:
		if not is_instance_valid(key):
			to_remove.append(key)
			continue
		var node := key as Node3D
		# Pooled entities lose their parent on release. Drop their cache entries
		# so a re-acquired instance fades in cleanly instead of inheriting the
		# previous owner's transparency state.
		if not node.is_inside_tree():
			to_remove.append(key)
			continue
		var los: bool = _target_los[key]
		var target_t: float = 0.0 if los else 1.0
		var current: float = _transparency.get(key, 1.0)
		current = lerp(current, target_t, weight)
		_transparency[key] = current
		# Show as soon as the target flips to visible — the alpha fade does the
		# rest. Hide only once we've fully faded out, so a brief LoS flicker
		# (e.g. a pickup briefly behind a glancing wall) doesn't hard-cut.
		if los and not node.visible:
			node.visible = true
		elif not los and current >= HIDE_THRESHOLD and node.visible:
			node.visible = false
		var geoms: Array = _geom_cache.get(key, [])
		for g in geoms:
			if is_instance_valid(g):
				(g as GeometryInstance3D).transparency = current
	for k in to_remove:
		_target_los.erase(k)
		_transparency.erase(k)
		_geom_cache.erase(k)

func _set_target(node: Node3D, los: bool) -> void:
	if not _target_los.has(node):
		# Fresh entries fade in from invisible regardless of initial LoS state —
		# avoids a one-frame flash at full opacity before the first lerp tick.
		_transparency[node] = 1.0
		_geom_cache[node] = _collect_geom(node)
	_target_los[node] = los
	# Pickability follows the discrete LoS target, not the lerped alpha. A
	# faded-but-not-yet-hidden target is still occluded by a wall and clicks
	# through it would be wrong; conversely a fading-in target should be
	# clickable as soon as the player rounds the corner.
	if node is CollisionObject3D:
		(node as CollisionObject3D).input_ray_pickable = los
	for child in node.get_children():
		if child is CollisionObject3D:
			(child as CollisionObject3D).input_ray_pickable = los

func _collect_geom(node: Node) -> Array:
	var out: Array = []
	if node is GeometryInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_geom(child))
	return out

## True if `node` had line of sight to the player as of the most recent physics
## tick. Returns false for nodes that haven't been tested yet — callers should
## treat "unknown" as occluded, which is the safe default for AI gates.
func has_los_to_player(node: Node) -> bool:
	return _target_los.get(node, false)
