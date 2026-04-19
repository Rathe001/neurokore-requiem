extends Area2D
class_name Switch

const INTERACT_RANGE := 100.0

@export var switch_id: String = ""
@export var display_name: String = "Switch"

@onready var visual: Polygon2D = $Visual
@onready var outline: Line2D = $Outline

var _activated := false

func _enter_tree() -> void:
	_activated = GameState.is_switch_on(switch_id)
	if visual != null:
		_refresh_visual()

func _ready() -> void:
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)
	GameState.switch_changed.connect(_on_switch_changed)
	_refresh_visual()

func _on_mouse_entered() -> void:
	outline.visible = true
	var hud := _get_hud()
	if hud != null:
		hud.show_tooltip(display_name)

func _on_mouse_exited() -> void:
	outline.visible = false
	var hud := _get_hud()
	if hud != null:
		hud.hide_tooltip()

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	if _activated:
		return
	if not _player_in_range():
		return
	GameState.set_switch(switch_id, true)

func _player_in_range() -> bool:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return false
	return players[0].global_position.distance_to(global_position) <= INTERACT_RANGE

func _on_switch_changed(id: String, value: bool) -> void:
	if id != switch_id:
		return
	_activated = value
	_refresh_visual()

func _refresh_visual() -> void:
	if visual == null:
		return
	visual.color = Color(1.0, 0.9, 0.3, 1.0) if _activated else Color(0.5, 0.45, 0.15, 0.8)

func _get_hud() -> Node:
	var nodes := get_tree().get_nodes_in_group(&"hud")
	return nodes[0] if nodes.size() > 0 else null
