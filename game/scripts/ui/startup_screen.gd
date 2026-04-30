extends Control

const LOGO_TEXTURE: Texture2D = preload("res://assets/ui/logo.png")
const GAME_SCENE := "res://scenes/world/prototype_3d.tscn"

const BG_COLOR := Color(0.02, 0.02, 0.04, 1.0)
const LOGO_MAX_WIDTH := 520.0
const BUTTON_SIZE := Vector2(200.0, 36.0)
const BUTTON_GAP := 8.0
const CARD_COL_GAP := 12.0
const CARD_ROW_GAP := 6.0

const PICKS: Array[Dictionary] = [
	{"class_id": &"analog", "spec_id": &"", "label_key": "STARTUP_PICK_ANALOG", "glyph": "H", "stat": "STAT_SOUL", "opposes": "STAT_INTERFACE", "backstory": "STARTUP_BACKSTORY_ANALOG"},
	{"class_id": &"cyborg", "spec_id": &"", "label_key": "STARTUP_PICK_CYBORG", "glyph": "C", "stat": "STAT_INTERFACE", "opposes": "STAT_SOUL", "backstory": "STARTUP_BACKSTORY_CYBORG"},
]

const GENDER_CARD_SIZE := Vector2(300.0, 80.0)
const GENDER_ACCENT_MALE := Color(0.4, 0.6, 0.9, 1.0)
const GENDER_ACCENT_FEMALE := Color(0.9, 0.45, 0.65, 1.0)

var _main_panel: Control
var _gender_panel: Control
var _class_panel: Control
var _settings_panel: SettingsPanel

func _ready() -> void:
	theme = UIThemeState.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main_panel()
	_build_gender_panel()
	_build_class_panel()
	_build_settings_panel()
	_build_version_stamp()
	_show_main()
	UIThemeState.changed.connect(_on_theme_changed)

func _build_settings_panel() -> void:
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.back_pressed.connect(_show_main)
	add_child(_settings_panel)

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
	buttons.offset_top = -280.0
	buttons.offset_bottom = -60.0
	_main_panel.add_child(buttons)

	buttons.add_child(_make_button("COMMON_NEW_GAME", _on_new_game_pressed))
	buttons.add_child(_make_button("COMMON_OPTIONS", _on_options_pressed))
	buttons.add_child(_make_button("COMMON_REPORT_BUG", _on_report_bug_pressed))
	buttons.add_child(_make_button("COMMON_OPEN_LOGS", _on_open_logs_pressed))
	buttons.add_child(_make_button("COMMON_QUIT", _on_quit_pressed))

func _build_gender_panel() -> void:
	_gender_panel = Control.new()
	_gender_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gender_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gender_panel)

	var title := Label.new()
	title.text = "STARTUP_TITLE_GENDER"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 60.0
	title.offset_bottom = 96.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gender_panel.add_child(title)

	var total_width := GENDER_CARD_SIZE.x * 2.0 + CARD_COL_GAP
	var vbox := HBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", int(CARD_COL_GAP))
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -total_width * 0.5
	vbox.offset_right = total_width * 0.5
	vbox.offset_top = -GENDER_CARD_SIZE.y * 0.5
	vbox.offset_bottom = GENDER_CARD_SIZE.y * 0.5
	_gender_panel.add_child(vbox)

	vbox.add_child(_make_gender_card(&"male", "STARTUP_GENDER_MALE", "STARTUP_GENDER_DESC_MALE", GENDER_ACCENT_MALE))
	vbox.add_child(_make_gender_card(&"female", "STARTUP_GENDER_FEMALE", "STARTUP_GENDER_DESC_FEMALE", GENDER_ACCENT_FEMALE))

	var back := _make_button("COMMON_BACK", _on_gender_back_pressed)
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -BUTTON_SIZE.x * 0.5
	back.offset_right = BUTTON_SIZE.x * 0.5
	back.offset_top = -80.0
	back.offset_bottom = -44.0
	_gender_panel.add_child(back)

func _make_gender_card(gender_id: StringName, label_key: String, desc_key: String, accent: Color) -> Button:
	var card := Button.new()
	card.custom_minimum_size = GENDER_CARD_SIZE
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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 4)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var name_label := Label.new()
	name_label.text = label_key
	name_label.theme_type_variation = &"CardTitle"
	name_label.add_theme_color_override(&"font_color", accent)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = desc_key
	desc_label.theme_type_variation = &"SmallLabel"
	desc_label.add_theme_font_size_override(&"font_size", 9)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0, 0.5))
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_label)

	card.pressed.connect(func() -> void: _on_gender_selected(gender_id))
	return card

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
	var total_width := ClassCardBuilder.CARD_SIZE.x * 2.0 + CARD_COL_GAP
	var total_height := ClassCardBuilder.CARD_SIZE.y * float(rows) + CARD_ROW_GAP * float(rows - 1)

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
		var cid: StringName = entry["class_id"]
		var sid: StringName = entry["spec_id"]
		grid.add_child(ClassCardBuilder.build(entry, func() -> void: _on_pick_selected(cid, sid)))

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

func _make_button(text: String, callback: Callable, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.disabled = not enabled
	button.pressed.connect(callback)
	return button

func _hide_all() -> void:
	_main_panel.visible = false
	_gender_panel.visible = false
	_class_panel.visible = false
	_settings_panel.visible = false

func _show_main() -> void:
	_hide_all()
	_main_panel.visible = true

func _show_gender_select() -> void:
	_hide_all()
	_gender_panel.visible = true

func _show_class_select() -> void:
	_hide_all()
	_class_panel.visible = true

func _show_settings() -> void:
	_hide_all()
	_settings_panel.visible = true

func _on_new_game_pressed() -> void:
	_show_gender_select()

func _on_options_pressed() -> void:
	_show_settings()

func _on_gender_selected(gender_id: StringName) -> void:
	PlayerState.gender = gender_id
	_show_class_select()

func _on_gender_back_pressed() -> void:
	_show_main()

func _on_back_pressed() -> void:
	_show_gender_select()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_report_bug_pressed() -> void:
	OS.shell_open(BuildInfo.BUG_REPORT_URL)

func _on_open_logs_pressed() -> void:
	var user_dir := OS.get_user_data_dir()
	var log_dir := user_dir.path_join("logs")
	if DirAccess.dir_exists_absolute(log_dir):
		OS.shell_open(log_dir)
	else:
		OS.shell_open(user_dir)

func _on_pick_selected(class_id: StringName, spec_id: StringName) -> void:
	PlayerState.set_class_and_spec(class_id, spec_id)
	get_tree().change_scene_to_file(GAME_SCENE)
