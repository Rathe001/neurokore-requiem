extends Node3D
class_name EnemiesContainer

## Container for all spawned enemies. In multiplayer, a MultiplayerSpawner
## attached here replicates add_child / remove_child to all peers so
## clients see the same enemies the host spawned.
##
## In single-player, enemies are added here the same way but without any
## network replication — the spawner is inert when there's no peer.

const ENEMY_SCENE: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")

var _spawner: MultiplayerSpawner


func _ready() -> void:
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "MultiplayerSpawner"
	# The spawner watches THIS node's children.
	_spawner.spawn_path = NodePath("..")
	# Register the enemy scene so the spawner can replicate it.
	_spawner.add_spawnable_scene(ENEMY_SCENE.resource_path)
	add_child(_spawner)
