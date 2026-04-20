extends Control

const LOGO_TEXTURE: Texture2D = preload("res://assets/ui/logo.png")
const GAME_SCENE := "res://scenes/world/prototype_3d.tscn"

const BG_COLOR := Color(0.02, 0.02, 0.04, 1.0)

const LOGO_MAX_WIDTH := 520.0
const BUTTON_SIZE := Vector2(200.0, 36.0)
const BUTTON_GAP := 8.0

const PICK_BUTTON_SIZE := Vector2(260.0, 48.0)
const PICK_ROW_GAP := 8.0
const PICK_COL_GAP := 16.0

# All 8 class/spec combos exposed for development. Each entry becomes a
# button that sets (class_id, spec_id) on PlayerState. Empty spec_id means
# the base class without a specialization. label_key is a translation key
# resolved by Button's auto-translate at draw time.
const PICKS: Array[Dictionary] = [
	{"class_id": &"human", "spec_id": &"", "label_key": "STARTUP_PICK_HUMAN"},
	{"class_id": &"cyborg", "spec_id": &"", "label_key": "STARTUP_PICK_CYBORG"},
	{"class_id": &"human", "spec_id": &"survivalist", "label_key": "STARTUP_PICK_HUMAN_SURVIVALIST"},
	{"class_id": &"cyborg", "spec_id": &"forged", "label_key": "STARTUP_PICK_CYBORG_FORGED"},
	{"class_id": &"human", "spec_id": &"gentleman", "label_key": "STARTUP_PICK_HUMAN_GENTLEMAN"},
	{"class_id": &"cyborg", "spec_id": &"automaton", "label_key": "STARTUP_PICK_CYBORG_AUTOMATON"},
	{"class_id": &"human", "spec_id": &"enculted", "label_key": "STARTUP_PICK_HUMAN_ENCULTED"},
	{"class_id": &"cyborg", "spec_id": &"polymath", "label_key": "STARTUP_PICK_CYBORG_POLYMATH"},
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

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", int(PICK_COL_GAP))
	grid.add_theme_constant_override(&"v_separation", int(PICK_ROW_GAP))
	var rows := int(ceil(float(PICKS.size()) / 2.0))
	var total_width := PICK_BUTTON_SIZE.x * 2.0 + PICK_COL_GAP
	var total_height := PICK_BUTTON_SIZE.y * float(rows) + PICK_ROW_GAP * float(rows - 1)
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
		grid.add_child(_make_pick_button(entry))

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

func _make_pick_button(entry: Dictionary) -> Button:
	var button := Button.new()
	button.text = entry["label_key"]
	button.custom_minimum_size = PICK_BUTTON_SIZE
	button.add_theme_font_size_override(&"font_size", 14)
	var class_id: StringName = entry["class_id"]
	var spec_id: StringName = entry["spec_id"]
	button.pressed.connect(func() -> void: _on_pick_selected(class_id, spec_id))
	return button

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
