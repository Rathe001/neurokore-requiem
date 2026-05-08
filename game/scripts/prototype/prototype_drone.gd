class_name PrototypeDrone
extends CharacterBody3D

# Untargetable hover drone for the Automaton Drone Swarm perk. Each drone
# instance wanders semi-randomly around the player and fires on enemies in
# range. The player spawns / despawns them via _reconcile_drones based on
# the `automaton_drones` perk aggregate.
#
# Movement is wander-toward-random-offset, NOT a fixed orbit. Orbit drones
# in tight rooms would fight wall geometry every loop ("drone stuck on the
# corner of the doorway while you walk past"); wander lets them cluster
# loosely near the player and slide along walls naturally via
# move_and_slide. Each drone re-rolls a new offset (bearing + radius +
# height) every RETARGET_INTERVAL_* seconds and lerps toward it.
#
# Layer setup (.tscn): collision_layer = 0, collision_mask = 1. Drone is
# undetectable to enemies / player / pickups, but world walls (layer 1)
# block it — so the swarm can't shoot through walls. No CollisionObject
# damage path exists either — drones have no take_damage, so the design
# intent ("untargetable, cannot die") still holds.
#
# Stats are hardcoded for now. Future gear mods or talent effects could
# modify these (wander_radius, fire_cooldown, projectile damage type, etc.).

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_projectile.tscn")

# Wander volume around the player. MIN keeps drones from bunching at the
# player's center; MAX keeps the swarm visibly close in dense fights.
const HOVER_RADIUS_MIN := 1.0
const HOVER_RADIUS_MAX := 2.6
const HOVER_HEIGHT_MIN := 1.1
const HOVER_HEIGHT_MAX := 2.2
# Re-roll the wander target on this random cadence — staggered per drone
# so the swarm doesn't all flick to new offsets on the same frame.
const RETARGET_INTERVAL_MIN := 0.7
const RETARGET_INTERVAL_MAX := 2.0
# Swarm-around-enemy offsets — when a chase target is locked, the drone
# orbits at this radius from the target rather than the player. Slightly
# tighter than the wander volume so the swarm reads as "ganging up" on
# whatever the player is engaging.
const SWARM_RADIUS_MIN := 1.4
const SWARM_RADIUS_MAX := 2.4
# Hard leash from the player. Drones won't push past this distance even
# if the chase target is out beyond it — they'll hover at the leash edge
# rather than peel off and chase across the room.
const SWARM_LEASH_FROM_PLAYER := 5.0
# Movement caps. FOLLOW_GAIN scales the seek vector into a velocity; clamp
# at MAX_SPEED so a drone that fell behind doesn't snap-teleport when it
# catches up to a sprinting player.
const FOLLOW_GAIN := 4.5
const MAX_SPEED := 7.0
# Bobbing adds a per-drone vertical sine on top of the wander target —
# small but breaks the "all drones drift in straight lines" feel.
const BOB_AMPLITUDE := 0.10
const BOB_SPEED := 2.4
# Anti-stuck: when a drone strays past this distance from the player (e.g.
# trapped behind a wall or a closed door because move_and_slide couldn't
# find a path back), snap it to the player's position. Generous enough
# that normal wander + brief separation while the player runs ahead don't
# trip it; tight enough that a stuck drone catches up within a few steps.
const TELEPORT_BACK_DISTANCE := 6.0

const ATTACK_RANGE := 9.0
const FIRE_COOLDOWN := 1.4
const PROJECTILE_SPEED := 22.0
const PROJECTILE_BASE_DAMAGE := 8

var _player: Node3D = null
var _wander_offset: Vector3 = Vector3.ZERO
var _retarget_t: float = 0.0
var _bob_phase: float = 0.0
var _fire_cd: float = 0.0
# Currently-engaged enemy + the drone's preferred angle/radius around it.
# Bearing/radius are per-drone so multiple drones swarm from different
# sides instead of overlapping on the same point. Cleared when the target
# dies, charms, leaves LOS, or strays past leash from the player.
var _chase_target: Node3D = null
var _swarm_bearing: float = 0.0
var _swarm_radius: float = 2.0


