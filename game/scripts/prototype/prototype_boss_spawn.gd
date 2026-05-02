extends Node3D
class_name PrototypeBossSpawn
## Slot marker that spawns a boss enemy at its position. Lives in the
## scene so level resets (NG+) re-trigger the spawn via the &"resettable"
## group. Mirrors PrototypeRoot._spawn_boss but layout-driven instead of
## scene-fixed-coordinate.

const ENEMY_SCENE: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")
@export var display_name: String = "Boss"


func _ready() -> void:
	add_to_group(&"resettable")
	_spawn()


# Called by PrototypeRoot.reset_level() group dispatch. PrototypeRoot already
# clears all enemies before this fires, so a fresh boss is safe to spawn.
func reset_state() -> void:
	_spawn()


func _spawn() -> void:
	var boss := EntityPool.acquire(ENEMY_SCENE)
	# Set identity before add_child so the first _init_enemy pass applies
	# boss stats directly and skips the trash display-name roll. (Prevents
	# a brief tint/floor-ring flicker on un-pooled instances.)
	if "is_boss" in boss:
		boss.is_boss = true
	if "display_name" in boss:
		boss.display_name = display_name
	get_parent().add_child(boss)
	boss.global_position = global_position
	if boss.has_method(&"reset"):
		boss.reset()
