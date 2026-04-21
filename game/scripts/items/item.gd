class_name Item extends Resource

@export var id: StringName
@export var name_key: String = ""
@export var description_key: String = ""
@export var kind: StringName = &""
@export var rarity: StringName = &"common"
@export var glyph: String = "?"
@export var glyph_color: Color = Color(1, 1, 1, 1)

@export_group("Light")
@export var light_energy: float = 0.0
@export var light_range: float = 0.0
@export var light_color: Color = Color(1, 1, 1, 1)

@export_group("Container")
@export var inventory_bonus: int = 0

@export_group("Belt")
@export var utility_slots: int = 0
