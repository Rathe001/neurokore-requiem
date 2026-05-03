class_name TelekinesisGrab
extends Node3D

# Polymath Telekinesis grab — owns one bolt's full lift-slam-AoE
# sequence on a single enemy. PrototypePlayer spawns one of these per
# bolt; each is independent so a T3 4-bolt trigger means 4 grabs
# running in parallel on (up to) 4 distinct enemies.
#
# Lifecycle:
#   _ready    — flip target into State.GRABBED, build the persistent
#               beam, start the lift tween
#   lift      — over LIFT_DURATION seconds, tween target.global_position.y
#               from start to start + LIFT_HEIGHT (cubic ease-out)
#   slam      — over SLAM_DURATION seconds, snap target back to start_y
#               (quad ease-in for the satisfying drop)
#   impact    — release the grab, deal direct damage to the target +
#               radial AoE around the landing point, queue_free
#
# Beam: a thin emissive cylinder MeshInstance3D updated each frame to
# stretch between the player's head and the lifted target's chest.
# Persists for the entire grab lifetime (the original spawn_beam
# was a one-shot flash that disappeared instantly — wrong for a 2s
# psionic hold).

const LIFT_DURATION := 2.0
const LIFT_HEIGHT := 3.5
const SLAM_DURATION := 0.25
const AOE_RADIUS := 2.6
# Direct damage goes to the lifted target; AoE damage to anyone else
# inside AOE_RADIUS at landing time. Lower than direct so a swarm of
# enemies isn't all wiped by one bolt.
const AOE_DAMAGE_FACTOR := 0.6
const AOE_KNOCKBACK := 5.0

const BEAM_THICKNESS := 0.025
const BEAM_COLOR := Color(0.95, 0.85, 1.0, 1.0)  # pale violet — Polymath head energy
const BEAM_PLAYER_HEAD_OFFSET := Vector3(0.0, 1.55, 0.0)
const BEAM_TARGET_OFFSET := Vector3(0.0, 0.9, 0.0)  # chest height on the enemy

var _player: Node3D
var _target: Node3D
var _direct_damage: int = 0
var _start_y: float = 0.0
var _beam_mesh: MeshInstance3D
var _completed: bool = false


func setup(player: Node3D, target: Node3D, direct_damage: int) -> void:
	_player = player
	_target = target
	_direct_damage = direct_damage


