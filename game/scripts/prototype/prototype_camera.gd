extends Camera3D
class_name PrototypeCamera

## Fixed-bearing follow camera. The @export `offset` defines the default
## camera position relative to the target — its magnitude becomes the orbit
## distance, its horizontal direction becomes the bearing, and the angle from
## vertical becomes the default pitch. Holding the middle mouse button and
## dragging the mouse vertically rotates the pitch between top-down and steep
## isometric, preserving distance + bearing.

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(4, 14, 4)
## Holding mouse-wheel-button and dragging vertically tilts the pitch.
## Off = camera is fixed at the @export offset's pitch.
@export var enable_pitch_drag: bool = true
## Radians of pitch change per pixel of mouse Y motion. Drag down = pitch
## up (toward side view); drag up = pitch toward top-down.
@export var pitch_drag_sensitivity: float = 0.005

# Pitch is angle from vertical: 0 rad = camera straight overhead (top-down),
# PI/2 = camera at target's height. Clamped well short of horizontal so the
# floor doesn't disappear behind the player.
# PITCH_MIN intentionally NOT 0 — at exactly straight-down, the camera
# forward vector flattens to zero in PrototypePlayer's wish-dir math and
# W/S input becomes ambiguous (read as "reversed"). 0.06 rad ≈ 3.4°
# off vertical: visually indistinguishable from true top-down but keeps
# basis.z non-degenerate in the horizontal plane.
const PITCH_MIN := 0.06
const PITCH_MAX := PI / 3.0  # 60° from vertical = 30° above the horizon

# Tolerance for "at default pitch" — middle-mouse drags accumulate small
# float drift, so direct equality on radians flickers. ~0.6° is well below
# what the player can resolve visually.
const PITCH_DEFAULT_EPSILON := 0.01

var _target: Node3D
var _pitch_rad: float = 0.0
var _default_pitch_rad: float = 0.0
var _bearing_rad: float = 0.0
var _distance: float = 1.0
var _mw_held: bool = false
# Camera shake — current jitter magnitude (in world units). Set by
# shake() and tweened back to 0 over the requested duration. Applied
# as a random Vector3 offset in _snap_to_target each frame. Per-camera
# so MP-safe (every player's iso camera shakes independently on
# their own hits).
var _shake_intensity: float = 0.0

# ── Cursor look-ahead ──────────────────────────────────────────────────────
# Camera focus blends toward the player's cursor by LOOKAHEAD_PCT of
# the player→cursor offset, clamped to LOOKAHEAD_MAX_DIST. Smooths via
# a lerp on the held offset so the camera doesn't snap on fast cursor
# motion. Makes the iso view feel responsive to aim direction —
# Diablo / Lost Ark style.
const LOOKAHEAD_PCT: float = 0.18
const LOOKAHEAD_MAX_DIST: float = 3.0
# Lower = snappier camera; higher = more drag. 0.12 is "noticeable but
# not floaty" at 60Hz.
const LOOKAHEAD_SMOOTH: float = 0.12
var _lookahead_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	# Fallback: look up the local player via PlayersContainer once the
	# scene tree is ready. Phase 2B made the player a runtime-spawned
	# child rather than a baked node, so the @export NodePath in the
	# scene file no longer points anywhere — we resolve it here instead.
	if _target == null:
		_target = _resolve_local_player()
	_init_orbit_from_offset()
	_default_pitch_rad = _pitch_rad
	if _target != null:
		_snap_to_target()
	else:
		look_at(Vector3.ZERO, Vector3.UP)


func _resolve_local_player() -> Node3D:
	# PlayersContainer is a sibling under the level shell root; reach
	# up via the parent rather than hardcoding a path so this still
	# works if the camera ever gets reparented.
	var root: Node = get_parent()
	if root == null:
		return null
	var container: Node = root.get_node_or_null(^"PlayersContainer")
	if container == null:
		return null
	# get_local_player() falls back to "any spawned player" when the
	# local id can't be resolved, so this won't crash on edge cases.
	if container.has_method(&"get_local_player"):
		return container.get_local_player() as Node3D
	return null


## Snap pitch back to the initial (@export-derived) value. Called by the
## V-key handler when the player wants to undo a tilt before any other
## view transition.
func reset_pitch() -> void:
	_pitch_rad = _default_pitch_rad


## True when the live pitch is within PITCH_DEFAULT_EPSILON of the initial
## value. The V-key handler uses this to decide between "reset pitch" and
## "switch to FPS."
func is_at_default_pitch() -> bool:
	return absf(_pitch_rad - _default_pitch_rad) < PITCH_DEFAULT_EPSILON


