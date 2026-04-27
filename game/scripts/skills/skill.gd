extends Resource
class_name Skill

enum TargetingMode {
	SINGLE_CONE,
	AOE_RADIAL,
}

@export var display_name: String = ""
@export var glyph: String = ""
@export var damage: int = 10
@export var skill_range: float = 100.0
@export var cooldown: float = 0.5
@export var wind_up: float = 0.0
@export var resource_cost: int = 0
@export var targeting_mode: TargetingMode = TargetingMode.SINGLE_CONE
@export var cone_deg: float = 60.0
@export var knockback: float = 0.0
@export var icon_color: Color = Color(0.7, 0.9, 1.0, 1.0)
