extends Control

const LOGO_TEXTURE: Texture2D = preload("res://assets/ui/logo.png")
const GAME_SCENE := "res://scenes/world/prototype_3d.tscn"

const BG_COLOR := Color(0.02, 0.02, 0.04, 1.0)
const LOGO_MAX_WIDTH := 520.0
const BUTTON_SIZE := Vector2(200.0, 36.0)
const BUTTON_GAP := 8.0
const CARD_SIZE := Vector2(400.0, 88.0)
const CARD_COL_GAP := 12.0
const CARD_ROW_GAP := 6.0
const PORTRAIT_SIZE := 64.0

const PICKS: Array[Dictionary] = [
	{"class_id": &"analog",  "spec_id": &"",           "label_key": "STARTUP_PICK_ANALOG",              "glyph": "H", "stat": "STAT_SOUL",         "opposes": "STAT_INTERFACE",    "backstory": "STARTUP_BACKSTORY_ANALOG"},
	{"class_id": &"cyborg", "spec_id": &"",           "label_key": "STARTUP_PICK_CYBORG",             "glyph": "C", "stat": "STAT_INTERFACE",     "opposes": "STAT_SOUL",         "backstory": "STARTUP_BACKSTORY_CYBORG"},
	{"class_id": &"analog",  "spec_id": &"gentleman",  "label_key": "STARTUP_PICK_ANALOG_GENTLEMAN",    "glyph": "G", "stat": "STAT_ORTHODOXY",     "opposes": "STAT_DEVIATION",    "backstory": "STARTUP_BACKSTORY_GENTLEMAN"},
	{"class_id": &"cyborg", "spec_id": &"forged",     "label_key": "STARTUP_PICK_CYBORG_FORGED",      "glyph": "F", "stat": "STAT_DEVIATION",     "opposes": "STAT_ORTHODOXY",    "backstory": "STARTUP_BACKSTORY_FORGED"},
	{"class_id": &"analog",  "spec_id": &"survivalist","label_key": "STARTUP_PICK_ANALOG_SURVIVALIST",  "glyph": "S", "stat": "STAT_INGENUITY",     "opposes": "STAT_OPTIMIZATION", "backstory": "STARTUP_BACKSTORY_SURVIVALIST"},
	{"class_id": &"cyborg", "spec_id": &"automaton",  "label_key": "STARTUP_PICK_CYBORG_AUTOMATON",   "glyph": "A", "stat": "STAT_OPTIMIZATION",  "opposes": "STAT_INGENUITY",    "backstory": "STARTUP_BACKSTORY_AUTOMATON"},
	{"class_id": &"analog",  "spec_id": &"enculted",   "label_key": "STARTUP_PICK_ANALOG_ENCULTED",     "glyph": "E", "stat": "STAT_AMBITION",      "opposes": "STAT_CLARITY",      "backstory": "STARTUP_BACKSTORY_ENCULTED"},
	{"class_id": &"cyborg", "spec_id": &"polymath",   "label_key": "STARTUP_PICK_CYBORG_POLYMATH",    "glyph": "P", "stat": "STAT_CLARITY",       "opposes": "STAT_AMBITION",     "backstory": "STARTUP_BACKSTORY_POLYMATH"},
]

var _main_panel: Control
var _class_panel: Control

func _ready() -> void:
	theme = UIThemeState.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main_panel()
	_build_class_panel()
	_build_version_stamp()
	_show_main()
	UIThemeState.changed.connect(_on_theme_changed)

func _build_version_stamp() -> void:
	var label := Label.new()
	label.text = BuildInfo.display_string()
	label.theme_type_variation = &"SmallLabel"
	label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0, 0.35))
	label.add_theme_font_size_override(&"font_size", 9)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 1.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = -220.0
	label.offset_right = -8.0
	label.offset_top = -22.0
	label.offset_bottom = -6.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)

func _on_theme_changed() -> void:
	theme = UIThemeState.theme

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

