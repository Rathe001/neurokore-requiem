extends Node2D
class_name EnemySpawner

# Drops enemies in waves at a configurable radius around the player.
# Intentionally simple: random points on a ring, soft cap on concurrent
# enemies. Meant for horde-density testing, not final encounter design.

@export var enemy_scene: PackedScene
@export var wave_interval: float = 3.0
@export var wave_size: int = 3
@export var spawn_radius: float = 420.0
@export var max_alive: int = 30

var _timer := 0.0

func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = wave_interval
		_spawn_wave()

func _spawn_wave() -> void:
	if enemy_scene == null:
		return
	var player := _find_player()
	if player == null:
		return
	var alive := get_tree().get_nodes_in_group(&"enemies").size()
	if alive >= max_alive:
		return
	var budget: int = min(wave_size, max_alive - alive)
	for i in budget:
		var enemy := enemy_scene.instantiate()
		var angle := randf() * TAU
		enemy.global_position = player.global_position + Vector2.from_angle(angle) * spawn_radius
		add_child(enemy)

func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group(&"player")
	return players[0] if players.size() > 0 else null
