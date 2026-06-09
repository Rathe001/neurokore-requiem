class_name UpperBodyAimModifier
extends SkeletonModifier3D
## Overlays a ranged-fire pose onto the UPPER body only (spine → arms) while
## the legs keep playing whatever the locomotion picker chose. Runs as a
## SkeletonModifier3D, i.e. AFTER the AnimationPlayer has posed the skeleton
## each update, so it blends on top of idle / run / strafe without disturbing
## the hips or legs.
##
## Why this exists: the old approach swapped the WHOLE body to a fire clip
## while firing, which (a) floated the feet — the Mixamo fire clip sits the
## hips higher than the locomotion clips — and (b) froze the legs, so the
## player couldn't aim and run at the same time. Keeping the lower body on the
## grounded locomotion clips and overlaying only the torso+arms fixes both,
## and the ramped `influence` makes the idle↔aim transition smooth instead of
## snapping.
##
## Lifecycle (driven by the player each physics tick):
##   configure(skel, anim_player, clip_name) — resolve which clip's rotation
##       tracks map onto our upper-body bones. Call again when the equipped
##       weapon class changes (pistol fire pose ≠ rifle fire pose).
##   tick(delta, aiming) — ramp influence toward 1 (aiming) / 0 (not) and
##       advance the recoil clock.
##   pulse_recoil() — restart the sampled clip from frame 0 on a shot event so
##       each shot reads as a fresh recoil cycle.

# Bones to overlay with the aim/swing pose. Hips IS included even though
# the rest of the leg chain isn't — the Mixamo strafe clips author Hips
# rotation to face the strafe direction, and applying spine/arm tracks
# LOCAL to that rotated Hips left the upper body twisted toward the
# strafe direction even with the overlay at full weight. Overlaying Hips
# with the fire-pose Hips (identity-ish, facing forward) cancels that
# propagation. Leg bones below Hips still play the locomotion / strafe
# clip uncontested.
const _UPPER_SHORT_NAMES: Array[StringName] = [
	&"Hips",
	&"Spine", &"Spine1", &"Spine2", &"Neck", &"Head",
	&"LeftShoulder", &"LeftArm", &"LeftForeArm", &"LeftHand",
	&"RightShoulder", &"RightArm", &"RightForeArm", &"RightHand",
]

# Seconds for influence to travel the full 0→1 (or 1→0). Short enough to feel
# responsive, long enough that the arm raise doesn't snap.
@export var ramp_time: float = 0.18
# Playback rate of the sampled clip while held. 1.0 = native; the recoil clock
# wraps at clip length so a looping fire clip keeps cycling.
@export var recoil_speed: float = 1.0

# Blend weight, ramped by tick(). Named _weight (not `influence`) because
# SkeletonModifier3D already defines a native `influence` property; we do the
# blend ourselves and leave the native one at its default.
var _weight: float = 0.0
var _target: float = 0.0
var _recoil_time: float = 0.0

var _anim: Animation = null
var _clip_len: float = 0.0
# Cached [{ "bone": int, "track": int }] for every upper-body rotation track
# in the configured clip. Empty → modifier is a no-op.
var _tracks: Array[Dictionary] = []
var _configured_clip: StringName = &""
# Tracks whether the current configure() included Hips. Lets the same
# clip be reconfigured with a different Hips policy (e.g. reload sets
# false, fire pose sets true) without the early-out short-circuiting.
var _configured_includes_hips: bool = true

# One-shot melee swing: plays a swing clip ONCE over a set duration on the
# upper body while the legs keep locomoting. Mutually exclusive with the
# looping aim hold (you either hold a gun or swing a melee weapon, never both).
var _swing_active: bool = false
var _swing_time: float = 0.0
var _swing_duration: float = 0.0

# Set of short names for O(1) membership during configure.
static var _upper_set: Dictionary = {}


func _init() -> void:
	if _upper_set.is_empty():
		for n in _UPPER_SHORT_NAMES:
			_upper_set[n] = true


