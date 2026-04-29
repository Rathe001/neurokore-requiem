extends Control

const PANEL_SIZE := Vector2(220.0, 280.0)
const BUTTON_SIZE := Vector2(168.0, 32.0)
const BUTTON_GAP := 6.0

var _main_panel: Control
var _settings_panel: SettingsPanel

func _ready() -> void:
	visible = false
	theme = UIThemeState.theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(&"ui_modal")
	_build_main_panel()
	_build_settings_panel()
	_build_version_stamp()
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

func open_menu() -> void:
	get_tree().call_group(&"ui_modal", &"close_menu")
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
	buttons.add_child(_make_button("COMMON_REPORT_BUG", _on_report_bug_pressed))
	buttons.add_child(_make_button("COMMON_OPEN_LOGS", _on_open_logs_pressed))
	buttons.add_child(_make_button("COMMON_QUIT_TO_DESKTOP", _on_quit_pressed))

func _build_settings_panel() -> void:
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.back_pressed.connect(_show_main)
	add_child(_settings_panel)

func _make_panel(panel_size: Vector2, title_text: String) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = panel_size
	panel.size = panel_size
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -panel_size.x * 0.5
	panel.offset_top = -panel_size.y * 0.5
	panel.offset_right = panel_size.x * 0.5
	panel.offset_bottom = panel_size.y * 0.5

	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 14.0)
	title.size = Vector2(panel_size.x, 22.0)
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

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_report_bug_pressed() -> void:
	OS.shell_open(BuildInfo.BUG_REPORT_URL)

func _on_open_logs_pressed() -> void:
	# Logs land in user_data/logs/ but the directory may not exist on first
	# run, so fall back to the parent so the button always opens something.
	var user_dir := OS.get_user_data_dir()
	var log_dir := user_dir.path_join("logs")
	if DirAccess.dir_exists_absolute(log_dir):
		OS.shell_open(log_dir)
	else:
		OS.shell_open(user_dir)
