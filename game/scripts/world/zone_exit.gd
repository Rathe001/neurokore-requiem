extends Area2D
class_name ZoneExit

signal used(target_scene: PackedScene, target_spawn_id: String)

const INTERACT_RANGE := 100.0

@export_file("*.tscn") var target_scene_path: String
@export var target_spawn_id: String = ""
@export var required_switch_id: String = ""
@export var display_name: String = "Exit"

@onready var visual: Polygon2D = $Visual
@onready var outline: Line2D = $Outline

var _used := false

func _enter_tree() -> void:
	add_to_group(&"zone_exit")
	_used = false
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
		hud.show_tooltip(_tooltip_text())

func _on_mouse_exited() -> void:
	outline.visible = false
	var hud := _get_hud()
	if hud != null:
		hud.hide_tooltip()

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	if _used:
		return
	if not _can_use():
		return
	if not _player_in_range():
		return
	var scene := _load_target()
	if scene == null:
		return
	_used = true
	used.emit(scene, target_spawn_id)

func _can_use() -> bool:
	if required_switch_id == "":
		return true
	return GameState.is_switch_on(required_switch_id)

func _player_in_range() -> bool:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return false
	return players[0].global_position.distance_to(global_position) <= INTERACT_RANGE

func _tooltip_text() -> String:
	if _can_use():
		return display_name
	return "%s (Locked)" % display_name

func _on_switch_changed(id: String, _value: bool) -> void:
	if id == required_switch_id:
		_refresh_visual()

func _refresh_visual() -> void:
	if visual == null:
		return
	visual.color = Color(0.3, 0.85, 0.9, 0.8) if _can_use() else Color(0.6, 0.25, 0.25, 0.6)

func _load_target() -> PackedScene:
	if target_scene_path == "":
		return null
	return load(target_scene_path) as PackedScene

func _get_hud() -> Node:
	var nodes := get_tree().get_nodes_in_group(&"hud")
	return nodes[0] if nodes.size() > 0 else null
