class_name DebugConfig
extends Resource

# All available debug overrides live here. Add new fields as features need
# them — commit the updated defaults file alongside, so every dev sees the
# new field with a safe default.

@export_group("Starting State")
@export var override_start_position: bool = false
@export var start_position: Vector3 = Vector3.ZERO
@export var starting_credits: int = 0
## Items to auto-equip on spawn. Each entry is "MainType" or "MainType:base_id".
## Examples: "Grenade:frag", "1H Weapon:ranged_1h", "Offhand:active_shield".
## Rolled at common rarity, item level 1. Equips to the appropriate slot;
## extras go to inventory. Processed in order — later items of the same
## slot type overwrite earlier ones in that slot.
@export var starter_loadout: PackedStringArray = []

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
