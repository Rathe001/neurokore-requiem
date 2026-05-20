class_name Footsteps
extends RefCounted
## Shared footstep accumulation + floor-type detection.
## Both PrototypePlayer and PrototypeEnemy call tick() each physics frame.

# Bloody footprints fire on their own sub-stride accumulator, not the
# audio/dust footstep threshold. A real heel-to-heel gait is ~70 cm; at
# the old 1.7 m audio cadence prints landed every other stride and the
# trail looked sparse and oversized.
const BLOODY_FOOTSTEP_DISTANCE: float = 0.7

## Accumulate horizontal distance and emit a footstep when threshold crossed.
## Returns the updated [accum, last_pos] so callers can store them. Pass
## spawn_puff = true for the local player (enemy puffs are too noisy at scale).
static func tick(
	body: CharacterBody3D,
	accum: float,
	last_pos: Vector3,
	distance_threshold: float,
	volume_db: float,
	spawn_puff: bool,
	at_listener: bool = false,
) -> Array:
	var pos := body.global_position
	if last_pos == Vector3.ZERO:
		return [accum, pos]
	if not body.is_on_floor():
		return [accum, pos]
	var delta_v := pos - last_pos
	delta_v.y = 0.0
	var d := delta_v.length()
	if d < 0.001:
		return [accum, pos]
	# Bloody trail runs on its own short-stride accumulator so prints
	# land at every footfall, not every other audio step. Cheap early-
	# out inside _handle_bloody_footstep when not in blood.
	if spawn_puff:
		var bloody_accum: float = float(body.get_meta(&"bloody_accum", 0.0)) + d
		if bloody_accum >= BLOODY_FOOTSTEP_DISTANCE:
			bloody_accum = 0.0
			var bloody_scene := body.get_tree().current_scene
			if bloody_scene != null:
				_handle_bloody_footstep(body, bloody_scene, pos, delta_v)
		body.set_meta(&"bloody_accum", bloody_accum)
	accum += d
	if accum >= distance_threshold:
		accum = 0.0
		if spawn_puff:
			var scene := body.get_tree().current_scene
			if scene != null:
				PrototypeAttackIndicator.spawn_footstep_puff(scene, pos)
		var floor_key := detect_floor_type(body)
		WeaponSounds.play_generic(floor_key, pos, volume_db, at_listener)
	return [accum, pos]


# Bloody footprint emission. Refresh-then-spawn order:
#   1. If currently standing in any blood decal, recharge the counter
#      to BLOODY_STEPS_INITIAL so the next print is full-intensity.
#   2. Spawn the print using the current counter (post-recharge) and
#      decrement.
# step_idx parity drives both the lateral offset (L/R of body centerline)
# AND which boot-print silhouette is used (right-foot vs mirrored).
static func _handle_bloody_footstep(body: CharacterBody3D, scene: Node, pos: Vector3, move_delta: Vector3) -> void:
	if PrototypeAttackIndicator.is_in_blood(pos):
		body.set_meta(&"bloody_steps_remaining", PrototypeAttackIndicator.BLOODY_STEPS_INITIAL)
	var remaining: int = int(body.get_meta(&"bloody_steps_remaining", 0))
	if remaining <= 0:
		return
	var step_idx: int = int(body.get_meta(&"bloody_step_idx", 0))
	var move_dir: Vector3 = move_delta.normalized() if move_delta.length_squared() > 0.0001 else Vector3.FORWARD
	# Right vector in the XZ plane = UP × forward.
	var right: Vector3 = Vector3.UP.cross(move_dir).normalized()
	var right_foot: bool = step_idx % 2 == 0
	# Lateral half-stance: ~10 cm off centerline matches the new 22 cm
	# print width without overlapping its mirror across the midline.
	var lateral: Vector3 = right * (0.10 if right_foot else -0.10)
	var intensity: float = float(remaining) / float(PrototypeAttackIndicator.BLOODY_STEPS_INITIAL)
	PrototypeAttackIndicator.spawn_blood_footprint(scene, pos + lateral, move_dir, intensity, right_foot)
	body.set_meta(&"bloody_steps_remaining", remaining - 1)
	body.set_meta(&"bloody_step_idx", step_idx + 1)


## Check the floor body under a CharacterBody3D for a material-type group.
static func detect_floor_type(body: CharacterBody3D) -> StringName:
	for i in body.get_slide_collision_count():
		var col := body.get_slide_collision(i)
		if col.get_normal().y < 0.5:
			continue
		var collider := col.get_collider()
		if collider is Node and collider.is_in_group(&"floor_grate"):
			return &"footstep_grate"
	return &"footstep_metal"
