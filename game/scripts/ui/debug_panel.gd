extends Control

const PANEL_POS := Vector2(12.0, 44.0)
const PANEL_SIZE := Vector2(170.0, 224.0)

const STAT_KEY_WIDTH := 70.0

const BOOL_FIELDS: Array[Dictionary] = [
	{"label_key": "DEBUG_GOD_MODE", "key": &"god_mode"},
	{"label_key": "DEBUG_INFINITE_RESOURCE", "key": &"infinite_resource"},
	{"label_key": "DEBUG_ONESHOT_ENEMIES", "key": &"one_shot_enemies"},
	{"label_key": "DEBUG_DISABLE_ENEMIES", "key": &"disable_enemies"},
	{"label_key": "DEBUG_SHOW_TELEGRAPHS", "key": &"show_attack_telegraphs"},
	{"label_key": "DEBUG_SHOW_OVERLAY", "key": &"show_debug_overlay"},
]

# (option label, RetroFilterOverlay.RetroMode value). Order = dropdown order.
const RETRO_FILTER_OPTIONS: Array[Array] = [
	["DEBUG_FILTER_OFF", 0],
	["DEBUG_FILTER_VHS", 1],
	["DEBUG_FILTER_SECURITY", 2],
	["DEBUG_FILTER_NIGHTVIS", 3],
	["DEBUG_FILTER_THERMAL", 4],
	["DEBUG_FILTER_CONCUSSED", 5],
	["DEBUG_FILTER_DRUNK", 6],
	["DEBUG_FILTER_LOWHP", 7],
	["DEBUG_FILTER_HALLUCINATION", 8],
	["DEBUG_FILTER_GLITCH", 9],
	["DEBUG_FILTER_NOIR", 10],
	["DEBUG_FILTER_INVERTED", 11],
]

func _ready() -> void:
	visible = false
	theme = UIThemeState.theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	UIThemeState.changed.connect(_on_theme_changed)


func _exit_tree() -> void:
	UIThemeState.changed.disconnect(_on_theme_changed)


func _on_theme_changed() -> void:
	theme = UIThemeState.theme

func _unhandled_input(event: InputEvent) -> void:
	if not BuildInfo.dev_tools_enabled():
		return
	if event.is_action_pressed(&"toggle_debug_panel"):
		visible = not visible
		get_viewport().set_input_as_handled()

func _build_layout() -> void:
	var p := UIThemeState.palette
	var panel := Panel.new()
	panel.position = PANEL_POS
	panel.size = PANEL_SIZE
	panel.custom_minimum_size = PANEL_SIZE
	panel.add_theme_stylebox_override(&"panel", _thin_panel_style(p))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(8.0, 6.0)
	vbox.size = Vector2(PANEL_SIZE.x - 16.0, PANEL_SIZE.y - 12.0)
	vbox.add_theme_constant_override(&"separation", 2)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "DEBUG_TITLE"
	title.theme_type_variation = &"BodyLabel"
	title.add_theme_color_override(&"font_color", p.text)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	for field in BOOL_FIELDS:
		_add_bool_row(vbox, field["label_key"], field["key"])

	vbox.add_child(HSeparator.new())
	_add_retro_filter_row(vbox)
	vbox.add_child(HSeparator.new())

	var cfg: DebugConfig = DebugState.config
	var start_text := "—"
	var credits_text := "0"
	if cfg != null:
		start_text = str(cfg.start_position) if cfg.override_start_position else "—"
		credits_text = str(cfg.starting_credits)
	_add_readonly_row(vbox, "DEBUG_START_POS", start_text)
	_add_readonly_row(vbox, "DEBUG_START_CR", credits_text)

func _add_bool_row(parent: VBoxContainer, label_key: String, key: StringName) -> void:
	var check := CheckBox.new()
	check.text = label_key
	check.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_tooltip)
	check.button_pressed = _get_bool(key)
	check.toggled.connect(func(pressed: bool) -> void: _set_bool(key, pressed))
	parent.add_child(check)

func _add_retro_filter_row(parent: VBoxContainer) -> void:
	var p := UIThemeState.palette
	var label := Label.new()
	label.text = "DEBUG_RETRO_FILTER"
	label.theme_type_variation = &"SmallLabel"
	label.add_theme_color_override(&"font_color", p.text)
	parent.add_child(label)

	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_tooltip)
	var current: int = _get_int(&"retro_filter_mode")
	var current_index: int = 0
	for i in RETRO_FILTER_OPTIONS.size():
		var entry: Array = RETRO_FILTER_OPTIONS[i]
		option.add_item(entry[0], int(entry[1]))
		if int(entry[1]) == current:
			current_index = i
	option.selected = current_index
	option.item_selected.connect(_on_retro_filter_selected.bind(option))
	parent.add_child(option)

func _on_retro_filter_selected(_index: int, option: OptionButton) -> void:
	# `selected` already updated by Godot; we just need the corresponding mode
	# id (the "metadata" we attached via add_item's id parameter).
	var mode: int = option.get_selected_id()
	_set_int(&"retro_filter_mode", mode)

func _get_int(key: StringName) -> int:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return 0
	return int(cfg.get(key))

func _set_int(key: StringName, value: int) -> void:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return
	cfg.set(key, value)
	# Notify any listeners (RetroFilterOverlay subscribes to this) — bool
	# toggles don't currently emit_changed, but the retro overlay needs to
	# react live to dropdown picks.
	cfg.emit_changed()

func _add_readonly_row(parent: VBoxContainer, label_key: String, value_text: String) -> void:
	var p := UIThemeState.palette
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var k := Label.new()
	k.text = label_key
	k.theme_type_variation = &"SmallLabel"
	k.custom_minimum_size = Vector2(STAT_KEY_WIDTH, 0.0)
	row.add_child(k)
	var v := Label.new()
	v.text = value_text
	v.theme_type_variation = &"SmallLabel"
	v.add_theme_color_override(&"font_color", p.text)
	row.add_child(v)
	parent.add_child(row)

func _thin_panel_style(p: UIThemeConfig) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = p.panel_bg
	s.border_color = Color(p.panel_border.r, p.panel_border.g, p.panel_border.b, 0.8)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	return s

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
