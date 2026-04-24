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

@export_group("Container")
@export var inventory_bonus: int = 0

@export_group("Combat")
@export var two_handed: bool = false
@export var fire_skill: Skill
@export var alt_fire_skill: Skill

@export_group("Belt")
@export var utility_slots: int = 0

@export_group("Stats")
## Flat stat bonuses applied when this item is equipped.
## Keys match AttributeState rollable stat IDs: ort, ing, amb, dev, opt, cla.
@export var stat_modifiers: Dictionary = {}
