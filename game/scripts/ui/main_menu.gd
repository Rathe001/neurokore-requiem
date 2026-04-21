extends Control

const PANEL_SIZE := Vector2(220.0, 200.0)
const SETTINGS_PANEL_SIZE := Vector2(360.0, 320.0)
const BUTTON_SIZE := Vector2(168.0, 32.0)
const BUTTON_GAP := 6.0
const ROW_LABEL_WIDTH := 110.0
const OPTION_WIDTH := 190.0

var _main_panel: Control
var _settings_panel: Control
var _window_mode_option: OptionButton
var _resolution_option: OptionButton

func _ready() -> void:
	visible = false
	theme = UIThemeState.theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(&"ui_modal")
	_build_main_panel()
	_build_settings_panel()
	UIThemeState.changed.connect(_on_theme_changed)

func _on_theme_changed() -> void:
	theme = UIThemeState.theme

func open_menu() -> void:
	visible = true
	_show_main()

func close_menu() -> void:
	visible = false

func _show_main() -> void:
	_main_panel.visible = true
	_settings_panel.visible = false

func _show_settings() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true

func _build_main_panel() -> void:
	_main_panel = _make_panel(PANEL_SIZE, "MENU_TITLE")
	add_child(_main_panel)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", int(BUTTON_GAP))
	buttons.position = Vector2((PANEL_SIZE.x - BUTTON_SIZE.x) * 0.5, 48.0)
	buttons.size = Vector2(BUTTON_SIZE.x, PANEL_SIZE.y - 64.0)
	_main_panel.add_child(buttons)

	buttons.add_child(_make_button("COMMON_RESUME", _on_resume_pressed))
	buttons.add_child(_make_button("COMMON_SETTINGS", _on_settings_pressed))
	buttons.add_child(_make_button("COMMON_QUIT_TO_DESKTOP", _on_quit_pressed))

func _build_settings_panel() -> void:
	_settings_panel = _make_panel(SETTINGS_PANEL_SIZE, "MENU_SETTINGS_TITLE")
	_settings_panel.visible = false
	add_child(_settings_panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	body.position = Vector2(18.0, 48.0)
	body.size = Vector2(SETTINGS_PANEL_SIZE.x - 36.0, SETTINGS_PANEL_SIZE.y - 110.0)
	_settings_panel.add_child(body)

	body.add_child(_make_section_label("MENU_SETTINGS_DISPLAY"))
	_window_mode_option = _make_window_mode_option()
	body.add_child(_make_option_row("MENU_SETTINGS_WINDOW_MODE", _window_mode_option))
	_resolution_option = _make_resolution_option()
	body.add_child(_make_option_row("MENU_SETTINGS_RESOLUTION", _resolution_option))

	body.add_child(_make_section_label("MENU_SETTINGS_ACCESSIBILITY"))

	var back := _make_button("COMMON_BACK", _on_back_pressed)
	back.position = Vector2(
		(SETTINGS_PANEL_SIZE.x - BUTTON_SIZE.x) * 0.5,
		SETTINGS_PANEL_SIZE.y - BUTTON_SIZE.y - 18.0,
	)
	back.size = BUTTON_SIZE
	_settings_panel.add_child(back)
	_refresh_display_options()
	DisplayState.changed.connect(_refresh_display_options)

func _make_option_row(label_key: String, option: OptionButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.text = label_key
	label.theme_type_variation = &"SubLabel"
	label.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	option.custom_minimum_size = Vector2(OPTION_WIDTH, 26.0)
	row.add_child(option)
	return row

func _make_window_mode_option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_sublabel)
	option.add_item(tr("WINDOW_MODE_WINDOWED"), DisplayConfig.Mode.WINDOWED)
	option.add_item(tr("WINDOW_MODE_BORDERLESS"), DisplayConfig.Mode.BORDERLESS_FULLSCREEN)
	option.add_item(tr("WINDOW_MODE_EXCLUSIVE"), DisplayConfig.Mode.EXCLUSIVE_FULLSCREEN)
	option.item_selected.connect(_on_window_mode_selected)
	return option

func _make_resolution_option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_sublabel)
	for res in DisplayState.available_resolutions():
		option.add_item("%d × %d" % [res.x, res.y])
	option.item_selected.connect(_on_resolution_selected)
	return option

func _refresh_display_options() -> void:
	if DisplayState.config == null:
		return
	_window_mode_option.select(_window_mode_option.get_item_index(DisplayState.config.mode))
	var resolutions := DisplayState.available_resolutions()
	var current := DisplayState.config.resolution
	for i in resolutions.size():
		if resolutions[i] == current:
			_resolution_option.select(i)
			break
	_resolution_option.disabled = DisplayState.config.mode != DisplayConfig.Mode.WINDOWED

func _on_window_mode_selected(index: int) -> void:
	DisplayState.set_mode(_window_mode_option.get_item_id(index))

func _on_resolution_selected(index: int) -> void:
	var resolutions := DisplayState.available_resolutions()
	if index < 0 or index >= resolutions.size():
		return
	DisplayState.set_resolution(resolutions[index])

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SectionLabel"
	return label

func _make_panel(size: Vector2, title_text: String) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = size
	panel.size = size
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5

	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 14.0)
	title.size = Vector2(size.x, 22.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	return panel

func _make_button(text: String, callback: Callable, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.disabled = not enabled
	button.pressed.connect(callback)
	return button

func _on_resume_pressed() -> void:
	close_menu()

func _on_settings_pressed() -> void:
	_show_settings()

func _on_back_pressed() -> void:
	_show_main()

func _on_quit_pressed() -> void:
	get_tree().quit()
