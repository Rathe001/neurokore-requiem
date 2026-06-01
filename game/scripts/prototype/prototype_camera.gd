extends Camera3D
class_name PrototypeCamera

## Fixed-bearing follow camera. The @export `offset` defines the default
## camera position relative to the target — its magnitude becomes the orbit
## distance, its horizontal direction becomes the bearing, and the angle from
## vertical becomes the default pitch. Holding the middle mouse button and
## dragging the mouse vertically rotates the pitch between top-down and steep
## isometric, preserving distance + bearing.

@export var target_path: NodePath
## Camera offset from the focal point. Magnitude becomes orbit distance,
## direction becomes pitch + bearing.
##
## Default magnitude (~105m) is tuned for fake-ortho perspective:
## with FOV=12° in the scene's Camera3D properties, distance 105m
## gives a vertical view extent of 2 * 105 * tan(6°) ≈ 22m — the
## same world extent as the legacy ortho size=22 setup. F8 toggles
## between perspective and orthogonal projection at runtime; ortho
## ignores distance entirely (parallel projection) so the same offset
## works visually in either mode.
##
## To make perspective convergence even less perceptible (closer to
## true ortho), halve FOV and double `offset` magnitude proportionally
## — view extent stays the same, foreshortening shrinks. Watch the
## `far` clip and any SDFGI / shadow distance settings if you push
## past ~150m.
@export var offset: Vector3 = Vector3(20.08, 70.30, 20.08)
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
var _default_bearing_rad: float = 0.0
var _distance: float = 1.0
var _default_distance: float = 1.0
var _mw_held: bool = false

# ── Debug inspect mode ────────────────────────────────────────────────────
# Toggled with F9. While active, mouse wheel scrolls zoom and middle-
# mouse HORIZONTAL drag orbits the bearing around the player; the
# existing middle-mouse vertical drag continues to drive pitch. Toggling
# OFF snaps every orbit value back to its @export default. Gated rather
# than always-on so the fixed-iso gameplay feel (no zoom, fixed bearing,
# see feedback_no_camera_lerp) stays intact for normal play.
var _inspect_mode: bool = false
const _INSPECT_DISTANCE_MIN: float = 2.0
const _INSPECT_DISTANCE_MAX: float = 120.0
const _INSPECT_PERSP_ZOOM_STEP: float = 0.85     # multiplier per notch (wheel-up zooms in)
const _BEARING_DRAG_SENSITIVITY: float = 0.006   # rad per pixel of horizontal mouse motion

# Orthogonal-zoom dials. The level camera ships projection=1 (ortho)
# so reducing _distance changes its position without changing rendered
# object size — every object stays the same screen-size at any distance.
# In ortho mode the lens dial is `size` (the world-space half-height of
# the view frustum). Wheel steps scale multiplicatively so the rate
# feels smooth at both ends of the range: at size=22 (default) a notch
# trims ~3 world units; at size=4 (zoomed in) the same notch trims ~0.5.
const _INSPECT_ORTHO_SIZE_MIN: float = 2.5
const _INSPECT_ORTHO_SIZE_MAX: float = 60.0
const _INSPECT_ORTHO_ZOOM_STEP: float = 0.85     # multiplier per notch (wheel-up zooms in)
var _default_size: float = 22.0

# F9 detection. _input on a Camera3D should fire for keyboard events,
# but it's been unreliable in the field — Steam overlay, focus loss,
# IME state, anything that consumes the event before it propagates
# through the viewport can swallow the keypress. Belt-and-braces:
# _input handles the normal case, _process polls Input.is_physical_key_pressed
# as a fallback, and a CanvasLayer label shows the mode visibly so
# the user knows whether the toggle actually engaged.
var _f9_was_pressed_last_frame: bool = false
var _inspect_label: Label = null
# Bright sphere rendered at the current muzzle position while inspect +
# tune mode are both on. Confirms visually that the muzzle override is
# actually flowing through to the world — if the marker moves when you
# press 5/6/7/8/9/0, the wiring works; if it doesn't, the override
# isn't reaching wherever you're trying to use it.
var _muzzle_marker: MeshInstance3D = null

