class_name DebugConfig
extends Resource

# All available debug overrides live here. Add new fields as features need
# them — commit the updated defaults file alongside, so every dev sees the
# new field with a safe default.

@export_group("Starting State")
@export var override_start_position: bool = false
@export var start_position: Vector3 = Vector3.ZERO
@export var starting_credits: int = 0

@export_group("Player Cheats")
@export var god_mode: bool = false
@export var infinite_resource: bool = false

@export_group("Enemy Behavior")
@export var one_shot_enemies: bool = false
@export var disable_enemies: bool = false

@export_group("Combat Feedback")
@export var show_attack_telegraphs: bool = false

@export_group("Overlay")
@export var show_debug_overlay: bool = false
