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
# ── Camera shake ──────────────────────────────────────────────────────────
# Decayed manually in _process (was a Tween — but tweens captured the
# property's *current* value at activation, so rapid-fire calls layered
# tweens whose new starts were the OLD tween's decayed value. Result:
# SMG bursts collapsed instead of sustaining. Manual envelope below
# fixes that — each shake() call resets the timer to whichever path
# is *longer* and intensity to whichever is *louder*, so a tiny SMG
# burst on top of a heavy grenade shake doesn't shorten the grenade.
#
# Envelope shape: SHAKE_HOLD_FRAC of the duration is held at full peak,
# the remainder decays with quadratic ease-out. The hold phase is what
# makes burst fire feel sustained — each new shake() during a burst
# resets the timer, so the hold keeps refreshing.
const SHAKE_HOLD_FRAC: float = 0.25

var _shake_intensity: float = 0.0  # current applied magnitude (random ±this per frame)
var _shake_initial: float = 0.0    # peak captured at last shake() call
var _shake_remaining: float = 0.0
var _shake_total: float = 0.0

# ── Energy-weapon push ────────────────────────────────────────────────────
# Directional camera offset that drifts AWAY from aim on fire, then
# springs back to neutral. Distinct from shake() — that's chaotic random
# jitter for impacts/recoil; push() is smooth pressure that reads as
# "energy is pushing me back," with no per-frame randomness. Modeled as
# velocity + position with simple damping/recovery so per-tick channel
# beams (Energy Accelerator) accumulate smoothly without snapping.
const PUSH_DAMPING: float = 10.0   # how fast velocity bleeds off (1/sec)
const PUSH_RECOVERY: float = 7.0   # how fast position springs back to 0 (1/sec)
const PUSH_MAX: float = 1.4        # clamp ceiling so accelerator stream can't drift forever
var _push_offset: Vector3 = Vector3.ZERO
var _push_velocity: Vector3 = Vector3.ZERO

# Audio listener — top-level so its transform is independent of the
# camera's own (shake / push must not affect audio panning). Position
# tracks the player each frame; orientation is locked once at _ready
# to match the camera's horizontal bearing, so panning is permanently
# screen-relative no matter what the player character is doing. This is
# the FPS-feel anchor: what you see is what you hear.
var _audio_listener: AudioListener3D


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
	_build_audio_listener()
	if _target != null:
		_snap_to_target()
	else:
		look_at(Vector3.ZERO, Vector3.UP)


# Create the AudioListener3D as a top-level child of this camera, with
# orientation derived from the (fixed) camera bearing so screen-right
# always corresponds to audio-right. Position is updated per-frame
# from _snap_to_target. current=true overrides Godot's default-to-
# active-camera listener pick.
func _build_audio_listener() -> void:
	_audio_listener = AudioListener3D.new()
	_audio_listener.top_level = true
	add_child(_audio_listener)
	# Listener forward = camera's horizontal forward (from camera toward
	# target, flattened). dir_horiz_to_camera = sin(b), 0, cos(b) — so
	# camera-to-target horizontal is its negation. Up stays world-up.
	var fwd := Vector3(-sin(_bearing_rad), 0.0, -cos(_bearing_rad))
	# look_at_from_position uses the +Z-forward convention; pass the
	# listener's own position plus the forward as the look-at target.
	# Calling immediately so the rotation is set before any sound plays.
	if _target != null:
		_audio_listener.global_position = _target.global_position
	else:
		_audio_listener.global_position = Vector3.ZERO
	_audio_listener.look_at(_audio_listener.global_position + fwd, Vector3.UP)
	_audio_listener.current = true


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
	_tick_shake(delta)
	_tick_push(delta)
	if _target == null:
		return
	_snap_to_target()


# Integrate the push spring. Position advances by velocity then springs
# back toward zero; velocity damps each frame. Clamps offset magnitude
# so a sustained channel-beam can't drift the camera off the player.
func _tick_push(delta: float) -> void:
	if _push_offset == Vector3.ZERO and _push_velocity == Vector3.ZERO:
		return
	_push_offset += _push_velocity * delta
	if _push_offset.length() > PUSH_MAX:
		_push_offset = _push_offset.normalized() * PUSH_MAX
	var pos_t: float = clampf(PUSH_RECOVERY * delta, 0.0, 1.0)
	var vel_t: float = clampf(PUSH_DAMPING * delta, 0.0, 1.0)
	_push_offset = _push_offset.lerp(Vector3.ZERO, pos_t)
	_push_velocity = _push_velocity.lerp(Vector3.ZERO, vel_t)
	# Snap to zero past a tiny epsilon so the spring doesn't oscillate
	# forever at imperceptible magnitudes.
	if _push_offset.length() < 0.001 and _push_velocity.length() < 0.001:
		_push_offset = Vector3.ZERO
		_push_velocity = Vector3.ZERO


