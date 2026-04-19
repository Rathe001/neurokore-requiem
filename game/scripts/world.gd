extends Node2D
class_name World

@onready var entities: Node2D = $Entities
@onready var hud: HUD = $HUD

func _ready() -> void:
	_rebind()

func _rebind() -> void:
	for exit in get_tree().get_nodes_in_group(&"zone_exit"):
		if not exit.used.is_connected(_on_zone_exit_used):
			exit.used.connect(_on_zone_exit_used)
	var level := _find_level()
	if level != null and hud != null:
		hud.bind_level(level)

func _find_level() -> Node:
	for child in entities.get_children():
		if child.is_in_group(&"level"):
			return child
	return null

func _on_zone_exit_used(target_scene: PackedScene) -> void:
	if target_scene == null:
		return
	var old_level := _find_level()
	if old_level != null:
		old_level.queue_free()
	var new_level := target_scene.instantiate()
	entities.add_child(new_level)
	var players := get_tree().get_nodes_in_group(&"player")
	if players.size() > 0:
		players[0].global_position = Vector2.ZERO
	await get_tree().process_frame
	_rebind()
