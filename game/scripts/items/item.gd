class_name Item extends Resource

@export var id: StringName
@export var name_key: String = ""
@export var description_key: String = ""
@export var kind: StringName = &""
@export var main_type: String = ""
@export var sub_type: String = ""
@export var rarity: StringName = &"common"
@export var glyph: String = "?"
@export var glyph_color: Color = Color(1, 1, 1, 1)

enum LightType { DIRECTIONAL, RADIANT, SCANNER, UV }

@export_group("Light")
@export var light_type: LightType = LightType.DIRECTIONAL
@export var light_energy: float = 0.0
@export var light_range: float = 0.0
@export var light_color: Color = Color(1, 1, 1, 1)

@export_group("Combat")
@export var two_handed: bool = false
@export var fire_skill: Skill
@export var alt_fire_skill: Skill
## Weapon stats rolled once at item generation from the WeaponBase ranges.
## Defaults are no-ops so non-weapon items don't accidentally affect combat.
@export var weapon_base_id: StringName = &""
@export var damage_min: int = 0
@export var damage_max: int = 0
@export var attack_speed: float = 1.0
@export var crit_chance: float = 0.0
@export var accuracy: float = 1.0
@export var weapon_range: float = 3.0

@export_group("Belt")
@export var utility_slots: int = 0

@export_group("Stats")
## Flat stat / modifier bonuses applied when this item is equipped.
## Keys are StringName — both AttributeState rollable stats (&"ort", &"ing",
## &"amb", &"dev", &"opt", &"cla") AND non-stat modifiers (&"inventory_bonus",
## &"damage_reduction", &"toxic_resistance", &"range_bonus", future ammo /
## magazine / augment-slot bonuses) live in this single dict. Affix table
## entries MUST use StringName keys (the &"" prefix); plain string keys hash
## differently and silently fail to match reads.
@export var stat_modifiers: Dictionary = {}


## Read a modifier with a fallback. Single accessor for typed reads from
## stat_modifiers — saves the every-caller `int(item.stat_modifiers.get(...))`
## boilerplate and centralises the dict-key contract.
func get_modifier(key: StringName, fallback: int = 0) -> int:
	return int(stat_modifiers.get(key, fallback))
