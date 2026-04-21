class_name PrototypeTooltip
extends Control

const SCREEN_MARGIN := Vector2(12, 12)
const PADDING_X := 8
const PADDING_Y := 6
const CONTENT_MIN_WIDTH := 200.0

var _bg: PanelContainer
var _vbox: VBoxContainer
var _text_label: Label
var _name_label: Label
var _desc_label: Label
var _stats_label: Label

func _ready() -> void:
	add_to_group(&"interactable_tooltip")
	mouse_filter = MOUSE_FILTER_IGNORE
	top_level = true
	visible = false
	_build_ui()
	_apply_theme()
	UIThemeState.changed.connect(_apply_theme)

func _build_ui() -> void:
	_bg = PanelContainer.new()
	_bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bg)

	_vbox = VBoxContainer.new()
	_vbox.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_vbox.add_theme_constant_override(&"separation", 3)
	_bg.add_child(_vbox)

	_text_label = Label.new()
	_text_label.mouse_filter = MOUSE_FILTER_IGNORE
	_text_label.add_theme_font_size_override(&"font_size", 11)
	_vbox.add_child(_text_label)

	_name_label = Label.new()
	_name_label.mouse_filter = MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override(&"font_size", 13)
	_vbox.add_child(_name_label)

	_desc_label = Label.new()
	_desc_label.mouse_filter = MOUSE_FILTER_IGNORE
	_desc_label.add_theme_font_size_override(&"font_size", 10)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_desc_label)

	_stats_label = Label.new()
	_stats_label.mouse_filter = MOUSE_FILTER_IGNORE
	_stats_label.add_theme_font_size_override(&"font_size", 10)
	_vbox.add_child(_stats_label)

func _apply_theme() -> void:
	var p: UIThemeConfig = UIThemeState.palette
	if p == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = p.panel_bg
	style.border_color = p.panel_border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = PADDING_X
	style.content_margin_right = PADDING_X
	style.content_margin_top = PADDING_Y
	style.content_margin_bottom = PADDING_Y
	_bg.add_theme_stylebox_override(&"panel", style)
	_text_label.add_theme_color_override(&"font_color", p.text)
	_desc_label.add_theme_color_override(&"font_color", p.text_dim)
	_stats_label.add_theme_color_override(&"font_color", p.text)

func _process(_delta: float) -> void:
	if not visible:
		return
	var vp_size := get_viewport().get_visible_rect().size
	position = vp_size - _bg.size - SCREEN_MARGIN

func show_text(text: String) -> void:
	if text.is_empty():
		hide_tooltip()
		return
	_text_label.text = text
	_text_label.visible = true
	_name_label.visible = false
	_desc_label.visible = false
	_stats_label.visible = false
	_bg.reset_size()
	visible = true

func show_item(item: Item) -> void:
	if item == null:
		hide_tooltip()
		return
	_text_label.visible = false

	_name_label.text = item.name_key
	_name_label.add_theme_color_override(&"font_color", _rarity_color(item.rarity))
	_name_label.visible = true

	var has_desc := item.description_key != ""
	_desc_label.text = item.description_key
	_desc_label.visible = has_desc

	var stats := _build_stats_text(item)
	_stats_label.text = stats
	_stats_label.visible = not stats.is_empty()

	_bg.reset_size()
	visible = true

func hide_tooltip() -> void:
	visible = false

func _rarity_color(rarity: StringName) -> Color:
	match rarity:
		&"magic":
			return Color(0.55, 0.75, 1.0, 1.0)
		&"rare":
			return Color(1.0, 0.85, 0.35, 1.0)
		&"unique":
			return Color(1.0, 0.6, 0.2, 1.0)
	return Color(0.95, 0.95, 0.95, 1.0)

func _build_stats_text(item: Item) -> String:
	var lines: Array[String] = []
	if item.kind == &"light":
		lines.append("%s: %d m" % [tr("ITEM_STATS_LIGHT_RANGE"), int(item.light_range)])
		lines.append("%s: %d" % [tr("ITEM_STATS_LIGHT_ENERGY"), int(item.light_energy)])
	if item.kind == &"backpack" and item.inventory_bonus > 0:
		lines.append("+%d %s" % [item.inventory_bonus, tr("ITEM_STATS_INVENTORY_BONUS")])
	if item.kind == &"belt" and item.utility_slots > 0:
		lines.append("+%d %s" % [item.utility_slots, tr("ITEM_STATS_UTILITY_SLOTS")])
	return "\n".join(lines)