## Resolve which of `clip_name`'s rotation tracks drive our upper-body bones.
## Idempotent for the same clip; cheap to call every tick (early-out on match).
## `include_hips` defaults to true (matches the fire-pose use case where
## overlaying Hips cancels strafe-clip body twist). Pass false for reload /
## other overlays whose source clip authors a backward lean on Hips that
## shouldn't propagate into gameplay stance.
func configure(skel: Skeleton3D, anim_player: AnimationPlayer, clip_name: StringName, include_hips: bool = true) -> void:
	if clip_name == _configured_clip and not _tracks.is_empty() and include_hips == _configured_includes_hips:
		return
	_configured_clip = clip_name
	_configured_includes_hips = include_hips
	_tracks.clear()
	_anim = null
	_clip_len = 0.0
	if skel == null or anim_player == null or clip_name == &"" or not anim_player.has_animation(clip_name):
		return
	_anim = anim_player.get_animation(clip_name)
	_clip_len = _anim.length
	for ti in _anim.get_track_count():
		if _anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		# Bone track paths look like `Skeleton3D:mixamorig_Spine`; the
		# concatenated subname is the bone name the track drives.
		var full := String(_anim.track_get_path(ti).get_concatenated_subnames())
		if full == "":
			continue
		var short := full.trim_prefix("mixamorig_")
		if not _upper_set.has(StringName(short)):
			continue
		if not include_hips and short == &"Hips":
			continue
		var bone := skel.find_bone(StringName(full))
		if bone < 0:
			bone = skel.find_bone(StringName(short))
		if bone >= 0:
			_tracks.append({"bone": bone, "track": ti})


## Per-physics-tick state update. `aiming` raises the overlay, otherwise it
## falls back to zero (full locomotion). Advancing the recoil clock here (not
## in _process_modification, which has no delta) keeps the cadence frame-rate
## independent.
func tick(delta: float, aiming: bool) -> void:
	# Swing takes priority: scrub the swing clip across its full length over
	# the swing duration at full weight. When it finishes, fall through so the
	# weight ramps back to the aim target (0 for melee) for a smooth settle.
	if _swing_active:
		_swing_time += delta
		if _swing_time < _swing_duration and _clip_len > 0.0:
			_recoil_time = (_swing_time / _swing_duration) * _clip_len
			_weight = 1.0
			return
		_swing_active = false
	_target = 1.0 if aiming else 0.0
	_weight = move_toward(_weight, _target, delta / maxf(ramp_time, 0.001))
	if aiming and _clip_len > 0.0:
		_recoil_time = fmod(_recoil_time + delta * recoil_speed, _clip_len)


## Start a one-shot upper-body overlay (melee swing, reload, etc.): play
## `clip_name` once over `duration` seconds on the upper-body bones. The
## legs are left to the locomotion picker so the player can keep moving.
##
## `include_hips` defaults to true (matches the melee-swing case where
## Hips contributes to the visible follow-through). Pass false for clips
## whose authored Hips pose shouldn't propagate into gameplay stance —
## the reload clip in particular leans back to balance the rifle, which
## reads as the avatar tipping backward while reloading.
func play_swing(skel: Skeleton3D, anim_player: AnimationPlayer, clip_name: StringName, duration: float, include_hips: bool = true) -> void:
	configure(skel, anim_player, clip_name, include_hips)
	if _anim == null:
		return
	_swing_active = true
	_swing_time = 0.0
	_swing_duration = maxf(duration, 0.05)


## Restart the sampled clip from frame 0 — call on a shot event so the upper
## body kicks through a fresh recoil cycle per shot.
func pulse_recoil() -> void:
	_recoil_time = 0.0


# Runs inside the skeleton's update pass, after the AnimationPlayer has set
# the base pose. Slerps each upper-body bone from its current (locomotion)
# rotation toward the sampled aim rotation by `influence`.
func _process_modification() -> void:
	if _weight <= 0.001 or _anim == null or _tracks.is_empty():
		return
	var skel := get_skeleton()
	if skel == null:
		return
	for t in _tracks:
		var aim_rot: Quaternion = _anim.rotation_track_interpolate(t["track"], _recoil_time)
		var cur: Quaternion = skel.get_bone_pose_rotation(t["bone"])
		skel.set_bone_pose_rotation(t["bone"], cur.slerp(aim_rot, _weight))