# ── Grip tuner (T inside inspect mode) ────────────────────────────────────
# Keyboard live-tune for the equipped weapon's WeaponAttachment grip
# offsets. Each bump mutates WeaponAttachment._GRIP and re-applies to
# the live model so the result shows immediately. P dumps the current
# entry to the console as a ready-to-paste dict line, Backspace resets.
# Gated on inspect mode + tune mode so normal gameplay isn't affected.
var _tune_mode: bool = false
const _TUNE_ROT_STEP: float = 15.0    # degrees per keypress
const _TUNE_POS_STEP: float = 0.05    # world units per keypress
const _TUNE_SCALE_UP: float = 1.1
const _TUNE_SCALE_DOWN: float = 0.9
# Y-offset applied to the focal point so the camera centres on the
# player's chest rather than the feet. Used in both regular gameplay
# (better visual centre-of-mass — character reads as upper-body-anchored
# rather than ground-anchored) and inspect mode (zoomed weapon-attach
# tuning frames the hands). ~1.2m is mid-chest height on the X Bot rig.
const _FOCAL_CHEST_OFFSET: float = 1.2

# ── Label3D fixed_size compensation ───────────────────────────────────────
# Godot 4's Label3D.fixed_size = true uses a projection-dependent
# compensation that lands ~5× too large under our narrow-FOV (18°)
# perspective camera vs the legacy ortho size=22 calibration. Every
# label setup site (item pickup names, credit drops, affliction glyphs)
# multiplies its authored pixel_size by `label_fixed_size_scale()` so
# labels keep the same apparent screen size whether the active camera
# is perspective or ortho. F8 projection toggling won't retroactively
# resize already-spawned labels — newly-spawned ones pick up the
# correct factor and old ones look mis-sized until the pool cycles.
# Re-calibrated when FOV dropped from 18° → 12°. Godot's fixed_size
# compensation overshoots in proportion to how narrow the FOV gets,
# roughly scaling with tan(FOV/2): tan(6°) / tan(9°) ≈ 0.66, so the
# old 0.20 factor became 0.13 at the new FOV.
const PERSPECTIVE_LABEL_FIXED_SCALE: float = 0.13


## Returns the multiplier that should be applied to authored `pixel_size`
## values on Label3D nodes with `fixed_size = true`, based on the active
## camera's projection. Falls back to 1.0 when no camera is available
## yet (e.g. setup during scene preload). Static so call sites don't
## need a PrototypeCamera reference — they just call
## `PrototypeCamera.label_fixed_size_scale()`.
static func label_fixed_size_scale() -> float:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return 1.0
	var root_node: Window = tree.root
	if root_node == null:
		return 1.0
	var vp: Viewport = root_node.get_viewport()
	if vp == null:
		return 1.0
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return 1.0
	return PERSPECTIVE_LABEL_FIXED_SCALE if cam.projection == PROJECTION_PERSPECTIVE else 1.0
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
	_default_bearing_rad = _bearing_rad
	_default_distance = _distance
	_default_size = size
	_build_audio_listener()
	_build_inspect_label()
	_build_muzzle_marker()
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
	# SFX autoload looks up the active listener via this group so it can
	# anchor "play at listener" sources to its position each frame —
	# without the follow, source and listener drift one frame apart and
	# player sounds pan opposite to player movement.
	_audio_listener.add_to_group(&"audio_listener")
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
	if not current:
		return
	# F9 toggles the debug inspect overlay regardless of any other state —
	# placed before the enable_pitch_drag gate so it can't get locked off.
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.physical_keycode == KEY_F9:
			_set_inspect_mode(not _inspect_mode)
			# Latch so the same-frame _process poll doesn't double-toggle.
			_f9_was_pressed_last_frame = true
			print("[Camera] F9 detected via INPUT event")
			return
		if ke.pressed and not ke.echo and ke.physical_keycode == KEY_F8:
			_toggle_projection()
			return
		# Grip-tuner key handling — only active inside inspect + tune
		# mode. Returns at the end so tune presses don't fall through
		# to the gameplay input layer.
		if _inspect_mode and ke.pressed and not ke.echo:
			if ke.physical_keycode == KEY_T:
				_tune_mode = not _tune_mode
				print("[Camera] grip tune mode: ", "ON" if _tune_mode else "OFF")
				return
			if _tune_mode and _handle_tune_key(ke.physical_keycode):
				return
	if not enable_pitch_drag:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mw_held = mb.pressed
			return
		# Mouse-wheel zoom is gated to inspect mode so the gameplay
		# camera stays at fixed framing (the project's design call;
		# see feedback_no_camera_lerp). In orthogonal projection
		# (the level camera) zoom = adjust `size`; in perspective
		# (anything bolted on later) zoom = adjust `_distance`.
		if _inspect_mode and mb.pressed:
			var is_ortho := projection == PROJECTION_ORTHOGONAL
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				if is_ortho:
					size = clampf(size * _INSPECT_ORTHO_ZOOM_STEP, _INSPECT_ORTHO_SIZE_MIN, _INSPECT_ORTHO_SIZE_MAX)
				else:
					_distance = clampf(_distance * _INSPECT_PERSP_ZOOM_STEP, _INSPECT_DISTANCE_MIN, _INSPECT_DISTANCE_MAX)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if is_ortho:
					size = clampf(size / _INSPECT_ORTHO_ZOOM_STEP, _INSPECT_ORTHO_SIZE_MIN, _INSPECT_ORTHO_SIZE_MAX)
				else:
					_distance = clampf(_distance / _INSPECT_PERSP_ZOOM_STEP, _INSPECT_DISTANCE_MIN, _INSPECT_DISTANCE_MAX)
		return
	if _mw_held and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_pitch_rad = clampf(_pitch_rad + mm.relative.y * pitch_drag_sensitivity, PITCH_MIN, PITCH_MAX)
		# Horizontal middle-drag orbits the bearing — also gated to
		# inspect mode so the fixed-bearing gameplay camera never
		# drifts off-axis from a stray middle-mouse pan.
		if _inspect_mode and absf(mm.relative.x) > 0.0:
			_bearing_rad = fposmod(_bearing_rad - mm.relative.x * _BEARING_DRAG_SENSITIVITY, TAU)


