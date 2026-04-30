class_name ClassCardBuilder
extends RefCounted

const CARD_SIZE := Vector2(400.0, 128.0)
const PORTRAIT_SIZE := 64.0

static func build(entry: Dictionary, on_pressed: Callable) -> Button:
	var class_id: StringName = entry["class_id"]
	var spec_id: StringName = entry["spec_id"]
	var accent: Color = UIThemeState.get_palette_for(class_id, spec_id).accent

	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE

	var bg_color := Color(accent.r * 0.12, accent.g * 0.12, accent.b * 0.12, 0.92)
	var bg_hover := Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.96)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style_normal.set_border_width_all(1)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = bg_hover
	style_hover.border_color = accent
	style_hover.set_border_width_all(2)

	card.add_theme_stylebox_override(&"normal", style_normal)
	card.add_theme_stylebox_override(&"hover", style_hover)
	card.add_theme_stylebox_override(&"pressed", style_hover)
	card.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	card.add_theme_stylebox_override(&"disabled", style_normal)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_top", 10)
	margin.add_theme_constant_override(&"margin_right", 10)
	margin.add_theme_constant_override(&"margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	# Portrait placeholder
	var portrait_wrap := Control.new()
	portrait_wrap.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(portrait_wrap)

	var portrait := ColorRect.new()
	portrait.color = Color(accent.r, accent.g, accent.b, 0.85)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_wrap.add_child(portrait)

	var glyph_label := Label.new()
	glyph_label.text = entry["glyph"]
	glyph_label.theme_type_variation = &"PortraitGlyph"
	glyph_label.add_theme_color_override(&"font_color", Color(0.0, 0.0, 0.0, 0.75))
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_wrap.add_child(glyph_label)

	# Text column
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 3)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var name_label := Label.new()
	name_label.text = entry["label_key"]
	name_label.theme_type_variation = &"CardTitle"
	name_label.add_theme_color_override(&"font_color", accent)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = TranslationServer.translate(entry["backstory"])
	desc_label.theme_type_variation = &"SmallLabel"
	desc_label.add_theme_font_size_override(&"font_size", 9)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	var hint_label := RichTextLabel.new()
	hint_label.bbcode_enabled = true
	hint_label.text = AttributeState.get_scaling_hint(class_id, spec_id)
	hint_label.fit_content = true
	hint_label.scroll_active = false
	hint_label.add_theme_font_size_override(&"normal_font_size", 8)
	hint_label.add_theme_color_override(&"default_color", Color(1.0, 1.0, 1.0, 0.45))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hint_label)

	# Stat tags — bottom-right corner
	var stats_overlay := Control.new()
	stats_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(stats_overlay)

	var tags_row := HBoxContainer.new()
	tags_row.add_theme_constant_override(&"separation", 4)
	tags_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags_row.anchor_left = 0.0
	tags_row.anchor_right = 1.0
	tags_row.anchor_top = 1.0
	tags_row.anchor_bottom = 1.0
	tags_row.offset_left = 8.0
	tags_row.offset_right = -8.0
	tags_row.offset_top = -18.0
	tags_row.offset_bottom = -5.0
	stats_overlay.add_child(tags_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags_row.add_child(spacer)

	var pos_tag := PanelContainer.new()
	pos_tag.theme_type_variation = &"StatPosTag"
	pos_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags_row.add_child(pos_tag)
	var plus_stat := Label.new()
	plus_stat.text = "+" + TranslationServer.translate(entry["stat"])
	plus_stat.theme_type_variation = &"StatLabel"
	plus_stat.add_theme_color_override(&"font_color", Color(0.35, 0.9, 0.45, 1.0))
	plus_stat.add_theme_font_size_override(&"font_size", 7)
	plus_stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pos_tag.add_child(plus_stat)

	var neg_tag := PanelContainer.new()
	neg_tag.theme_type_variation = &"StatNegTag"
	neg_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags_row.add_child(neg_tag)
	var minus_opp := Label.new()
	minus_opp.text = "-" + TranslationServer.translate(entry["opposes"])
	minus_opp.theme_type_variation = &"StatLabel"
	minus_opp.add_theme_color_override(&"font_color", Color(0.9, 0.3, 0.3, 0.85))
	minus_opp.add_theme_font_size_override(&"font_size", 7)
	minus_opp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	neg_tag.add_child(minus_opp)

	card.pressed.connect(on_pressed)
	return card