# Extra args (orbit_index / orbit_total) kept for call-site compatibility
# with the old orbit version — they're unused by the wander behaviour but
# letting them through keeps PrototypePlayer._reconcile_drones from caring
# which movement model is current.
func setup(player: Node3D, _orbit_index: int = 0, _orbit_total: int = 1) -> void:
	_player = player
	# Per-drone phase + initial wander target so the swarm doesn't visibly
	# converge on the same point for the first second after spawn.
	_bob_phase = randf() * TAU
	_pick_new_target()
	# Half-elapsed initial cooldown so the first shot lands quickly when
	# the perk first unlocks — feels responsive.
	_fire_cd = FIRE_COOLDOWN * 0.5
	# Snap to the player's position (slightly elevated) at spawn — using the
	# wander offset here can land the drone outside the room (through walls
	# / doors), where it gets stuck and silently lost. Letting the wander
	# seek pull it outward over the next physics frames is safer.
	if is_inside_tree():
		global_position = player.global_position + Vector3(0.0, 1.6, 0.0)


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# Anti-stuck snap: if we're well outside the wander volume from the
	# player, the drone is almost certainly trapped behind a wall or door
	# (move_and_slide can't path through level geometry). Teleport home
	# and re-roll the wander target so we resume a fresh approach. Cheap
	# distance check, runs every physics tick.
	var to_player := _player.global_position - global_position
	if to_player.length_squared() > TELEPORT_BACK_DISTANCE * TELEPORT_BACK_DISTANCE:
		global_position = _player.global_position + Vector3(0.0, 1.6, 0.0)
		velocity = Vector3.ZERO
		_pick_new_target()
		return
	_validate_chase_target()
	if _chase_target == null:
		_acquire_chase_target()
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_pick_new_target()
	_bob_phase += BOB_SPEED * delta
	# Hover target: swarm around the chase target if we have one, else
	# wander around the player. Either way the bob is added on top so
	# move_and_slide projects against walls without fighting a modulated
	# axis.
	var target: Vector3
	if _chase_target != null:
		target = _swarm_position_for(_chase_target)
	else:
		target = _player.global_position + _wander_offset
	target.y += sin(_bob_phase) * BOB_AMPLITUDE
	var to_target := target - global_position
	velocity = to_target * FOLLOW_GAIN
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED
	# move_and_slide handles wall sliding via collision_mask = 1, so a
	# drone targeting an offset behind a wall slides along the wall toward
	# the nearest reachable point instead of pushing into it.
	move_and_slide()
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		if _try_fire():
			_fire_cd = FIRE_COOLDOWN
		else:
			# No target — re-check on a short cadence rather than waiting a
			# full FIRE_COOLDOWN so the drone reacts quickly when an enemy
			# walks into range.
			_fire_cd = 0.25


# Compute the swarm hover position around a target enemy. The drone keeps
# a fixed bearing+radius for the engagement so it stays on "its side" of
# the enemy instead of orbiting. Result is clamped to SWARM_LEASH_FROM_PLAYER
# so a target running across the map doesn't drag the drone off the player.
func _swarm_position_for(target: Node3D) -> Vector3:
	var hover_y := lerpf(HOVER_HEIGHT_MIN, HOVER_HEIGHT_MAX, 0.5)
	var around := target.global_position + Vector3(
		cos(_swarm_bearing) * _swarm_radius,
		hover_y,
		sin(_swarm_bearing) * _swarm_radius,
	)
	var from_player := around - _player.global_position
	if from_player.length() > SWARM_LEASH_FROM_PLAYER:
		around = _player.global_position + from_player.normalized() * SWARM_LEASH_FROM_PLAYER
	return around


# Drop the current chase target if it died, got charmed, lost LOS to the
# player, or drifted past leash. Leaving stale targets attached makes the
# drone hover over a corpse or tug at the leash edge.
func _validate_chase_target() -> void:
	if _chase_target == null:
		return
	if not is_instance_valid(_chase_target):
		_chase_target = null
		return
	if not _chase_target.is_in_group(&"enemies"):
		_chase_target = null
		return
	if _chase_target.has_method(&"is_player_friendly") and _chase_target.is_player_friendly():
		_chase_target = null
		return
	if not LosCuller.has_los_to_player(_chase_target):
		_chase_target = null
		return
	var to_player := _chase_target.global_position - _player.global_position
	# +2 grace beyond the leash so a target dancing right at the edge
	# doesn't strobe in/out of the chase state every frame.
	if to_player.length() > SWARM_LEASH_FROM_PLAYER + 2.0:
		_chase_target = null


