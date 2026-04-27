class_name PrototypeTooltip
extends Control

const SCREEN_MARGIN := Vector2(12, 12)
const MOUSE_OFFSET := Vector2(14.0, 14.0)
const PADDING_X := 8
const PADDING_Y := 6
const CONTENT_MIN_WIDTH := 200.0

var COLOR_PRIMARY:  Color = AttributeState.RELATIONSHIP_COLORS[&"primary"]
var COLOR_TEAM:     Color = AttributeState.RELATIONSHIP_COLORS[&"team"]
var COLOR_OPP_TEAM: Color = AttributeState.RELATIONSHIP_COLORS[&"opp_team"]
var COLOR_OPPOSING: Color = AttributeState.RELATIONSHIP_COLORS[&"opposing"]

var _bg: PanelContainer
var _vbox: VBoxContainer
var _text_label: Label
var _name_label: Label
var _type_label: Label
var _desc_label: Label
var _stats_label: RichTextLabel

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
	_text_label.theme_type_variation = &"BodyLabel"
	_text_label.mouse_filter = MOUSE_FILTER_IGNORE
	_vbox.add_child(_text_label)

	_name_label = Label.new()
	_name_label.theme_type_variation = &"CardTitle"
	_name_label.mouse_filter = MOUSE_FILTER_IGNORE
	_vbox.add_child(_name_label)

	_type_label = Label.new()
	_type_label.theme_type_variation = &"SmallLabel"
	_type_label.mouse_filter = MOUSE_FILTER_IGNORE
	_vbox.add_child(_type_label)

	_desc_label = Label.new()
	_desc_label.theme_type_variation = &"TooltipLabel"
	_desc_label.mouse_filter = MOUSE_FILTER_IGNORE
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vbox.add_child(_desc_label)

	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.scroll_active = false
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stats_label.mouse_filter = MOUSE_FILTER_IGNORE
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
	_type_label.add_theme_color_override(&"font_color", Color(p.text, 0.55))
	_stats_label.add_theme_color_override(&"default_color", p.text)

func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseMotion:
		_reposition((event as InputEventMouseMotion).position)

func _reposition(mouse: Vector2) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var pos := mouse + MOUSE_OFFSET
	pos.x = minf(pos.x, vp_size.x - _bg.size.x - SCREEN_MARGIN.x)
	pos.y = minf(pos.y, vp_size.y - _bg.size.y - SCREEN_MARGIN.y)
	position = pos

func show_text(text: String) -> void:
	if text.is_empty():
		hide_tooltip()
		return
	_text_label.text = text
	_text_label.visible = true
	_name_label.visible = false
	_type_label.visible = false
	_desc_label.visible = false
	_stats_label.visible = false
	_bg.reset_size()
	visible = true
	_reposition(get_viewport().get_mouse_position())

func show_item(item: Item) -> void:
	if item == null:
		hide_tooltip()
		return
	_text_label.visible = false

	_name_label.text = item.name_key
	_name_label.add_theme_color_override(&"font_color", _rarity_color(item.rarity))
	_name_label.visible = true

	var type_text := _build_type_text(item)
	_type_label.text = type_text
	_type_label.visible = not type_text.is_empty()

	var has_desc := item.description_key != ""
	_desc_label.text = item.description_key
	_desc_label.visible = has_desc

	var stats := _build_stats_text(item)
	_stats_label.text = stats
	_stats_label.visible = not stats.is_empty()

	_bg.reset_size()
	visible = true
	_reposition(get_viewport().get_mouse_position())

func show_talent_node(title: String, body: String) -> void:
	_text_label.visible = false
	_name_label.text = title
	_name_label.add_theme_color_override(&"font_color", Color(0.95, 0.95, 0.95, 1.0))
	_name_label.visible = true
	_type_label.visible = false
	_desc_label.text = body
	_desc_label.visible = true
	_stats_label.visible = false
	_bg.reset_size()
	visible = true
	_reposition(get_viewport().get_mouse_position())

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

func _build_type_text(item: Item) -> String:
	if item.main_type.is_empty():
		return ""
	if item.sub_type.is_empty():
		return item.main_type
	return "%s — %s" % [item.main_type, item.sub_type]

func _build_stats_text(item: Item) -> String:
	var lines: Array[String] = []
	if item.kind == &"optics":
		lines.append("%s: %d m" % [tr("ITEM_STATS_LIGHT_RANGE"), int(item.light_range)])
		lines.append("%s: %d" % [tr("ITEM_STATS_LIGHT_ENERGY"), int(item.light_energy)])
	if item.kind == &"backpack" and item.inventory_bonus > 0:
		lines.append("+%d %s" % [item.inventory_bonus, tr("ITEM_STATS_INVENTORY_BONUS")])
	if item.kind == &"belt" and item.utility_slots > 0:
		lines.append("+%d %s" % [item.utility_slots, tr("ITEM_STATS_UTILITY_SLOTS")])
	for stat_id: StringName in item.stat_modifiers:
		var amount: int = int(item.stat_modifiers[stat_id])
		var color := _stat_rel_color(stat_id)
		var hex := "#%s" % color.to_html(false)
		var label := _stat_display_name(stat_id)
		lines.append("[color=%s]+%d %s[/color]" % [hex, amount, label])
	return "\n".join(lines)

func _stat_rel_color(stat_id: StringName) -> Color:
	var rel := AttributeState.get_stat_relationship(stat_id, PlayerState.class_id, PlayerState.spec_id)
	if rel == &"primary":
		return COLOR_PRIMARY
	elif rel == &"team":
		return COLOR_TEAM
	var my_stat: StringName = AttributeState.get_spec_stat(PlayerState.spec_id)
	if my_stat != &"" and AttributeState.NEMESIS_STAT.get(my_stat, &"") == stat_id:
		return COLOR_OPPOSING
	return COLOR_OPP_TEAM

func _stat_display_name(stat_id: StringName) -> String:
	var key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	return tr(key) if key != &"" else (stat_id as String).capitalize()
