extends Control
class_name SkillSlot

@onready var icon: ColorRect = $Icon
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var key_label: Label = $KeyLabel
@onready var background: ColorRect = $Background
@onready var border: ColorRect = $Border
@onready var inner: ColorRect = $Inner
@onready var frame: NinePatchRect = $Frame

var _skill: Skill = null
var _player: Node = null

func _ready() -> void:
	_apply_theme()
	UIThemeState.changed.connect(_apply_theme)

func _apply_theme() -> void:
	var p := UIThemeState.palette
	background.color = p.slot_bg
	border.color = p.slot_border
	inner.color = p.slot_bg
	if p.slot_frame != null:
		frame.texture = p.slot_frame
		frame.patch_margin_left = p.frame_patch_margin
		frame.patch_margin_top = p.frame_patch_margin
		frame.patch_margin_right = p.frame_patch_margin
		frame.patch_margin_bottom = p.frame_patch_margin
		frame.visible = true
		border.visible = false
	else:
		frame.texture = null
		frame.visible = false
		border.visible = true

func bind(player: Node, skill: Skill, keybind_label: String) -> void:
	_player = player
	_skill = skill
	if skill != null:
		icon.color = skill.icon_color
	else:
		icon.color = UIThemeState.palette.slot_bg
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
