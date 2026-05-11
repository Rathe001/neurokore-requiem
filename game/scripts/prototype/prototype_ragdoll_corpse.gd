class_name PrototypeRagdollCorpse
extends RigidBody3D

# Self-managed physics corpse. Spawned by PrototypeEnemy on death with a
# clone of the enemy's visual subtree. Tumbles via gravity + initial impulse,
# auto-sleeps when at rest, melts into the floor at LIFETIME and queue_frees.
#
# Walk-through push: the rigid body itself only collides with World (Layer 1),
# so live enemies AND the player walk straight through. A child Area3D sensor
# detects the player overlapping us — while inside, we apply a per-tick
# impulse along the player's velocity. Net effect: corpses brush aside as the
# player wades through them, but never block movement. Grenades hit
# apply_explosion_impulse directly via the &"ragdoll_corpses" group.
#
# Not pooled — corpses are short-lived (LIFETIME), so the per-spawn cost of
# instantiation + visual.duplicate() is bounded. If profile shows churn we
# can pool the RigidBody shell separately and just swap visuals.

const LIFETIME: float = 20.0
const SINK_DURATION: float = 1.5
const SINK_DEPTH: float = 1.4
const DEATH_IMPULSE_MIN: float = 4.0
const DEATH_IMPULSE_MAX: float = 7.5
const DEATH_LIFT_FACTOR: float = 0.35  # vertical:horizontal ratio for the kill toss
# Per-tick impulse magnitude when the player is overlapping us = speed *
# WADE_PUSH_FORCE. Tuned so a walking player nudges the corpse aside over
# ~half a second of contact, while a sprint bowls it out of the way.
const WADE_PUSH_FORCE: float = 0.045

# Corpses use Layer 6 (Corpses) for the rigid body so the &"ragdoll_corpses"
# group is also queryable via physics if we ever want it. Mask = Layer 1
# (World) only — neither the player CharacterBody3D nor live enemies collide
# with Layer 6, so they pass through unimpeded.
const LAYER_CORPSE: int = 32  # 1 << 5
const MASK_WORLD: int = 1     # 1 << 0
# Pillars on Layer 8 — physical obstacles like walls, just LoS-transparent.
# Including them in the corpse's collision mask lets ragdolls bounce off
# decorative columns instead of intersecting them.
const MASK_PILLAR: int = 128  # 1 << 7
# Player layer (Layer 3) — used by the Area3D sensor's collision_mask so it
# detects only the player's body and not enemies/pickups/projectiles.
const MASK_PLAYER: int = 4    # 1 << 2

var _age: float = 0.0
var _expired: bool = false
var _visual_root: Node3D = null
# Player CharacterBody3D currently overlapping the wade sensor (or null).
# Captured on body_entered, cleared on body_exited; sampled in
# _physics_process to compute the per-tick nudge direction.
var _player_in_range: Node3D = null
var _wade_sensor: Area3D = null


func _ready() -> void:
	add_to_group(&"ragdoll_corpses")
	collision_layer = LAYER_CORPSE
	collision_mask = MASK_WORLD | MASK_PILLAR
	# Auto-sleep keeps resting bodies cheap — explosions / player push
	# auto-wake on apply_central_impulse.
	can_sleep = true
	# We don't react to contacts in script, so don't pay the monitor cost.
	contact_monitor = false
	# A bit of linear/angular damp keeps the tumble from sliding forever
	# on the polished low-poly floors.
	linear_damp = 0.4
	angular_damp = 1.2
	# Slight CCD margin so a fast-tumbling body doesn't tunnel through
	# thin walls.
	continuous_cd = true


# Builds collision + wade sensor + parents the cloned visual. Caller passes
# capsule sizing so different enemy footprints (small drone, basic biped,
# boss) tumble at their own scale.
func setup_visual(visual: Node3D, capsule_height: float, capsule_radius: float) -> void:
	var clamped_h: float = maxf(capsule_height, capsule_radius * 2.0 + 0.05)
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	# Capsule height in Godot is the FULL length including the two
	# hemispheres; clamp to >= 2*radius so we don't get a degenerate shape.
	shape.height = clamped_h
	shape.radius = capsule_radius
	collider.shape = shape
	add_child(collider)
	# Wade sensor: slightly larger Area3D capsule that detects the player.
	# Bigger so the corpse starts being pushed BEFORE the player's body fully
	# overlaps the rigid-body capsule — feels like wading through bodies
	# instead of stepping into a force field. Layer 0 (not detectable) so the
	# sensor itself never trips other systems.
	_wade_sensor = Area3D.new()
	_wade_sensor.collision_layer = 0
	_wade_sensor.collision_mask = MASK_PLAYER
	_wade_sensor.monitoring = true
	_wade_sensor.monitorable = false
	var sensor_col := CollisionShape3D.new()
	var sensor_shape := CapsuleShape3D.new()
	sensor_shape.height = clamped_h + 0.4
	sensor_shape.radius = capsule_radius + 0.2
	sensor_col.shape = sensor_shape
	_wade_sensor.add_child(sensor_col)
	add_child(_wade_sensor)
	_wade_sensor.body_entered.connect(_on_wade_body_entered)
	_wade_sensor.body_exited.connect(_on_wade_body_exited)
	# Visual sits under the rigid body's origin — center it vertically so
	# the capsule's local Y aligns with the mesh's spine.
	visual.position = Vector3(0.0, -clamped_h * 0.5, 0.0)
	add_child(visual)
	_visual_root = visual
	# Stop any animation on the clone so the bones stay frozen at whatever
	# pose the enemy was duplicated in. Otherwise the duplicate's anim
	# player keeps re-applying tracks and the corpse never visually settles.
	_freeze_animations(visual)


