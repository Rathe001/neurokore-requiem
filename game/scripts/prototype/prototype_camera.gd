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
const PITCH_MIN := 0.0
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

func _ready() -> void:
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	_init_orbit_from_offset()
	_default_pitch_rad = _pitch_rad
	if _target != null:
		_snap_to_target()
	else:
		look_at(Vector3.ZERO, Vector3.UP)


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


func _process(_delta: float) -> void:
	if _target == null:
		return
	_snap_to_target()


func _snap_to_target() -> void:
	var sin_p := sin(_pitch_rad)
	var cos_p := cos(_pitch_rad)
	var dir_horiz := Vector3(sin(_bearing_rad), 0.0, cos(_bearing_rad))
	var ofs := Vector3(0.0, _distance * cos_p, 0.0) + dir_horiz * (_distance * sin_p)
	global_position = _target.global_position + ofs
	# Up hint = horizontal direction *away* from the camera. Same look_at
	# orientation as Vector3.UP at non-zero pitch (both vectors lie in the
	# forward+true-up plane), but stays well-defined at pitch = 0 where
	# Vector3.UP would be parallel to forward and degenerate the basis.
	look_at(_target.global_position, -dir_horiz)