# Enter / leave debug inspect mode. Leaving snaps every orbit parameter
# back to its initial @export-derived default so the iso framing is
# restored exactly — no lerp, since the gameplay camera contract is
# snap-only.
# Looks up the local player's right-hand skeleton + the currently
# equipped weapon's base_id. Returns [null, &""] when the player isn't
# spawned yet or no weapon is equipped — the tuner bails on either.
func _resolve_tune_target() -> Array:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return [null, &""]
	var visual := player.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return [null, &""]
	var skel := PrototypePlayer._find_skeleton_recursive(visual)
	if skel == null:
		return [null, &""]
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	if weapon == null:
		return [skel, &""]
	return [skel, weapon.weapon_base_id]


# Handles a single tune-mode keypress. Returns true if the key was a
# recognised tune control (so _input can stop dispatching it), false if
# the key was unrelated and should keep propagating.
func _handle_tune_key(keycode: int) -> bool:
	var target := _resolve_tune_target()
	var skel: Skeleton3D = target[0]
	var base_id: StringName = target[1]
	if skel == null or base_id == &"":
		return false
	# Threaded through every bump so the tuner writes to _GRIP_FEMALE when
	# tuning on a female avatar, _GRIP_MALE otherwise. WeaponAttachment
	# could resolve this from the skeleton itself, but the tuner already
	# knows which player it's operating on — cheaper + clearer to pass it.
	var gender := _local_player_gender()
	match keycode:
		KEY_J: WeaponAttachment.bump_rotation(base_id, &"x", -_TUNE_ROT_STEP, gender)
		KEY_L: WeaponAttachment.bump_rotation(base_id, &"x",  _TUNE_ROT_STEP, gender)
		KEY_U: WeaponAttachment.bump_rotation(base_id, &"y", -_TUNE_ROT_STEP, gender)
		KEY_O: WeaponAttachment.bump_rotation(base_id, &"y",  _TUNE_ROT_STEP, gender)
		KEY_H: WeaponAttachment.bump_rotation(base_id, &"z", -_TUNE_ROT_STEP, gender)
		KEY_K: WeaponAttachment.bump_rotation(base_id, &"z",  _TUNE_ROT_STEP, gender)
		KEY_LEFT:    WeaponAttachment.bump_position(base_id, &"x", -_TUNE_POS_STEP, gender)
		KEY_RIGHT:   WeaponAttachment.bump_position(base_id, &"x",  _TUNE_POS_STEP, gender)
		KEY_DOWN:    WeaponAttachment.bump_position(base_id, &"y", -_TUNE_POS_STEP, gender)
		KEY_UP:      WeaponAttachment.bump_position(base_id, &"y",  _TUNE_POS_STEP, gender)
		KEY_COMMA:  WeaponAttachment.bump_position(base_id, &"z", -_TUNE_POS_STEP, gender)
		KEY_PERIOD: WeaponAttachment.bump_position(base_id, &"z",  _TUNE_POS_STEP, gender)
		KEY_MINUS, KEY_KP_SUBTRACT: WeaponAttachment.bump_scale(base_id, _TUNE_SCALE_DOWN, gender)
		KEY_EQUAL, KEY_KP_ADD:      WeaponAttachment.bump_scale(base_id, _TUNE_SCALE_UP, gender)
		# Per-weapon muzzle override. Top-row 5/6/7/8/9/0 — sit just
		# right of the skill hotbar keys so they're easy to reach
		# without remapping. Useful when the AABB-corner heuristic
		# picks the wrong spot (laser pistol, smg, taser).
		KEY_5: WeaponAttachment.bump_muzzle(base_id, &"x", -_TUNE_POS_STEP, gender)
		KEY_6: WeaponAttachment.bump_muzzle(base_id, &"x",  _TUNE_POS_STEP, gender)
		KEY_7: WeaponAttachment.bump_muzzle(base_id, &"y", -_TUNE_POS_STEP, gender)
		KEY_8: WeaponAttachment.bump_muzzle(base_id, &"y",  _TUNE_POS_STEP, gender)
		KEY_9: WeaponAttachment.bump_muzzle(base_id, &"z", -_TUNE_POS_STEP, gender)
		KEY_0: WeaponAttachment.bump_muzzle(base_id, &"z",  _TUNE_POS_STEP, gender)
		KEY_P:
			WeaponAttachment.dump_grip_to_console(base_id, gender)
			return true
		KEY_BACKSPACE: WeaponAttachment.reset_grip(base_id, gender)
		_: return false
	# Recognised bump — re-apply to the live model so the change shows
	# without re-equipping. reapply_grip reads the gender meta off the
	# skeleton itself so it auto-picks the same table the bump wrote to.
	WeaponAttachment.reapply_grip(skel, base_id)
	return true