func _ready() -> void:
	if not _is_target_grabbable():
		queue_free()
		return
	if not _target.has_method(&"apply_grab") or not _target.apply_grab():
		queue_free()
		return
	_start_y = _target.global_position.y
	_build_beam()
	_update_beam()
	# Lift on a tween — TRANS_CUBIC + EASE_OUT gives a satisfying
	# "yanked up, slows at the top" arc.
	var lift_tween := create_tween()
	lift_tween.tween_property(_target, "global_position:y", _start_y + LIFT_HEIGHT, LIFT_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	lift_tween.tween_callback(_start_slam)


func _process(_delta: float) -> void:
	# Cancel cleanly if the target dies / is freed mid-lift. The
	# already-running tween would otherwise fault on the freed instance.
	if _completed:
		return
	if not _is_target_alive():
		_cancel()
		return
	_update_beam()


func _start_slam() -> void:
	if _completed or not _is_target_alive():
		_cancel()
		return
	var slam_tween := create_tween()
	slam_tween.tween_property(_target, "global_position:y", _start_y, SLAM_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	slam_tween.tween_callback(_apply_impact)


func _apply_impact() -> void:
	if _completed:
		return
	_completed = true
	if not _is_target_alive():
		_cancel()
		return
	var landing_pos: Vector3 = _target.global_position
	# Snap THIS node to the landing position BEFORE spawning the radial
	# indicator — spawn_hit_radial reads host.global_position, so passing
	# `self` while still at world origin (the bug we were seeing) put
	# the AoE pulse at the player's feet instead of at the slammed
	# enemy. Capture the player's position first because we still want
	# the take_damage knockback origin to point back at the player.
	var player_pos: Vector3 = _player.global_position
	global_position = landing_pos
	PrototypeAttackIndicator.spawn_hit_radial(self, AOE_RADIUS)
	# Release BEFORE dealing damage so the take_damage knockback can
	# move the target normally (KNOCKBACK state expects to control
	# velocity, which GRABBED was suspending).
	if _target.has_method(&"release_grab"):
		_target.release_grab()
	if _target.has_method(&"take_damage"):
		_target.take_damage(_direct_damage, player_pos, 0.0)
	# AoE damage to neighbours. Radius query uses the post-slam landing
	# position; the lifted target may have moved horizontally during
	# the lift if it got grabbed mid-stride.
	var aoe_damage := int(round(float(_direct_damage) * AOE_DAMAGE_FACTOR))
	for n in SpatialGrid.query_radius(landing_pos, AOE_RADIUS, &"enemies"):
		if n == _target or not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method(&"take_damage"):
			continue
		n.take_damage(aoe_damage, landing_pos, AOE_KNOCKBACK)
	queue_free()


func _cancel() -> void:
	# Target died / despawned mid-lift. Drop the body back to start_y
	# before releasing — without this a corpse gets stranded mid-air
	# (DEAD state suspends physics, so it won't fall on its own).
	# Then release the grab in case the state survived (corpse paths
	# skip release).
	if _target != null and is_instance_valid(_target):
		var pos: Vector3 = _target.global_position
		pos.y = _start_y
		_target.global_position = pos
		if _target.has_method(&"release_grab"):
			_target.release_grab()
	queue_free()


func _is_target_grabbable() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if not _target.has_method(&"take_damage"):
		return false
	return _is_target_alive()


func _is_target_alive() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	# PrototypeEnemy._is_alive returns false when DEAD; group check
	# catches corpses moved out of &"enemies" by _become_corpse.
	if _target.is_in_group(&"corpses"):
		return false
	if _target is PrototypeEnemy and not (_target as PrototypeEnemy)._is_alive():
		return false
	return true


func _build_beam() -> void:
	_beam_mesh = MeshInstance3D.new()
	# BoxMesh with the long axis on Z so look_at can orient the beam
	# directly: look_at(target) points the node's local -Z at target,
	# so a Z-elongated box becomes a beam from origin toward target.
	# CylinderMesh + scaled basis was unreliable here — render order
	# kept collapsing to a 1-unit stub regardless of the Y scale.
	var box := BoxMesh.new()
	box.size = Vector3(BEAM_THICKNESS * 2.0, BEAM_THICKNESS * 2.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b, 0.9)
	mat.emission_enabled = true
	mat.emission = BEAM_COLOR
	mat.emission_energy_multiplier = 8.0
	mat.disable_receive_shadows = true
	# Avoid depth-write so overlapping beams (multi-bolt T3) don't
	# punch holes in each other.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	box.material = mat
	_beam_mesh.mesh = box
	_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam_mesh)


# Stretch the box between player-head and target-chest each frame.
# look_at orients local -Z at target, so we just scale Z by the
# distance to span the gap. midpoint placement means the box extends
# (dist/2) toward the target and (dist/2) away — total length = dist.
func _update_beam() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _target == null or not is_instance_valid(_target):
		return
	if _beam_mesh == null:
		return
	var origin: Vector3 = _player.global_position + BEAM_PLAYER_HEAD_OFFSET
	var target_pos: Vector3 = _target.global_position + BEAM_TARGET_OFFSET
	var to_target := target_pos - origin
	var dist := to_target.length()
	if dist < 0.001:
		_beam_mesh.visible = false
		return
	_beam_mesh.visible = true
	# Reset transform first — look_at fails when the resulting basis is
	# parallel to the prior one, and scale leaks across frames if not
	# reset. Cheaper than tracking dirty state.
	_beam_mesh.global_transform = Transform3D(Basis.IDENTITY, (origin + target_pos) * 0.5)
	# look_at requires a non-parallel up vector. For nearly-vertical
	# beams (rare during a 2s lift but possible for a tall enemy under
	# the player), fall back to Vector3.RIGHT.
	var dir := to_target / dist
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	_beam_mesh.look_at(target_pos, up)
	_beam_mesh.scale = Vector3(1.0, 1.0, dist)
