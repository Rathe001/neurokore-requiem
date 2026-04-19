extends Control
class_name SkillSlot

@onready var icon: ColorRect = $Icon
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var key_label: Label = $KeyLabel

var _skill: Skill = null
var _player: Node = null

func bind(player: Node, skill: Skill, keybind_label: String) -> void:
	_player = player
	_skill = skill
	if skill != null:
		icon.color = skill.icon_color
	else:
		icon.color = Color(0.12, 0.14, 0.18, 1.0)
	key_label.text = keybind_label
	cooldown_overlay.position.y = 0.0
	cooldown_overlay.size.y = 0.0

func _process(_delta: float) -> void:
	if _player == null or _skill == null or not _player.has_method(&"get_cooldown_ratio"):
		return
	var ratio: float = _player.get_cooldown_ratio(_skill)
	var h := size.y
	cooldown_overlay.position.y = h * (1.0 - ratio)
	cooldown_overlay.size.y = h * ratio