# Resolves the local (controlling) player's gender so the tuner writes
# to the matching grip table. PlayerState owns the canonical SP/host
# value; for clients, PlayerState.gender reflects what they picked at
# character creation, which is what we want here (we're tuning their
# avatar). Defaults to &"male" if PlayerState isn't reachable.
func _local_player_gender() -> StringName:
	if Engine.has_singleton("PlayerState") or PlayerState != null:
		return PlayerState.gender
	return &"male"


# F8 flips projection mode at runtime so you can A/B perspective vs
# ortho on the live scene. Visual framing stays roughly identical
# because (a) the @export offset puts the camera ~70m back, which under
# FOV=18° perspective produces the same 22m view extent as the legacy
# size=22 ortho setup, and (b) ortho ignores distance entirely. Exits
# inspect mode on swap so the user sees the unmodified framing of the
# newly-active projection.
func _toggle_projection() -> void:
	if _inspect_mode:
		_set_inspect_mode(false)
	if projection == PROJECTION_PERSPECTIVE:
		projection = PROJECTION_ORTHOGONAL
		print("[Camera] projection: ORTHOGONAL (size=%.1f, F8 to swap back)" % size)
	else:
		projection = PROJECTION_PERSPECTIVE
		print("[Camera] projection: PERSPECTIVE (fov=%.1f°, F8 to swap back)" % fov)


func _set_inspect_mode(active: bool) -> void:
	_inspect_mode = active
	if not active:
		_pitch_rad = _default_pitch_rad
		_bearing_rad = _default_bearing_rad
		_distance = _default_distance
		size = _default_size
	# One-shot console line so the debug toggle is discoverable from logs.
	print("[Camera] inspect mode: ", "ON (wheel=zoom, MMB-drag=orbit)" if active else "OFF (restored)")
	_update_inspect_label()


func _process(delta: float) -> void:
	_tick_shake(delta)
	_tick_push(delta)
	_poll_f9_fallback()
	_update_inspect_label()
	_update_muzzle_marker()
	if _target == null:
		return
	_snap_to_target()


# Per-frame poll for F9. Fires if the key is down THIS frame but not
# last — edge-detected like a button press. Backstop for the _input
# path; if _input picked it up first it'll have already toggled so
# the polled path sees the new state and rests.
func _poll_f9_fallback() -> void:
	var down := Input.is_physical_key_pressed(KEY_F9)
	if down and not _f9_was_pressed_last_frame:
		_set_inspect_mode(not _inspect_mode)
		print("[Camera] F9 detected via POLL (fallback path)")
	_f9_was_pressed_last_frame = down


