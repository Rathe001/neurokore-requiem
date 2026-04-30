extends Control
class_name MinimapPlayerDot

## Draws the player position dot at the center of the minimap, using the
## class palette color.

const DOT_RADIUS := 3.0

var map_center := Vector2.ZERO:
	set(value):
		if map_center != value:
			map_center = value
			queue_redraw()

var opacity: float = 1.0:
	set(value):
		if opacity != value:
			opacity = value
			queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	var col: Color = UIThemeState.palette.player_color
	col.a = opacity
	draw_circle(map_center, DOT_RADIUS, col)
