class_name MonsterAffix extends Resource

## Modifier prefix applied to a monster pack — leader + companions all share
## the same affix list. Each multiplier compounds onto the rolled level
## stats; tint colors the floor ring so the player can read the modifier
## set at a glance from across the room.
##
## Effect IDs (lifesteal, thorns, burning, etc.) are author-time labels for
## now — the consumer hooks for those mechanics arrive when the damage-
## type / status-effect framework lands. Keep authoring them in affix .tres
## files even though they're inert; the data drives the eventual wire-up.

@export var id: StringName = &""
@export var label: String = ""

@export_group("Stat multipliers")
@export var health_mult: float = 1.0
@export var damage_mult: float = 1.0
## Multiplied onto attack_cooldown — < 1.0 = faster swings, > 1.0 = slower.
@export var attack_cooldown_mult: float = 1.0
@export var move_speed_mult: float = 1.0

@export_group("Visual")
## Floor ring tint that overrides the level-based color when this affix is
## present. Use distinct hues so player learns the affix-color mapping over
## a few encounters (Diablo-style: blue = magic, gold = rare, etc.).
@export var ring_tint: Color = Color.WHITE

@export_group("Roll")
@export var weight: int = 100
@export var min_level: int = 1

@export_group("Effect hooks")
## Reserved for future status / on-hit effect mechanics (lifesteal, thorns,
## explosive_death, ignite). Inert until those systems are built — declare
## them now so authoring stays forward-compatible.
@export var effects: Array[StringName] = []
