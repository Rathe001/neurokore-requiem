extends Control

const PANEL_POS := Vector2(16.0, 16.0)
const PANEL_SIZE := Vector2(240.0, 240.0)

const PANEL_BG_COLOR := Color(0.04, 0.05, 0.08, 0.92)
const PANEL_BORDER_COLOR := Color(0.3, 0.5, 0.7, 0.8)
const TITLE_COLOR := Color(0.82, 0.9, 1.0, 1.0)
const VALUE_COLOR := Color(0.7, 0.85, 1.0, 1.0)
const DIM_COLOR := Color(0.55, 0.65, 0.8, 1.0)

const BOOL_FIELDS: Array[Dictionary] = [
	{"label": "God Mode", "key": &"god_mode"},
	{"label": "Infinite Resource", "key": &"infinite_resource"},
	{"label": "One-shot Enemies", "key": &"one_shot_enemies"},
	{"label": "Disable Enemies", "key": &"disable_enemies"},
	{"label": "Show Attack Telegraphs", "key": &"show_attack_telegraphs"},
]

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug_panel"):
		visible = not visible
		get_viewport().set_input_as_handled()

func _build_layout() -> void:
	var panel := Control.new()
	panel.position = PANEL_POS
	panel.size = PANEL_SIZE
	panel.custom_minimum_size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var bg := ColorRect.new()
	bg.color = PANEL_BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	var border := ReferenceRect.new()
	border.border_color = PANEL_BORDER_COLOR
	border.border_width = 1.0
	border.editor_only = false
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(border)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(10.0, 8.0)
	vbox.size = Vector2(PANEL_SIZE.x - 20.0, PANEL_SIZE.y - 16.0)
	vbox.add_theme_constant_override(&"separation", 3)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Debug  [F3]"
	title.add_theme_font_size_override(&"font_size", 14)
	title.add_theme_color_override(&"font_color", TITLE_COLOR)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	for field in BOOL_FIELDS:
		_add_bool_row(vbox, field["label"], field["key"])

	vbox.add_child(HSeparator.new())

	var cfg: DebugConfig = DebugState.config
	var start_text := "—"
	var credits_text := "0"
	if cfg != null:
		start_text = str(cfg.start_position) if cfg.override_start_position else "—"
		credits_text = str(cfg.starting_credits)
	_add_readonly_row(vbox, "Start pos", start_text)
	_add_readonly_row(vbox, "Start credits", credits_text)

func _add_bool_row(parent: VBoxContainer, label_text: String, key: StringName) -> void:
	var check := CheckBox.new()
	check.text = label_text
	check.add_theme_font_size_override(&"font_size", 12)
	check.button_pressed = _get_bool(key)
	check.toggled.connect(func(pressed: bool) -> void: _set_bool(key, pressed))
	parent.add_child(check)

func _add_readonly_row(parent: VBoxContainer, key_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var k := Label.new()
	k.text = key_text + ":"
	k.add_theme_font_size_override(&"font_size", 11)
	k.add_theme_color_override(&"font_color", DIM_COLOR)
	k.custom_minimum_size = Vector2(96.0, 0.0)
	row.add_child(k)
	var v := Label.new()
	v.text = value_text
	v.add_theme_font_size_override(&"font_size", 11)
	v.add_theme_color_override(&"font_color", VALUE_COLOR)
	row.add_child(v)
	parent.add_child(row)

func _get_bool(key: StringName) -> bool:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return false
	return bool(cfg.get(key))

func _set_bool(key: StringName, value: bool) -> void:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return
	cfg.set(key, value)
