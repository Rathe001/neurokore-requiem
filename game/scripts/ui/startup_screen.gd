extends Control

const LOGO_TEXTURE: Texture2D = preload("res://assets/ui/logo.png")
const GAME_SCENE := "res://scenes/world/prototype_3d.tscn"

const BG_COLOR := Color(0.02, 0.02, 0.04, 1.0)
const LOGO_MAX_WIDTH := 520.0
const BUTTON_SIZE := Vector2(200.0, 36.0)
const BUTTON_GAP := 8.0
const CARD_SIZE := Vector2(400.0, 110.0)
const CARD_COL_GAP := 12.0
const CARD_ROW_GAP := 8.0
const PORTRAIT_SIZE := 80.0

const PICKS: Array[Dictionary] = [
	{
		"class_id": &"human", "spec_id": &"",
		"label_key": "STARTUP_PICK_HUMAN",
		"glyph": "H",
		"accent": Color(0.65, 0.45, 0.25, 1),
		"backstory": "Unaugmented and proud of it. Survives on wit, adaptability, and the stubborn refusal of flesh to become obsolete.",
	},
	{
		"class_id": &"cyborg", "spec_id": &"",
		"label_key": "STARTUP_PICK_CYBORG",
		"glyph": "C",
		"accent": Color(0.3, 0.85, 1.0, 1),
		"backstory": "Half human, half machine — all pragmatism. Whether by choice or necessity, you've crossed the threshold most only dream about.",
	},
	{
		"class_id": &"human", "spec_id": &"survivalist",
		"label_key": "STARTUP_PICK_HUMAN_SURVIVALIST",
		"glyph": "S",
		"accent": Color(0.7, 0.85, 0.35, 1),
		"backstory": "The city tried to kill you. It failed. You've made weapons from wreckage and learned that the best tool is the one you have right now.",
	},
	{
		"class_id": &"cyborg", "spec_id": &"forged",
		"label_key": "STARTUP_PICK_CYBORG_FORGED",
		"glyph": "F",
		"accent": Color(0.9, 0.25, 0.2, 1),
		"backstory": "You didn't stop at practical. Every limb, every organ — an opportunity for something harder. The flesh that remains is just scaffolding.",
	},
	{
		"class_id": &"human", "spec_id": &"gentleman",
		"label_key": "STARTUP_PICK_HUMAN_GENTLEMAN",
		"glyph": "G",
		"accent": Color(0.95, 0.92, 0.8, 1),
		"backstory": "Composed under pressure. Lethal in formal wear. You've turned restraint into a weapon — your enemies don't see it coming until it's done.",
	},
	{
		"class_id": &"cyborg", "spec_id": &"automaton",
		"label_key": "STARTUP_PICK_CYBORG_AUTOMATON",
		"glyph": "A",
		"accent": Color(0.55, 0.78, 0.85, 1),
		"backstory": "Precision. Efficiency. You've outsourced instinct to systems that never panic. Your drone network sees what you don't.",
	},
	{
		"class_id": &"human", "spec_id": &"enculted",
		"label_key": "STARTUP_PICK_HUMAN_ENCULTED",
		"glyph": "E",
		"accent": Color(0.78, 0.35, 0.85, 1),
		"backstory": "You found something in the dark and it found you back. What others call ambition, you call clarity. What they call madness, you call perspective.",
	},
	{
		"class_id": &"cyborg", "spec_id": &"polymath",
		"label_key": "STARTUP_PICK_CYBORG_POLYMATH",
		"glyph": "P",
		"accent": Color(0.95, 0.9, 0.3, 1),
		"backstory": "Where others specialize, you synthesize. Arcane theory meets cybernetic precision. Your enemies can't prepare for what they can't categorize.",
	},
]

var _main_panel: Control
var _class_panel: Control

func _ready() -> void:
	theme = UIThemeState.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main_panel()
	_build_class_panel()
	_show_main()
	UIThemeState.changed.connect(_on_theme_changed)

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
	title.add_theme_font_size_override(&"font_size", 28)
	title.add_theme_color_override(&"font_color", UIThemeState.palette.text)
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
	grid.offset_top = -total_height * 0.5 + 10.0
	grid.offset_bottom = total_height * 0.5 + 10.0
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
	var accent: Color = entry["accent"]
	var class_id: StringName = entry["class_id"]
	var spec_id: StringName = entry["spec_id"]

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
	glyph_label.add_theme_font_size_override(&"font_size", 32)
	glyph_label.add_theme_color_override(&"font_color", Color(0.0, 0.0, 0.0, 0.75))
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_wrap.add_child(glyph_label)

	# Text
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 5)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var name_label := Label.new()
	name_label.text = entry["label_key"]
	name_label.add_theme_font_size_override(&"font_size", 15)
	name_label.add_theme_color_override(&"font_color", accent)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = entry["backstory"]
	desc_label.add_theme_font_size_override(&"font_size", 10)
	desc_label.add_theme_color_override(&"font_color", Color(0.78, 0.78, 0.78, 0.85))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	card.pressed.connect(func() -> void: _on_pick_selected(class_id, spec_id))
	return card

func _make_button(text: String, callback: Callable, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override(&"font_size", 14)
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
