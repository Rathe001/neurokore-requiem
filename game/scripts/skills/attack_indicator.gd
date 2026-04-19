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

static func spawn(parent: Node, skill: Skill, aim: Vector2) -> AttackIndicator:
	var indicator := AttackIndicator.new()
	parent.add_child(indicator)
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			indicator.show_cone(aim, skill.range, skill.cone_deg, skill.indicator_color, skill.wind_up)
		Skill.TargetingMode.AOE_RADIAL:
			indicator.show_radial(skill.range, skill.indicator_color, skill.wind_up)
	return indicator

func show_cone(aim: Vector2, radius: float, cone_deg: float, color: Color, wind_up: float = 0.0) -> void:
	_shape = Shape.CONE
	_aim_angle = aim.angle()
	_radius = radius
	_cone_deg = cone_deg
	_color = color
	queue_redraw()
	_play(wind_up)

func show_radial(radius: float, color: Color, wind_up: float = 0.0) -> void:
	_shape = Shape.RADIAL
	_radius = radius
	_color = color
	queue_redraw()
	_play(wind_up)

func _play(wind_up: float) -> void:
	var tween := create_tween()
	if wind_up > 0.0:
		modulate.a = 0.35
		tween.tween_property(self, "modulate:a", 1.0, wind_up)
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