# Pick the nearest visible enemy within ATTACK_RANGE that's also inside
# the player's leash. Roll a fresh swarm bearing/radius per acquisition
# so two drones engaging the same target won't stack on the same point.
func _acquire_chase_target() -> void:
	var best: Node3D = null
	var best_d2 := ATTACK_RANGE * ATTACK_RANGE
	var leash_sq := SWARM_LEASH_FROM_PLAYER * SWARM_LEASH_FROM_PLAYER
	for n in SpatialGrid.query_radius(_player.global_position, ATTACK_RANGE, &"enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method(&"take_damage"):
			continue
		if n.has_method(&"is_player_friendly") and n.is_player_friendly():
			continue
		if not LosCuller.has_los_to_player(n):
			continue
		var d2 := _player.global_position.distance_squared_to(n.global_position)
		if d2 > leash_sq:
			continue
		if d2 < best_d2:
			best_d2 = d2
			best = n
	if best != null:
		_chase_target = best
		_swarm_bearing = randf() * TAU
		_swarm_radius = randf_range(SWARM_RADIUS_MIN, SWARM_RADIUS_MAX)


# Roll a fresh hover offset around the player. Random bearing / radius /
# height every time; drones don't try to space themselves apart, since
# the random offsets naturally desync after a few retargets.
func _pick_new_target() -> void:
	var bearing := randf() * TAU
	var radius := randf_range(HOVER_RADIUS_MIN, HOVER_RADIUS_MAX)
	var height := randf_range(HOVER_HEIGHT_MIN, HOVER_HEIGHT_MAX)
	_wander_offset = Vector3(cos(bearing) * radius, height, sin(bearing) * radius)
	_retarget_t = randf_range(RETARGET_INTERVAL_MIN, RETARGET_INTERVAL_MAX)


# Pick the nearest enemy within ATTACK_RANGE and spawn a projectile aimed
# at chest height. Returns true when a shot was fired so the caller can
# refresh the cooldown only on a real fire.
func _try_fire() -> bool:
	var best: Node3D = null
	var best_dist_sq := ATTACK_RANGE * ATTACK_RANGE
	for n in SpatialGrid.query_radius(global_position, ATTACK_RANGE, &"enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method(&"take_damage"):
			continue
		# Skip player-friendly (charmed) pets — drones are an extension
		# of the player and shouldn't waste shots on bolts that the
		# projectile script will then filter out as friendly fire.
		if n.has_method(&"is_player_friendly") and n.is_player_friendly():
			continue
		# Drones respect line-of-sight from the PLAYER's perspective —
		# they're an extension of the player, not independent scouts.
		# An enemy the player can't see can't be targeted by their
		# drones either, matching the rule for charm / DoT / telekinesis.
		if not LosCuller.has_los_to_player(n):
			continue
		var d2 := global_position.distance_squared_to(n.global_position)
		if d2 < best_dist_sq:
			best_dist_sq = d2
			best = n
	if best == null:
		return false
	var origin := global_position
	var aim_to := best.global_position + Vector3(0.0, 0.9, 0.0) - origin
	if aim_to.length_squared() < 0.0001:
		return false
	var proj: PrototypeProjectile = EntityPool.acquire(PROJECTILE_SCENE)
	if proj == null:
		return false
	proj.target_group = &"enemies"
	proj.direction = aim_to.normalized()
	proj.speed = PROJECTILE_SPEED
	proj.max_range = ATTACK_RANGE + 2.0
	proj.knockback_strength = 0.0
	proj.source_position = global_position
	# Damage scales with the player's main stat — Optimization for
	# Automaton — so investing in the perk's stat heavies up the drones.
	var dmg := int(round(float(PROJECTILE_BASE_DAMAGE) * 1.0))
	proj.damage_min = dmg
	proj.damage_max = dmg
	proj.damage_mult = 1.0
	proj.accuracy = 1.0
	proj.crit_chance = 0.0
	proj.ignore_melee_penalty = true
	get_parent().add_child(proj)
	proj.global_position = origin
	proj.monitoring = true
	proj.reset()
	return true
