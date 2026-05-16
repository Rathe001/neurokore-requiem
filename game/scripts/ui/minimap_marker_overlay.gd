extends Control
class_name MinimapMarkerOverlay

## Draws switch / exit markers on the minimap. Markers are filtered by
## ExplorationState — only pieces the player has revealed contribute
## markers, so an unexplored room's switches don't spoil their location.
##
## Switches render as small filled circles; an unused switch is yellow
## and slightly larger so it reads as "still to do," while a used switch
## drops to a dim grey. The level exit is a diamond — red when locked,
## green once the boss is dead and the player can descend.
##
## Positioning uses the same iso projection basis as ScannerRadar so
## markers line up with the rotated map texture. The parent Minimap
## sets view_center / view_size / project_* every frame and queue_redraws
## us; manual fullscreen panning therefore scrolls markers in lockstep
## with the underlying floor pixels.

const SWITCH_RADIUS_ACTIVE := 4.0
const SWITCH_RADIUS_USED := 2.5
const EXIT_RADIUS := 5.5

const SWITCH_COLOR_ACTIVE := Color(1.0, 0.85, 0.2, 1.0)
const SWITCH_COLOR_USED := Color(0.45, 0.45, 0.45, 0.85)
const EXIT_COLOR_LOCKED := Color(0.95, 0.3, 0.25, 1.0)
const EXIT_COLOR_UNLOCKED := Color(0.3, 0.95, 0.4, 1.0)

## Parent Minimap writes these every frame from _update_pan so the overlay
## projects relative to whatever the user is currently looking at —
## including manual arrow-key pan offsets.
var map_rect := Rect2(Vector2.ZERO, Vector2(170.0, 170.0))
var view_center: Vector3 = Vector3.ZERO
var view_size: float = 30.0
var project_right: Vector3 = Vector3.RIGHT
var project_up: Vector3 = Vector3.FORWARD
var opacity: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Repaint on any ExplorationState change so newly-revealed rooms
	# light up their markers without waiting for the next view update.
	# changed fires on reset(), reveal_room, and bulk reveal too.
	if not ExplorationState.changed.is_connected(queue_redraw):
		ExplorationState.changed.connect(queue_redraw)


func _draw() -> void:
	if map_rect.size.x <= 0.0 or view_size <= 0.0:
		return
	var center := map_rect.get_center()
	var px_per_world := map_rect.size.y / view_size
	var radius := map_rect.size.x * 0.5

	for n in get_tree().get_nodes_in_group(&"minimap_marker"):
		var node := n as Node3D
		if node == null or not node.is_inside_tree():
			continue
		var room_id: StringName = ExplorationState.room_at_world(node.global_position)
		# Empty room_id (legacy levels without ExplorationState population)
		# falls through to always-render so hand-authored prototype scenes
		# still show their markers.
		if room_id != &"" and not ExplorationState.is_explored(room_id):
			continue
		var pos := _project(node.global_position, center, px_per_world)
		# Clip to the visible map circle so markers don't render in the
		# bezel area when the user pans them off-screen.
		var from_center := pos - center
		if from_center.length() > radius:
			continue
		if node is PrototypeExit:
			_draw_exit(pos, (node as PrototypeExit).is_locked())
		elif node is PrototypeSwitch:
			_draw_switch(pos, (node as PrototypeSwitch).is_used())


func _project(world_pos: Vector3, center: Vector2, px_per_world: float) -> Vector2:
	var offset := world_pos - view_center
	var sx := offset.dot(project_right) * px_per_world
	var sy := -offset.dot(project_up) * px_per_world  # screen Y inverted
	return center + Vector2(sx, sy)


func _draw_switch(pos: Vector2, used: bool) -> void:
	var col: Color = SWITCH_COLOR_USED if used else SWITCH_COLOR_ACTIVE
	col.a *= opacity
	var r: float = SWITCH_RADIUS_USED if used else SWITCH_RADIUS_ACTIVE
	draw_circle(pos, r, col)


func _draw_exit(pos: Vector2, locked: bool) -> void:
	var col: Color = EXIT_COLOR_LOCKED if locked else EXIT_COLOR_UNLOCKED
	col.a *= opacity
	var r := EXIT_RADIUS
	var pts := PackedVector2Array([
		pos + Vector2(0.0, -r),
		pos + Vector2(r, 0.0),
		pos + Vector2(0.0, r),
		pos + Vector2(-r, 0.0),
	])
	draw_colored_polygon(pts, col)