func _build_main_panel() -> void:
	_main_panel = Control.new()
	_main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main_panel)

	var logo := TextureRect.new()
	logo.texture = LOGO_TEXTURE
	logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.anchor_left = 0.5
	logo.anchor_right = 0.5
	logo.anchor_top = 0.0
	logo.offset_left = -LOGO_MAX_WIDTH * 0.5
	logo.offset_right = LOGO_MAX_WIDTH * 0.5
	logo.offset_top = 60.0
	logo.offset_bottom = 60.0 + LOGO_MAX_WIDTH * 0.55
	_main_panel.add_child(logo)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", int(BUTTON_GAP))
	buttons.anchor_left = 0.5
	buttons.anchor_right = 0.5
	buttons.anchor_top = 1.0
	buttons.anchor_bottom = 1.0
	buttons.offset_left = -BUTTON_SIZE.x * 0.5
	buttons.offset_right = BUTTON_SIZE.x * 0.5
	buttons.offset_top = -200.0
	buttons.offset_bottom = -60.0
	_main_panel.add_child(buttons)

	buttons.add_child(_make_button("COMMON_NEW_GAME", _on_new_game_pressed))
	buttons.add_child(_make_button("COMMON_OPTIONS", _on_options_pressed, false))
	buttons.add_child(_make_button("COMMON_QUIT", _on_quit_pressed))

func _build_class_panel() -> void:
	_class_panel = Control.new()
	_class_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_class_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_class_panel)

	var title := Label.new()
	title.text = "STARTUP_TITLE"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 60.0
	title.offset_bottom = 96.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_class_panel.add_child(title)

	var rows := int(ceil(float(PICKS.size()) / 2.0))
	var total_width := CARD_SIZE.x * 2.0 + CARD_COL_GAP
	var total_height := CARD_SIZE.y * float(rows) + CARD_ROW_GAP * float(rows - 1)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", int(CARD_COL_GAP))
	grid.add_theme_constant_override(&"v_separation", int(CARD_ROW_GAP))
	grid.anchor_left = 0.5
	grid.anchor_right = 0.5
	grid.anchor_top = 0.5
	grid.anchor_bottom = 0.5
	grid.offset_left = -total_width * 0.5
	grid.offset_right = total_width * 0.5
	grid.offset_top = -total_height * 0.5 + 24.0
	grid.offset_bottom = total_height * 0.5 + 24.0
	_class_panel.add_child(grid)

	for entry in PICKS:
		grid.add_child(_make_pick_card(entry))

	var back := _make_button("COMMON_BACK", _on_back_pressed)
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -BUTTON_SIZE.x * 0.5
	back.offset_right = BUTTON_SIZE.x * 0.5
	back.offset_top = -80.0
	back.offset_bottom = -44.0
	_class_panel.add_child(back)

func _make_pick_card(entry: Dictionary) -> Button:
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
	margin.add_theme_constant_override(&"margin_bottom", 10)
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

	# Text
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
	desc_label.text = tr(entry["backstory"])
	desc_label.theme_type_variation = &"SmallLabel"
	desc_label.add_theme_font_size_override(&"font_size", 9)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.max_lines_visible = 2
	desc_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	# Stats overlay — bottom-right corner, single row
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
	plus_stat.text = "+" + tr(entry["stat"])
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
	minus_opp.text = "-" + tr(entry["opposes"])
	minus_opp.theme_type_variation = &"StatLabel"
	minus_opp.add_theme_color_override(&"font_color", Color(0.9, 0.3, 0.3, 0.85))
	minus_opp.add_theme_font_size_override(&"font_size", 7)
	minus_opp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	neg_tag.add_child(minus_opp)

	card.pressed.connect(func() -> void: _on_pick_selected(class_id, spec_id))
	return card

func _make_button(text: String, callback: Callable, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.disabled = not enabled
	button.pressed.connect(callback)
	return button

func _show_main() -> void:
	_main_panel.visible = true
	_class_panel.visible = false

func _show_class_select() -> void:
	_main_panel.visible = false
	_class_panel.visible = true

func _on_new_game_pressed() -> void:
	_show_class_select()

func _on_options_pressed() -> void:
	pass

func _on_back_pressed() -> void:
	_show_main()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_pick_selected(class_id: StringName, spec_id: StringName) -> void:
	PlayerState.set_class_and_spec(class_id, spec_id)
	get_tree().change_scene_to_file(GAME_SCENE)
