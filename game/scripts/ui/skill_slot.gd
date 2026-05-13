extends Control
class_name SkillSlot

@onready var icon: ColorRect = $Icon
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var key_label: Label = $KeyLabel
@onready var glyph_label: Label = $GlyphLabel
@onready var background: ColorRect = $Background
@onready var border: ColorRect = $Border
@onready var inner: ColorRect = $Inner
@onready var frame: NinePatchRect = $Frame

var _skill: Skill = null
var _player: Node = null
# Built at runtime so the .tscn doesn't need editing. Visible only
# while the bound skill is on cooldown.
#   _cooldown_dim   — static full-coverage dim rect under the drain
#                     overlay, so the icon stays uniformly darkened
#                     the whole cooldown (otherwise the bottom half
#                     reads as "ready" once the drain shrinks past
#                     the timer label, killing readability).
#   _cooldown_label — centred numeric countdown. Integer seconds for
#                     cooldowns ≥1s, one decimal below.
var _cooldown_dim: ColorRect = null
var _cooldown_label: Label = null
var _charge_label: Label = null

func _ready() -> void:
	_apply_theme()
	UIThemeState.changed.connect(_apply_theme)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	tree_exiting.connect(_on_tree_exiting)
	_cooldown_dim = ColorRect.new()
	_cooldown_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cooldown_dim.color = Color(0.0, 0.0, 0.0, 0.65)
	_cooldown_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cooldown_dim.visible = false
	add_child(_cooldown_dim)
	# Sit the static dim layer between the icon and the animated drain
	# overlay so the drain shows on top of (not under) the dim. The
	# drain overlay was added in the .tscn, so its child index = 5.
	move_child(_cooldown_dim, cooldown_overlay.get_index())
	_cooldown_label = Label.new()
	_cooldown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cooldown_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_cooldown_label.add_theme_font_size_override(&"font_size", 8)
	_cooldown_label.add_theme_color_override(&"font_color", Color.WHITE)
	_cooldown_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	_cooldown_label.add_theme_constant_override(&"outline_size", 2)
	_cooldown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cooldown_label.visible = false
	add_child(_cooldown_label)
	_charge_label = Label.new()
	_charge_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_charge_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_charge_label.add_theme_font_size_override(&"font_size", 8)
	_charge_label.add_theme_color_override(&"font_color", Color(0.3, 0.9, 0.4))
	_charge_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	_charge_label.add_theme_constant_override(&"outline_size", 2)
	_charge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge_label.visible = false
	add_child(_charge_label)

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
		var has_glyph := skill.glyph != ""
		glyph_label.text = skill.glyph
		glyph_label.visible = has_glyph
		key_label.visible = not has_glyph
	else:
		icon.color = UIThemeState.palette.slot_bg
		glyph_label.visible = false
		key_label.visible = true
	key_label.text = keybind_label
	cooldown_overlay.visible = false

func _process(_delta: float) -> void:
	if _player == null or _skill == null or not _player.has_method(&"get_cooldown_ratio"):
		if _charge_label != null:
			_charge_label.visible = false
		return
	_update_charge_badge()
	var ratio: float = _player.get_cooldown_ratio(_skill)
	if ratio <= 0.0:
		cooldown_overlay.visible = false
		if _cooldown_dim != null:
			_cooldown_dim.visible = false
		if _cooldown_label != null:
			_cooldown_label.visible = false
		return
	cooldown_overlay.visible = true
	cooldown_overlay.offset_top = size.y * (1.0 - ratio)
	if _cooldown_dim != null:
		_cooldown_dim.visible = true
	# Numeric countdown — integer seconds at 1s+ (room for two digits
	# without overflowing the slot), one decimal below 1s so the
	# player sees the final tick rather than a flat "0".
	if _cooldown_label != null and _player.has_method(&"get_cooldown_remain"):
		var remain: float = _player.get_cooldown_remain(_skill)
		_cooldown_label.text = "%d" % int(ceil(remain)) if remain >= 1.0 else "%.1f" % remain
		_cooldown_label.visible = true


func _on_mouse_entered() -> void:
	if _skill == null:
		return
	var source: Item = _resolve_source_item()
	get_tree().call_group(&"interactable_tooltip", &"show_skill", _skill, source)


func _on_mouse_exited() -> void:
	if is_inside_tree():
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")


func _on_tree_exiting() -> void:
	_on_mouse_exited()
	UIThemeState.changed.disconnect(_apply_theme)


func _update_charge_badge() -> void:
	if _charge_label == null:
		return
	if _skill == null or _skill.active_kind != Skill.ActiveKind.POTION:
		_charge_label.visible = false
		return
	if _player == null or not _player.has_method(&"get_potion_charges"):
		_charge_label.visible = false
		return
	var charges: int = _player.get_potion_charges()
	_charge_label.text = str(charges)
	_charge_label.visible = true


func _resolve_source_item() -> Item:
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	if weapon != null:
		if weapon.fire_skill == _skill or weapon.alt_fire_skill == _skill:
			return weapon
	var offhand: Item = InventoryState.get_equipped(&"offhand")
	if offhand != null:
		if offhand.fire_skill == _skill or offhand.alt_fire_skill == _skill:
			return offhand
	return null
