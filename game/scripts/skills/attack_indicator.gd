extends Node2D
class_name AttackIndicator

const FADE_DURATION := 0.18
const CONE_SEGMENTS := 24

enum Shape { CONE, RADIAL }

var _shape: Shape = Shape.CONE
var _radius: float = 0.0
var _cone_deg: float = 60.0
var _aim_angle: float = 0.0
var _color: Color = Color.WHITE

func show_cone(aim: Vector2, radius: float, cone_deg: float, color: Color) -> void:
	_shape = Shape.CONE
	_aim_angle = aim.angle()
	_radius = radius
	_cone_deg = cone_deg
	_color = color
	queue_redraw()
	_fade_and_free()

func show_radial(radius: float, color: Color) -> void:
	_shape = Shape.RADIAL
	_radius = radius
	_color = color
	queue_redraw()
	_fade_and_free()

func _fade_and_free() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)

func _draw() -> void:
	match _shape:
		Shape.CONE:
			var pts := PackedVector2Array()
			pts.append(Vector2.ZERO)
			var half := deg_to_rad(_cone_deg * 0.5)
			var start := _aim_angle - half
			var end := _aim_angle + half
			for i in CONE_SEGMENTS + 1:
				var t := float(i) / CONE_SEGMENTS
				var a: float = lerp(start, end, t)
				pts.append(Vector2.from_angle(a) * _radius)
			draw_colored_polygon(pts, _color)
		Shape.RADIAL:
			draw_circle(Vector2.ZERO, _radius, _color)
