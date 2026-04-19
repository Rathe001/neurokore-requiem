extends Control
class_name SkillSlot

@onready var icon: ColorRect = $Icon
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var key_label: Label = $KeyLabel

var _skill: Skill = null
var _player: Player = null

func bind(player: Player, skill: Skill, keybind_label: String) -> void:
	_player = player
	_skill = skill
	if skill != null:
		icon.color = Color(skill.indicator_color.r, skill.indicator_color.g, skill.indicator_color.b, 1.0)
	key_label.text = keybind_label
	cooldown_overlay.position.y = 0.0
	cooldown_overlay.size.y = 0.0

func _process(_delta: float) -> void:
	if _player == null or _skill == null:
		return
	var ratio := _player.get_cooldown_ratio(_skill)
	var h := size.y
	cooldown_overlay.position.y = h * (1.0 - ratio)
	cooldown_overlay.size.y = h * ratio
