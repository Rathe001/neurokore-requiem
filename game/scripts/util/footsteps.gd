class_name Footsteps
extends RefCounted
## Shared footstep accumulation + floor-type detection.
## Both PrototypePlayer and PrototypeEnemy call tick() each physics frame.

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
