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
@export var unlock_all_talents: bool = false

@export_group("Enemy Behavior")
@export var one_shot_enemies: bool = false
@export var disable_enemies: bool = false

@export_group("Combat Feedback")
@export var show_attack_telegraphs: bool = false

@export_group("Overlay")
@export var show_debug_overlay: bool = false
## When true, every HoverableInteractable prints its visual AABB +
## CollisionShape3D extents + a mismatch flag on _ready. One-shot
## diagnostic for the collision-vs-visual audit (pre-release task 3).
## Walk the level with this enabled, grep console for "INTERACTABLE
## COLLISION AUDIT" to find mismatches.
@export var dump_interactable_collision_audit: bool = false

@export_group("Post-Processing")
## Screen filter mode. 0=Off, 1=VHS, 2=Security Cam, 3=Night Vision,
## 4=Thermal, 5=Concussed, 6=Drunk, 7=Low HP, 8=Hallucination, 9=Glitch,
## 10=Noir, 11=Inverted. Mirrors RetroFilterOverlay.RetroMode.
@export var retro_filter_mode: int = 0
## Master toggle for the WorldEnvironment color grading
## (adjustment_brightness/contrast/saturation). A/B the graded vs
## ungraded look from the debug panel without restarting.
@export var color_grading_enabled: bool = true

## MP host-migration toggle (off by default — experimental).
## When false (default), a host disconnect drops surviving clients to the
## main menu via HostDisconnectedScreen (the documented Phase 8 flow).
## When true, surviving clients run the host-migration handshake:
##   - Elect a new host (lowest steam id wins)
##   - Re-bind transport (close old peer; new host opens host peer;
##     others open client peers)
##   - Re-authority every entity to the new host's peer 1
##   - Game resumes for everyone or falls back to disconnect on timeout
## Flagged off because the flow is multi-week stability work and has not
## been verified across real Steam accounts yet. See
## [[project_host_migration_plan]] memory for the iteration roadmap.
@export var host_migration_enabled: bool = false
