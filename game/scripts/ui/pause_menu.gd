extends Control

const PANEL_SIZE := Vector2(220.0, 200.0)
const SETTINGS_PANEL_SIZE := Vector2(340.0, 240.0)
const BUTTON_SIZE := Vector2(168.0, 32.0)
const BUTTON_GAP := 6.0

const PANEL_BG_COLOR := Color(0.04, 0.05, 0.08, 0.92)
const PANEL_BORDER_COLOR := Color(0.3, 0.5, 0.7, 0.9)
const TITLE_COLOR := Color(0.82, 0.9, 1.0, 1.0)
const LABEL_COLOR := Color(0.75, 0.82, 0.9, 1.0)
const SECTION_COLOR := Color(0.55, 0.7, 0.85, 1.0)

var _main_panel: Control
var _settings_panel: Control

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(&"ui_modal")
	_build_main_panel()
	_build_settings_panel()

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
	_main_panel = _make_panel(PANEL_SIZE, "Menu")
	add_child(_main_panel)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", int(BUTTON_GAP))
	buttons.position = Vector2((PANEL_SIZE.x - BUTTON_SIZE.x) * 0.5, 48.0)
	buttons.size = Vector2(BUTTON_SIZE.x, PANEL_SIZE.y - 64.0)
	_main_panel.add_child(buttons)

	buttons.add_child(_make_button("Resume", _on_resume_pressed))
	buttons.add_child(_make_button("Settings", _on_settings_pressed))
	buttons.add_child(_make_button("Quit to Desktop", _on_quit_pressed))

func _build_settings_panel() -> void:
	_settings_panel = _make_panel(SETTINGS_PANEL_SIZE, "Settings")
	_settings_panel.visible = false
	add_child(_settings_panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	body.position = Vector2(18.0, 48.0)
	body.size = Vector2(SETTINGS_PANEL_SIZE.x - 36.0, SETTINGS_PANEL_SIZE.y - 110.0)
	_settings_panel.add_child(body)

	body.add_child(_make_section_label("Accessibility"))

	var back := _make_button("Back", _on_back_pressed)
	back.position = Vector2(
		(SETTINGS_PANEL_SIZE.x - BUTTON_SIZE.x) * 0.5,
		SETTINGS_PANEL_SIZE.y - BUTTON_SIZE.y - 18.0,
	)
	back.size = BUTTON_SIZE
	_settings_panel.add_child(back)

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 14)
	label.add_theme_color_override(&"font_color", SECTION_COLOR)
	return label

func _make_panel(size: Vector2, title_text: String) -> Control:
	var panel := Control.new()
	panel.custom_minimum_size = size
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_bottom = size.y * 0.5

	var bg := ColorRect.new()
	bg.color = PANEL_BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bg)

	var border := ReferenceRect.new()
	border.border_color = PANEL_BORDER_COLOR
	border.border_width = 2.0
	border.editor_only = false
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(border)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(&"font_color", TITLE_COLOR)
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
	button.add_theme_font_size_override(&"font_size", 13)
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
