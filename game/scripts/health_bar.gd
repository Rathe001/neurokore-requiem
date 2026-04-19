extends Node2D
class_name HealthBar

const WIDTH := 40.0
const HEIGHT := 4.0

@onready var fill: Polygon2D = $Fill

func set_health(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	var filled := WIDTH * ratio
	var half_w := WIDTH / 2.0
	var half_h := HEIGHT / 2.0
	fill.polygon = PackedVector2Array([
		Vector2(-half_w, -half_h),
		Vector2(-half_w + filled, -half_h),
		Vector2(-half_w + filled, half_h),
		Vector2(-half_w, half_h),
	])