# Tick the shake envelope. Hold at peak for SHAKE_HOLD_FRAC of total,
# then quadratic-ease-out to zero. Returns early when no shake is in
# flight so the common path is one branch.
func _tick_shake(delta: float) -> void:
	if _shake_remaining <= 0.0:
		if _shake_intensity > 0.0:
			_shake_intensity = 0.0
		return
	_shake_remaining -= delta
	if _shake_remaining <= 0.0:
		_shake_intensity = 0.0
		_shake_initial = 0.0
		_shake_total = 0.0
		return
	var elapsed: float = _shake_total - _shake_remaining
	var hold_time: float = _shake_total * SHAKE_HOLD_FRAC
	if elapsed < hold_time:
		_shake_intensity = _shake_initial
		return
	var decay_total: float = _shake_total - hold_time
	if decay_total <= 0.0:
		_shake_intensity = 0.0
		return
	var ratio: float = _shake_remaining / decay_total
	_shake_intensity = _shake_initial * ratio * ratio


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
	# Energy-weapon push — directional offset (computed in _tick_push)
	# that drifts the camera opposite aim then springs back. Distinct
	# from shake() above: smooth, directional, "pressure" rather than
	# "impact." Adding to `ofs` (camera position) instead of the focal
	# means look_at still tracks the player; the world appears to lurch
	# toward the aim direction as the camera kicks back from it.
	ofs += _push_offset
	var focal := _target.global_position
	global_position = focal + ofs
	# Up hint = horizontal direction *away* from the camera. Same look_at
	# orientation as Vector3.UP at non-zero pitch (both vectors lie in the
	# forward+true-up plane), but stays well-defined at pitch = 0 where
	# Vector3.UP would be parallel to forward and degenerate the basis.
	look_at(focal, -dir_horiz)
	# Listener tracks the player position only — orientation stays locked
	# to the bearing-aligned basis set in _build_audio_listener so panning
	# is purely screen-relative and never wobbles with camera shake/push.
	if _audio_listener != null:
		_audio_listener.global_position = focal




## Apply a directional push impulse to the camera — used by energy
## weapons to fake "muzzle pressure" without the random jitter of
## shake(). `aim_direction` is the world-space firing direction; the
## camera kicks OPPOSITE (i.e., the player feels pushed back). Y is
## flattened so the camera stays in the ground plane. `impulse` is
## velocity in world units / sec; the spring tick converts that into
## a brief offset that springs back to zero.
##
## Static entry — call sites don't need a PrototypeCamera reference.
static func push_at(source: Node, aim_direction: Vector3, impulse: float) -> void:
	if source == null or impulse <= 0.0:
		return
	var vp := source.get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d() as PrototypeCamera
	if cam == null:
		return
	var dir := aim_direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	# Push goes OPPOSITE the aim — player gets shoved back by the beam.
	cam._push_velocity -= dir * impulse


## Impact-shake helper — applies shake() to the LOCAL camera, scaled
## by distance from the blast. Use this for world-positioned events
## (explosions, ground slams) so a far-away RPG hit produces a smaller
## jolt than one detonating at the player's feet. `source` is any node
## in the tree; we walk up to its viewport to find the active camera.
## Linear falloff out to `falloff_radius`; past that, no shake. Static
## entry point so call sites don't need a PrototypeCamera reference.
##
## Distance is measured from the camera's FOCAL point (= player), not
## the camera's own global position. The iso camera sits ~14u away
## from the player at all times, so camera-position-distance would
## report ~14 for a blast at the player's feet — exactly the falloff
## edge — and feel broken. Focal-distance is the proximity the player
## actually perceives.
static func shake_at(source: Node, world_pos: Vector3, peak: float, duration: float, falloff_radius: float = 16.0) -> void:
	if source == null:
		return
	var vp := source.get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d() as PrototypeCamera
	if cam == null:
		return
	var dist: float = cam.focal_position().distance_to(world_pos)
	if dist >= falloff_radius:
		return
	var t: float = clampf(1.0 - dist / falloff_radius, 0.0, 1.0)
	cam.shake(peak * t, duration)


## Returns the world-space focal point of the camera (the spot the
## camera looks at). Used by proximity-based systems (impact shake)
## that need "near the player" semantics rather than "near the physical
## camera," since the iso camera always sits a fixed distance off the
## floor.
func focal_position() -> Vector3:
	if _target == null:
		return global_position
	return _target.global_position


## Trigger a brief camera shake. `intensity` is the peak random offset
## (in world units) — 0.05 is subtle, 1.0+ is heavy. `duration` is the
## envelope window: SHAKE_HOLD_FRAC at full peak, then quadratic decay.
## Per-camera so MP-safe (every player's iso camera shakes only on
## their own hits).
##
## Overlap semantics: peak intensity becomes max(currently-applied,
## requested) and remaining time becomes max(currently-remaining,
## requested duration). Using *currently-applied* (the live decayed
## value) means a small rapid-fire shake doesn't artificially boost a
## heavier in-flight one mid-decay; using *currently-remaining* means
## a small shake on top of a heavy one doesn't shorten the heavy one.
func shake(intensity: float, duration: float) -> void:
	if intensity <= 0.0 or duration <= 0.0:
		return
	var new_initial: float = maxf(_shake_intensity, intensity)
	var new_remaining: float = maxf(_shake_remaining, duration)
	_shake_initial = new_initial
	_shake_intensity = new_initial
	_shake_remaining = new_remaining
	_shake_total = new_remaining
