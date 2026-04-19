extends Node3D

const ENEMY_SCENE: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")

const SPAWN_BATCH := 25
const SPAWN_MIN_RADIUS := 8.0
const SPAWN_MAX_RADIUS := 14.0
const MAX_CORPSES := 100

var _corpses: Array[Node3D] = []

func _ready() -> void:
	add_to_group(&"corpse_manager")
	if DebugState.config != null and DebugState.config.disable_enemies:
		_clear_enemies()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_horde_spawn"):
		if DebugState.config != null and DebugState.config.disable_enemies:
			return
		_spawn_wave(SPAWN_BATCH)
	elif event.is_action_pressed(&"debug_horde_clear"):
		_clear_enemies()
		_clear_corpses()

func register_corpse(corpse: Node3D) -> void:
	_corpses.append(corpse)
	while _corpses.size() > MAX_CORPSES:
		var oldest: Node3D = _corpses.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

func corpse_count() -> int:
	return _corpses.size()

func _spawn_wave(count: int) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var center: Vector3 = player.global_position if player != null else Vector3.ZERO
	for i in count:
		var angle := randf() * TAU
		var radius := randf_range(SPAWN_MIN_RADIUS, SPAWN_MAX_RADIUS)
		var pos := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var enemy := ENEMY_SCENE.instantiate() as Node3D
		add_child(enemy)
		enemy.global_position = pos

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		e.queue_free()

func _clear_corpses() -> void:
	for c in _corpses:
		if is_instance_valid(c):
			c.queue_free()
	_corpses.clear()
