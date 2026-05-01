extends RefCounted
class_name StepUp

## Auto step-up helper for CharacterBody3D. Call AFTER move_and_slide() each
## physics frame, passing the horizontal velocity the body WANTED before the
## slide consumed it. Lets bodies walk onto curbs, pit-edge fences, and
## (eventually) stairs without triggering the jump arc.
##
## Algorithm: when the body is grounded and just hit a wall, probe a virtual
## "lift → advance → drop" path with test_move(). If all three legs clear, the
## obstacle is short enough to step on, and we teleport the body to the landed
## position. If any leg is blocked, we bail and the body stays put — gameplay
## sees the same hard stop it would have without the helper.
##
## Step-up is intentionally instant (no partial-frame interpolation): single
## physics-tick teleports of <= step_height are imperceptible at typical step
## heights (0.3–0.5m), and an interpolated version would have to fight the
## body's own velocity integration the next frame.

## Returns true if a step was applied. Callers can use that signal to suppress
## landing FX, etc. — most won't need the return value.
static func try(body: CharacterBody3D, wish_horiz: Vector3, step_height: float, delta: float) -> bool:
	# Only step when grounded and currently obstructed. Airborne = mid-jump,
	# we don't want to teleport mid-flight. No wall = nothing to step over.
	if not body.is_on_floor():
		return false
	if not body.is_on_wall():
		return false

	# Use the wished horizontal velocity, not body.velocity, because
	# move_and_slide may have zeroed/reduced velocity against the wall —
	# losing the very direction we'd need to step in.
	var motion := Vector3(wish_horiz.x, 0.0, wish_horiz.z) * delta
	if motion.length_squared() < 0.0001:
		return false

	var xform := body.global_transform
	var up := Vector3(0.0, step_height, 0.0)

	# Probe 1: lift. If a low ceiling (or the obstacle's own top, when it's
	# taller than step_height) blocks the lift, this isn't a step — it's a
	# wall.
	if body.test_move(xform, up):
		return false
	xform.origin += up

	# Probe 2: advance horizontally from the lifted position. If still blocked
	# up here, the obstacle extends above step_height — also not a step.
	if body.test_move(xform, motion):
		return false
	xform.origin += motion

	# Probe 3: drop back down. We MUST hit a floor within step_height — if the
	# advance landed us over open air (e.g. the far side of a pit-edge fence),
	# we'd be stepping into the pit, which is exactly what the fence was
	# preventing. Bailing here keeps the original guard rail behavior.
	var drop := Vector3(0.0, -step_height, 0.0)
	var drop_hit := KinematicCollision3D.new()
	if not body.test_move(xform, drop, drop_hit):
		return false

	# Commit. drop_hit.get_travel() is the actual downward distance traveled
	# before the surface stopped the probe — places the body flush with the
	# step's top surface.
	body.global_position = xform.origin + drop_hit.get_travel()
	return true
