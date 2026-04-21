extends Node3D
class_name PrototypeRoot

const ENEMY_SCENE: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")

const SPAWN_BATCH := 25
const MAX_CORPSES := 100

@export var spawn_min_radius: float = 8.0
@export var spawn_max_radius: float = 14.0

var _corpses: Array[Node3D] = []
var _corpse_head: int = 0

func _ready() -> void:
	add_to_group(&"corpse_manager")
	get_viewport().physics_object_picking = true
	_wire_switches()
	if DebugState.config != null and DebugState.config.disable_enemies:
		_clear_enemies()

func _wire_switches() -> void:
	var builder := get_node_or_null("LevelBuilder") as LevelBuilder
	if builder == null:
		return
	# Supply room has a locked door on its WEST wall — wire a switch if present
	var switch_supply := get_node_or_null("SwitchSupply") as PrototypeSwitch
	if switch_supply != null:
		var door := builder.get_door(&"supply_room", RoomDef.Wall.WEST)
		if door != null:
			switch_supply.target_door = switch_supply.get_path_to(door)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_horde_spawn"):
		if DebugState.config != null and DebugState.config.disable_enemies:
			return
		_spawn_wave(SPAWN_BATCH)
	elif event.is_action_pressed(&"debug_horde_clear"):
		_clear_enemies()
		_clear_corpses()

func register_corpse(corpse: Node3D) -> void:
	if _corpses.size() < MAX_CORPSES:
		_corpses.append(corpse)
	else:
		var oldest: Node3D = _corpses[_corpse_head]
		if is_instance_valid(oldest):
			EntityPool.release(oldest)
		_corpses[_corpse_head] = corpse
		_corpse_head = (_corpse_head + 1) % MAX_CORPSES

func corpse_count() -> int:
	return _corpses.size()

func _spawn_wave(count: int) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var center: Vector3 = player.global_position if player != null else Vector3.ZERO
	for i in count:
		var angle := randf() * TAU
		var radius := randf_range(spawn_min_radius, spawn_max_radius)
		var pos := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var enemy := EntityPool.acquire(ENEMY_SCENE)
		add_child(enemy)
		enemy.global_position = pos
		if enemy.has_method(&"reset"):
			enemy.reset()

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		SpatialGrid.unregister(e)
		EntityPool.release(e)

func _clear_corpses() -> void:
	for c in _corpses:
		if is_instance_valid(c):
			EntityPool.release(c)
	_corpses.clear()
	_corpse_head = 0
