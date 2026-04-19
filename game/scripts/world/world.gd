extends Node2D
class_name World

@onready var entities: Node2D = $Entities
@onready var hud: HUD = $HUD

var _level_cache: Dictionary = {}

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

func _on_zone_exit_used(target_scene: PackedScene, target_spawn_id: String) -> void:
	if target_scene == null:
		return
	if hud != null:
		hud.hide_tooltip()
		await hud.fade_out()
	var target_path := target_scene.resource_path

	var old_level := _find_level()
	if old_level != null:
		var old_path: String = old_level.scene_file_path
		entities.remove_child(old_level)
		if old_path != "":
			_level_cache[old_path] = old_level

	var new_level: Node
	if _level_cache.has(target_path):
		new_level = _level_cache[target_path]
		_level_cache.erase(target_path)
	else:
		new_level = target_scene.instantiate()
	entities.add_child(new_level)
	_move_player_to_spawn(new_level, target_spawn_id)
	await get_tree().process_frame
	_rebind()
	if hud != null:
		await hud.fade_in()

func _move_player_to_spawn(level: Node, spawn_id: String) -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	for spawn in _collect_spawns(level):
		if spawn.spawn_id == spawn_id:
			players[0].global_position = spawn.global_position
			return
	players[0].global_position = Vector2.ZERO

func _collect_spawns(node: Node) -> Array:
	var result: Array = []
	if node is SpawnPoint:
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_spawns(child))
	return result