func _on_wade_body_entered(body: Node) -> void:
	# Only the player should match (mask = Layer 3) — group check is a
	# belt-and-braces guard against future layer reuse.
	if body.is_in_group(&"player") and body is Node3D:
		_player_in_range = body as Node3D


func _on_wade_body_exited(body: Node) -> void:
	if body == _player_in_range:
		_player_in_range = null


func _freeze_animations(node: Node) -> void:
	if node is AnimationPlayer:
		var ap := node as AnimationPlayer
		# stop(true) flushes pending track values so the clip's last applied
		# pose persists; stop(false) would leave bones at whatever they were
		# at duplicate-time which is sometimes mid-blend.
		ap.stop(true)
		ap.active = false
	for child in node.get_children():
		_freeze_animations(child)


# Initial tumble from the killing hit. Direction is the kill_from→corpse
# vector (already normalized by caller); force=0 picks a random magnitude.
func apply_death_impulse(direction: Vector3, force: float = 0.0) -> void:
	var horiz := Vector3(direction.x, 0.0, direction.z)
	if horiz.length_squared() > 0.0001:
		horiz = horiz.normalized()
	else:
		# Killed point-blank or by an unsourced hit — pick a random horizontal
		# direction so the body still tumbles instead of dropping straight down.
		var a := randf() * TAU
		horiz = Vector3(cos(a), 0.0, sin(a))
	var f := force if force > 0.001 else randf_range(DEATH_IMPULSE_MIN, DEATH_IMPULSE_MAX)
	var impulse := horiz * f + Vector3.UP * f * DEATH_LIFT_FACTOR
	apply_central_impulse(impulse)
	# Random torque so the body spins on multiple axes — without this, a
	# pure-horizontal impulse on a centered capsule produces almost no
	# rotation and the corpse just slides flat.
	apply_torque_impulse(Vector3(
		randf_range(-2.0, 2.0),
		randf_range(-1.0, 1.0),
		randf_range(-2.0, 2.0),
	))


# Called by grenades and other AoE sources. force is in linear-impulse units
# applied along (corpse - blast_origin); falloff math lives in the caller.
func apply_explosion_impulse(blast_origin: Vector3, force: float) -> void:
	if _expired:
		return
	var diff := global_position - blast_origin
	var dist := diff.length()
	if dist < 0.001:
		# Corpse sitting on top of the blast — pick a random horizontal toss.
		var a := randf() * TAU
		diff = Vector3(cos(a), 0.0, sin(a))
		dist = 1.0
	var dir := diff / dist
	apply_central_impulse(dir * force + Vector3.UP * force * 0.45)
	apply_torque_impulse(Vector3(
		randf_range(-3.0, 3.0),
		randf_range(-1.5, 1.5),
		randf_range(-3.0, 3.0),
	))


# Per-tick wade nudge while the player overlaps. impulse_mag is force *
# delta on the caller's side, so this just applies the impulse without
# further scaling.
func apply_wade_nudge(direction: Vector3, impulse_mag: float) -> void:
	if _expired or impulse_mag <= 0.0:
		return
	apply_central_impulse(direction * impulse_mag)
	# Tiny torque so the corpse rolls/spins as it gets shoved instead of
	# just sliding flat. Scaled to the impulse so a slow walk-through
	# barely rotates it but a sprint sends it tumbling.
	var t := impulse_mag * 0.3
	apply_torque_impulse(Vector3(
		randf_range(-t, t),
		randf_range(-t * 0.5, t * 0.5),
		randf_range(-t, t),
	))


## Floor Y below which we assume the corpse fell into a pit. Slightly below
## zero so corpses on ramps / uneven terrain don't false-trigger, but well
## above the pit kill areas so we clean up before landing on WorldBottom.
const PIT_DESPAWN_Y: float = -1.5

func _physics_process(delta: float) -> void:
	if _expired:
		return
	# Corpse fell off the level (pit, gap in geometry) — despawn immediately.
	if global_position.y < PIT_DESPAWN_Y:
		_expired = true
		queue_free()
		return
	_age += delta
	if _age >= LIFETIME:
		_begin_sink()
		return
	# While the player wades through us, push the corpse along their heading
	# at a per-second rate of speed * WADE_PUSH_FORCE (multiplied by delta
	# so the per-tick impulse stays framerate-independent).
	if _player_in_range != null and is_instance_valid(_player_in_range):
		if "velocity" in _player_in_range:
			var pv: Vector3 = _player_in_range.velocity
			pv.y = 0.0
			var speed := pv.length()
			if speed > 0.1:
				apply_wade_nudge(pv / speed, speed * WADE_PUSH_FORCE * delta * 60.0)
	else:
		_player_in_range = null


# Sink-and-shrink: freeze physics, tween the rigid body's Y down by SINK_DEPTH
# and the visual's scale toward zero, then queue_free. Freezing first means
# the gravity/collisions don't fight the tween. Shrinking the visual (not the
# rigid body) avoids weird scale-on-rigid-body warnings; the collision shape
# stays its original size during the brief sink, which is invisible anyway.
func _begin_sink() -> void:
	_expired = true
	set_deferred(&"freeze", true)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "global_position:y", global_position.y - SINK_DEPTH, SINK_DURATION)
	if _visual_root != null:
		t.tween_property(_visual_root, "scale", _visual_root.scale * 0.2, SINK_DURATION)
	t.set_parallel(false)
	t.tween_callback(queue_free)