# Small top-left HUD label that surfaces inspect mode + the live values
# we're tuning. Visible feedback is the only way to know whether F9
# actually engaged without reading the console.
func _build_inspect_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_inspect_label = Label.new()
	# Top-center: clear of the top-left controls hint and clear of the
	# character in inspect mode. Anchored to top so it doesn't drift on
	# resize.
	_inspect_label.anchor_left = 0.5
	_inspect_label.anchor_right = 0.5
	_inspect_label.position = Vector2(-560, 8)
	_inspect_label.modulate = Color(0.6, 1.0, 0.6, 1.0)
	_inspect_label.add_theme_font_size_override(&"font_size", 12)
	_inspect_label.visible = false
	layer.add_child(_inspect_label)


# Magenta unshaded sphere parented under the camera node so it can't get
# orphaned on level reload. Visible only when inspect + tune mode are
# both active, positioned per-frame to match the live muzzle.
func _build_muzzle_marker() -> void:
	var inst := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.04
	sph.height = 0.08
	sph.radial_segments = 12
	sph.rings = 6
	inst.mesh = sph
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.top_level = true
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.2, 1.0, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.no_depth_test = true                              # always on top
	inst.material_override = mat
	inst.visible = false
	add_child(inst)
	_muzzle_marker = inst


func _update_muzzle_marker() -> void:
	if _muzzle_marker == null:
		return
	var show: bool = _inspect_mode and _tune_mode
	_muzzle_marker.visible = show
	if not show:
		return
	var t := _resolve_tune_target()
	var skel: Skeleton3D = t[0]
	var base_id: StringName = t[1]
	if skel == null or base_id == &"":
		_muzzle_marker.visible = false
		return
	# Use the player's facing direction as the aim seed — the AABB-
	# heuristic branch of get_muzzle_position needs an aim direction.
	# The override branch ignores aim, so this only matters for weapons
	# without a tuned muzzle field.
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var aim := -player.global_transform.basis.z if player != null else -global_transform.basis.z
	var muzzle := WeaponAttachment.get_muzzle_position(skel, aim)
	if muzzle == Vector3.ZERO:
		_muzzle_marker.visible = false
		return
	_muzzle_marker.global_position = muzzle


func _update_inspect_label() -> void:
	if _inspect_label == null:
		return
	_inspect_label.visible = _inspect_mode
	if _inspect_mode:
		var is_ortho := projection == PROJECTION_ORTHOGONAL
		var mode_label: String = "ORTHO" if is_ortho else "PERSP"
		var zoom_field: String = ("size=%.1f" % size) if is_ortho else ("dist=%.1f" % _distance)
		var header := "[INSPECT %s] %s  pitch=%.0f°  bearing=%.0f°  (wheel=zoom, MMB-drag=orbit, F8=swap, F9=exit, T=tune)" % [
			mode_label, zoom_field, rad_to_deg(_pitch_rad), rad_to_deg(_bearing_rad),
		]
		if _tune_mode:
			var t := _resolve_tune_target()
			var base_id: StringName = t[1]
			if base_id != &"":
				var grip := WeaponAttachment.get_grip(base_id, _local_player_gender())
				var p: Vector3 = grip.get("pos", Vector3.ZERO)
				var r: Vector3 = grip.get("rot", Vector3.ZERO)
				var s: float = float(grip.get("scale_mult", 1.0))
				var mz: Vector3 = grip.get("muzzle", Vector3.ZERO)
				header += "\n[TUNE %s]  pos=(%.2f, %.2f, %.2f)  rot=(%.0f, %.0f, %.0f)  scale=%.2f  muzzle=(%.2f, %.2f, %.2f)" % [
					String(base_id), p.x, p.y, p.z, r.x, r.y, r.z, s, mz.x, mz.y, mz.z,
				]
				header += "\n  rot: J/L=±X  U/O=±Y  H/K=±Z   pos: ←→=±X  ↑↓=±Y  ,/.=±Z   scale: -/=   muzzle: 5/6=±X  7/8=±Y  9/0=±Z   P=dump  Backspace=reset"
			else:
				header += "\n[TUNE] no weapon equipped"
		_inspect_label.text = header


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
	# Focal centres on the chest, not the feet — better visual anchor
	# (the character's mass reads as upper-body) and lines up with where
	# weapons / aim cues actually live. Applied unconditionally so the
	# game camera and inspect-mode framing both centre the same point.
	var focal := _target.global_position
	focal.y += _FOCAL_CHEST_OFFSET
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
