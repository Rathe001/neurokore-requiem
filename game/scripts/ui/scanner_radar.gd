extends Control
class_name ScannerRadar

## Radar sweep overlay for the Scanner light type. Draws on top of the minimap:
## rotating sweep line, fading enemy blips, range rings. Sized and positioned
## by the parent Minimap via `map_rect`.
##
## Blips are projected from world-space enemy positions onto the minimap using
## the minimap camera's basis vectors, so they are anchored to the actual map.

const SWEEP_SPEED := TAU * 0.4  # radians per second (~one rotation per 2.5s)
const BLIP_FADE_TIME := 2.5     # seconds a blip stays visible after sweep
const RING_COUNT := 3
const RING_SEGMENTS := 64
const MAX_SCANNER_RANGE := 12.0 # world units — matches common_scanner light_range
const TRAIL_STEPS := 30
const TRAIL_ARC := TAU * 0.25   # quarter-circle sweep trail

const RING_COLOR := Color(0.1, 0.35, 0.1, 0.4)
const SWEEP_COLOR := Color(0.15, 0.9, 0.25, 0.07)
const TRAIL_COLOR := Color(0.5, 1.0, 0.55, 0.05)
const BLIP_COLOR := Color(0.2, 1.0, 0.3, 1.0)
const BLIP_FLASH_COLOR := Color(0.7, 1.0, 0.8, 1.0)
const BLIP_FLASH_TIME := 0.3  # seconds the bright flash lasts
const BLIP_RADIUS_CORNER := 1.2
const BLIP_RADIUS_FULL := 1.8
const BLIP_RADIUS_THRESHOLD := 120.0  # map_radius above which fullscreen size is used

## Set by the parent Minimap to position and size the overlay.
var map_rect := Rect2(0.0, 0.0, 170.0, 170.0)
## The minimap camera's orthographic size — used to scale the scanner detection ring.
var camera_ortho_size: float = 30.0
## Reference to the minimap camera — used to project world positions onto the map.
var minimap_camera: Camera3D = null
## Master opacity multiplier (reduced in fullscreen so the radar doesn't overpower the game).
var opacity: float = 1.0

var _sweep_angle: float = 0.0
var _player: Node3D = null

## Each blip stores { node: Node3D, age: float, last_pos: Vector3 }.
## last_pos is kept so blips linger at the enemy's last known position after they die.
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
	# scan_radius must use the same px_per_world scale as _world_to_map so the
	# ring edge exactly matches where a max-range enemy blip would land.
	var px_per_world := map_rect.size.y / maxf(camera_ortho_size, 0.01)
	var scan_radius := minf(MAX_SCANNER_RANGE * px_per_world, map_radius)
	var blip_r := BLIP_RADIUS_FULL if map_radius > BLIP_RADIUS_THRESHOLD else BLIP_RADIUS_CORNER
	var o := opacity

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
		draw_line(center, tip, col, 1.8)

	# Sweep line.
	var sweep_tip := center + Vector2(cos(_sweep_angle), sin(_sweep_angle)) * scan_radius
	draw_line(center, sweep_tip, Color(SWEEP_COLOR, SWEEP_COLOR.a * o), 1.5)

	# Blips — projected from world positions onto the minimap.
	for blip in _blips:
		var age: float = blip.age
		var alpha := clampf(1.0 - age / BLIP_FADE_TIME, 0.0, 1.0) * o
		var flash_t := clampf(1.0 - age / BLIP_FLASH_TIME, 0.0, 1.0)
		var base_col := BLIP_FLASH_COLOR.lerp(BLIP_COLOR, 1.0 - flash_t)
		var col := Color(base_col.r, base_col.g, base_col.b, alpha)
		var world_pos: Vector3 = blip.last_pos
		if is_instance_valid(blip.node):
			world_pos = (blip.node as Node3D).global_position
		var pos := _world_to_map(world_pos)
		# Clamp inside the scanner detection circle (not the full map circle).
		var from_center := pos - center
		if from_center.length() > scan_radius - blip_r:
			pos = center + from_center.normalized() * (scan_radius - blip_r)
		draw_circle(pos, blip_r, col)


func _world_to_map(world_pos: Vector3) -> Vector2:
	if minimap_camera == null or not is_instance_valid(minimap_camera) or _player == null:
		return map_rect.get_center()
	var offset := world_pos - _player.global_position
	var right := minimap_camera.global_transform.basis.x
	var up_world := minimap_camera.global_transform.basis.y
	var px_per_world := map_rect.size.y / maxf(camera_ortho_size, 0.01)
	var sx := offset.dot(right) * px_per_world
	var sy := -offset.dot(up_world) * px_per_world  # screen Y is inverted vs world up
	return map_rect.get_center() + Vector2(sx, sy)


func _draw_ring(center: Vector2, radius: float, color: Color, width: float = 1.0) -> void:
	var prev := center + Vector2(radius, 0.0)
	for i in range(1, RING_SEGMENTS + 1):
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		var next := center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(prev, next, color, width)
		prev = next

func _update_blips(delta: float, old_angle: float, new_angle: float) -> void:
	# Age existing blips; update last known position while node is valid.
	var i := _blips.size() - 1
	while i >= 0:
		_blips[i].age += delta
		if is_instance_valid(_blips[i].node):
			_blips[i].last_pos = (_blips[i].node as Node3D).global_position
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
		# World XZ angle — matches the sweep angle coordinate space.
		var angle := atan2(offset.z, offset.x)
		if angle < 0.0:
			angle += TAU
		if not _angle_in_sweep(angle, old_angle, new_angle):
			continue
		# Refresh existing blip or create a new one.
		var found := false
		for blip in _blips:
			if blip.get("node") == enemy:
				blip.age = 0.0
				found = true
				break
		if not found:
			_blips.append({ "node": enemy, "age": 0.0, "last_pos": (enemy as Node3D).global_position })

func _angle_in_sweep(angle: float, old_a: float, new_a: float) -> bool:
	if new_a >= old_a:
		return angle >= old_a and angle <= new_a
	else:
		return angle >= old_a or angle <= new_a
