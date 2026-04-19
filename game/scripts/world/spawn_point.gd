@tool
extends Node2D
class_name SpawnPoint

const GIZMO_RADIUS := 24.0
const GIZMO_COLOR := Color(0.3, 1.0, 0.5, 0.9)

@export var spawn_id: String = "":
	set(value):
		spawn_id = value
		queue_redraw()

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, GIZMO_RADIUS, Color(GIZMO_COLOR.r, GIZMO_COLOR.g, GIZMO_COLOR.b, 0.25))
	draw_arc(Vector2.ZERO, GIZMO_RADIUS, 0.0, TAU, 32, GIZMO_COLOR, 2.0)
	draw_line(Vector2(-GIZMO_RADIUS * 0.6, 0), Vector2(GIZMO_RADIUS * 0.6, 0), GIZMO_COLOR, 1.5)
	draw_line(Vector2(0, -GIZMO_RADIUS * 0.6), Vector2(0, GIZMO_RADIUS * 0.6), GIZMO_COLOR, 1.5)
	var label := spawn_id if spawn_id != "" else "(no id)"
	var font := ThemeDB.fallback_font
	var font_size := 14
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2(-size.x * 0.5, -GIZMO_RADIUS - 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GIZMO_COLOR)
