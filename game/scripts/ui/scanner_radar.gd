extends Control
class_name ScannerRadar

## Radar sweep overlay for the Scanner light type. Draws on top of the minimap:
## rotating sweep line, fading enemy blips, range rings. Sized and positioned
## by the parent Minimap via `map_rect`.

const SWEEP_SPEED := TAU * 0.4  # radians per second (~one rotation per 2.5s)
const BLIP_FADE_TIME := 2.5     # seconds a blip stays visible after sweep
const RING_COUNT := 3
const RING_SEGMENTS := 64
const MAX_SCANNER_RANGE := 20.0 # world units — detection radius for enemies
const TRAIL_STEPS := 30
const TRAIL_ARC := TAU * 0.25   # quarter-circle sweep trail

const BG_COLOR := Color(0.02, 0.06, 0.02, 0.45)
const RING_COLOR := Color(0.1, 0.35, 0.1, 0.4)
const SWEEP_COLOR := Color(0.15, 0.9, 0.25, 0.6)
const TRAIL_COLOR := Color(0.1, 0.7, 0.15, 0.15)
const BLIP_COLOR := Color(0.2, 1.0, 0.3, 1.0)
const BLIP_FLASH_COLOR := Color(0.7, 1.0, 0.8, 1.0)
const BLIP_FLASH_TIME := 0.3  # seconds the bright flash lasts
const BLIP_RADIUS_CORNER := 1.2
const BLIP_RADIUS_FULL := 1.8
const BLIP_RADIUS_THRESHOLD := 120.0  # map_radius above which fullscreen size is used

## Set by the parent Minimap to position and size the overlay.
var map_rect := Rect2(0.0, 0.0, 170.0, 170.0)
## The minimap camera's orthographic size — used to scale the radar circle
## proportionally within the map. The radar represents MAX_SCANNER_RANGE
## world units, which is a fraction of the full minimap view.
var camera_ortho_size: float = 30.0
## Master opacity multiplier (reduced in fullscreen so the radar doesn't overpower the game).
var opacity: float = 1.0

var _sweep_angle: float = 0.0
var _player: Node3D = null

## Each blip stores { position: Vector2, age: float, node: Node3D }.
var _blips: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_player(player: Node3D) -> void:
	_player = player

func _process(delta: float) -> void:
	if not visible:
		return
	var old_angle := _sweep_angle
	_sweep_angle = fmod(_sweep_angle + SWEEP_SPEED * delta, TAU)
	_update_blips(delta, old_angle, _sweep_angle)
	queue_redraw()

func _draw() -> void:
	var center := map_rect.get_center()
	var map_radius := map_rect.size.x * 0.5
	# The scanner covers a fixed world range, not the full minimap view.
	# Scale the radar circle to represent MAX_SCANNER_RANGE within the map.
	var scan_radius := map_radius * clampf(MAX_SCANNER_RANGE / maxf(camera_ortho_size, 0.01), 0.0, 1.0)
	var blip_r := BLIP_RADIUS_FULL if map_radius > BLIP_RADIUS_THRESHOLD else BLIP_RADIUS_CORNER
	var o := opacity

	# Semi-transparent green tint over the scanner area only.
	draw_circle(center, scan_radius, Color(BG_COLOR, BG_COLOR.a * o))

	# Range rings.
	for i in range(1, RING_COUNT + 1):
		var r := scan_radius * (float(i) / float(RING_COUNT))
		_draw_ring(center, r, Color(RING_COLOR, RING_COLOR.a * o))

	# Sweep trail (fading arc behind the sweep line).
	for i in TRAIL_STEPS:
		var t := float(i) / float(TRAIL_STEPS)
		var angle := _sweep_angle - TRAIL_ARC * t
		var alpha := TRAIL_COLOR.a * (1.0 - t) * o
		var col := Color(TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, alpha)
		var tip := center + Vector2(cos(angle), sin(angle)) * scan_radius
		draw_line(center, tip, col, 1.0)

	# Sweep line.
	var sweep_tip := center + Vector2(cos(_sweep_angle), sin(_sweep_angle)) * scan_radius
	draw_line(center, sweep_tip, Color(SWEEP_COLOR, SWEEP_COLOR.a * o), 1.5)

	# Blips — positions are normalized 0..1 within MAX_SCANNER_RANGE.
	for blip in _blips:
		var age: float = blip.age
		var alpha := clampf(1.0 - age / BLIP_FADE_TIME, 0.0, 1.0) * o
		# Bright flash when first revealed, fading to normal blip color.
		var flash_t := clampf(1.0 - age / BLIP_FLASH_TIME, 0.0, 1.0)
		var base_col := BLIP_FLASH_COLOR.lerp(BLIP_COLOR, 1.0 - flash_t)
		var col := Color(base_col.r, base_col.g, base_col.b, alpha)
		var pos: Vector2 = blip.position * scan_radius + center
		# Clamp inside the scanner circle.
		var from_center := pos - center
		if from_center.length() > scan_radius - blip_r:
			pos = center + from_center.normalized() * (scan_radius - blip_r)
		draw_circle(pos, blip_r, col)


func _draw_ring(center: Vector2, radius: float, color: Color, width: float = 1.0) -> void:
	var prev := center + Vector2(radius, 0.0)
	for i in range(1, RING_SEGMENTS + 1):
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		var next := center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(prev, next, color, width)
		prev = next

func _update_blips(delta: float, old_angle: float, new_angle: float) -> void:
	# Age existing blips and remove expired ones.
	var i := _blips.size() - 1
	while i >= 0:
		_blips[i].age += delta
		if _blips[i].age > BLIP_FADE_TIME:
			_blips.remove_at(i)
		i -= 1

	if _player == null or not is_instance_valid(_player):
		return

	# Query enemies within the fixed scanner range (not the camera zoom).
	var enemies := SpatialGrid.query_radius(_player.global_position, MAX_SCANNER_RANGE, &"enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var offset := enemy.global_position - _player.global_position
		# Convert world XZ offset to radar-space angle and distance.
		var angle := atan2(offset.z, offset.x)
		if angle < 0.0:
			angle += TAU
		# Check if this enemy was swept over this frame.
		if _angle_in_sweep(angle, old_angle, new_angle):
			var dist := Vector2(offset.x, offset.z).length()
			# Normalize to 0..1 within the fixed scanner range.
			var radar_t := clampf(dist / MAX_SCANNER_RANGE, 0.0, 1.0)
			var radar_pos := Vector2(cos(angle), sin(angle)) * radar_t
			# Replace existing blip for this enemy or add new one.
			var found := false
			for blip in _blips:
				if blip.get("node") == enemy:
					blip.position = radar_pos
					blip.age = 0.0
					found = true
					break
			if not found:
				_blips.append({ "position": radar_pos, "age": 0.0, "node": enemy })

func _angle_in_sweep(angle: float, old_a: float, new_a: float) -> bool:
	if new_a >= old_a:
		return angle >= old_a and angle <= new_a
	else:
		return angle >= old_a or angle <= new_a