# Decompose the @export offset into orbit polar coords so runtime pitch
# adjustments preserve distance + bearing. Bearing 0 = camera due south
# of target (+Z); PI/4 = SE; PI/2 = east (+X); etc.
func _init_orbit_from_offset() -> void:
	_distance = offset.length()
	if _distance < 0.0001:
		_distance = 1.0
		return
	var horiz := Vector2(offset.x, offset.z).length()
	_pitch_rad = clampf(atan2(horiz, offset.y), PITCH_MIN, PITCH_MAX)
	_bearing_rad = atan2(offset.x, offset.z) if horiz > 0.0001 else 0.0


func _input(event: InputEvent) -> void:
	if not enable_pitch_drag or not current:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mw_held = mb.pressed
		return
	if _mw_held and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_pitch_rad = clampf(_pitch_rad + mm.relative.y * pitch_drag_sensitivity, PITCH_MIN, PITCH_MAX)


func _process(delta: float) -> void:
	if _target == null:
		return
	_update_lookahead(delta)
	_snap_to_target()


func _snap_to_target() -> void:
	var sin_p := sin(_pitch_rad)
	var cos_p := cos(_pitch_rad)
	var dir_horiz := Vector3(sin(_bearing_rad), 0.0, cos(_bearing_rad))
	var ofs := Vector3(0.0, _distance * cos_p, 0.0) + dir_horiz * (_distance * sin_p)
	# Translational shake — adds a random offset to the camera's world
	# position each frame while _shake_intensity > 0. look_at keeps the
	# target centered, so the world appears to jolt in screen space
	# without the view rotating. Stronger hits decay slower; see shake().
	if _shake_intensity > 0.0:
		ofs += Vector3(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity),
		)
	# Cursor look-ahead — blend the camera's focus point toward the
	# player's cursor by LOOKAHEAD_PCT. _lookahead_offset is smoothed
	# via lerp so fast cursor flicks don't whip the view; the camera
	# trails the cursor by a few frames of inertia.
	var focal := _target.global_position + _lookahead_offset
	global_position = focal + ofs
	# Up hint = horizontal direction *away* from the camera. Same look_at
	# orientation as Vector3.UP at non-zero pitch (both vectors lie in the
	# forward+true-up plane), but stays well-defined at pitch = 0 where
	# Vector3.UP would be parallel to forward and degenerate the basis.
	look_at(focal, -dir_horiz)


# Update the smoothed look-ahead offset toward the player's cursor.
# Called per-frame from _process. Reads cursor_world_position from the
# target if available (PrototypePlayer exposes it); other targets just
# get zero look-ahead. Y is forced flat so the camera doesn't tilt
# vertically when the cursor hits a wall at a different height.
func _update_lookahead(delta: float) -> void:
	if _target == null or not _target.has_method(&"cursor_world_position"):
		_lookahead_offset = _lookahead_offset.lerp(Vector3.ZERO, LOOKAHEAD_SMOOTH)
		return
	var cursor_pos: Vector3 = _target.call(&"cursor_world_position")
	var target_pos: Vector3 = _target.global_position
	var raw_offset: Vector3 = (cursor_pos - target_pos) * LOOKAHEAD_PCT
	raw_offset.y = 0.0
	if raw_offset.length() > LOOKAHEAD_MAX_DIST:
		raw_offset = raw_offset.normalized() * LOOKAHEAD_MAX_DIST
	# Frame-rate-independent smoothing. The smoothing constant
	# represents "how far toward the target per 1/60s", scaled by
	# delta for variable frame timing.
	var t: float = clampf(LOOKAHEAD_SMOOTH * delta * 60.0, 0.0, 1.0)
	_lookahead_offset = _lookahead_offset.lerp(raw_offset, t)


## Trigger a brief camera shake. `intensity` is the peak random offset
## (in world units) — 0.05 is subtle, 0.2 is heavy. `duration` is the
## decay window; the shake eases out to zero over that time. Stronger
## shake wins over an in-flight weaker one. Per-camera so MP-safe.
func shake(intensity: float, duration: float) -> void:
	if intensity <= 0.0 or duration <= 0.0:
		return
	if intensity > _shake_intensity:
		_shake_intensity = intensity
	var tween := create_tween()
	tween.tween_property(self, "_shake_intensity", 0.0, duration) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
