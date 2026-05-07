class_name OffhandBase extends Resource

## Defines an offhand archetype (e.g. "Buckler", "Shield Generator").
## Parallel to WeaponBase / GrenadeBase but for offhand items.

@export var id: StringName = &""
@export var display_name: String = ""
@export var glyph: String = "◊"

@export var fire_skill: Skill
