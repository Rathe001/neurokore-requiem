class_name BehaviorMod extends Resource

## Behavior modifier carried by a single piece of gear. Behavior mods are
## the identity layer of itemization — two items with identical stats and
## different mods play differently. See docs/systems.md "Behavior mods"
## for the design pillars and tradeoffs.
##
## Each gear slot (head/chest/hands/legs/feet/back — not weapons) has a
## pool of ~4 mods authored as separate .tres files under
## res://resources/behavior_mods/{slot}/{id}.tres. ItemRoller picks one
## from the pool at drop time and rolls its params from the ranges below.
##
## Per the "feature-flag" rollout model:
##   - `is_implemented` toggles whether equipping this mod actually does
##     anything in-game. False = the mod tooltip renders in gray ("not
##     yet active"); true = it dispatches via BehaviorModRegistry.
##   - `condition_id` (optional) names a context the mod requires to be
##     "active" even when implemented — e.g. "wielding_laser_pistol". An
##     empty string means the mod is always-active when implemented. The
##     registry resolves condition IDs to runtime bool checks.
##
## Item stores the mod by id (StringName) plus a Dictionary of rolled
## param values. Looking up the BehaviorMod resource happens through
## BehaviorModRegistry, which loads every .tres under the mod directory
## once at startup.

## Unique identifier — matches the .tres filename (without extension).
## Used by Item.behavior_mod_id, BehaviorModRegistry lookups, and
## condition-check dispatch keys.
@export var id: StringName = &""

## Player-facing display name (e.g. "Servo Stride", "Jetpack"). Tooltip
## paints this prominently above the description.
@export var display_name: String = ""

## Which gear slot this mod belongs to. Must match an armor slot key
## from SlotRegistry: &"head", &"chest", &"hands", &"legs", &"feet",
## &"back". ItemRoller filters the mod pool by this when rolling.
@export var slot: StringName = &""

## Player-facing description of what the mod does + its tradeoff. Show
## the trade EXPLICITLY (e.g. "Sprint costs no resource. Trade: −X% base
## walk speed.") so the player can reason about whether the swap is
## worth it without alt-tabbing to a wiki.
@export_multiline var description: String = ""

## Rollable parameters as a Dictionary keyed by parameter name (String)
## mapping to a [min, max] float array. ItemRoller samples each at drop
## time using the rarity-curve roller so quality scales with item rarity.
##
## Example: { "drain_per_sec": [18.0, 26.0], "ceiling_m": [4.0, 6.0] }
##
## The rolled values land on Item.mod_params under the same keys so
## tooltip rendering and effect dispatch can read them back.
@export var param_ranges: Dictionary = {}

## True when this mod has a real effect dispatched through
## BehaviorModRegistry. False marks the mod as a "preview" — it still
## rolls onto items so the player can see the design space, but the
## tooltip renders it grayed-out and equipping it has no in-game effect.
##
## Flip to true on the .tres once the effect is wired so existing rolled
## drops automatically become live without re-rolling the player's
## inventory.
@export var is_implemented: bool = false

## Optional gating condition for "active" state. Empty string means the
## mod is unconditionally active whenever implemented. A non-empty value
## names a check the registry will resolve at display + dispatch time
## (e.g. "wielding_laser_pistol" → checks the equipped weapon's
## weapon_base_id). The tooltip flips between green (condition met) and
## gray (condition not met or not implemented yet) on each refresh.
@export var condition_id: StringName = &""

## Optional class restriction. When set to a class id (&"analog",
## &"cyborg", &"forged", etc.), only matching characters can roll or
## equip this mod. Empty = available to all classes.
@export var class_restriction: StringName = &""
