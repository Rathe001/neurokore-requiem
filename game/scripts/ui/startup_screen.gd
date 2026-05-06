extends Control

const LOGO_TEXTURE: Texture2D = preload("res://assets/ui/logo-transparent.png")
const BG_TEXTURE: Texture2D = preload("res://assets/ui/texture2.png")
const GAME_SCENE := "res://scenes/world/level_shell.tscn"
const LOGO_MAX_WIDTH := 520.0
const BUTTON_SIZE := Vector2(200.0, 36.0)
const BUTTON_GAP := 8.0

var _main_panel: Control
var _creation_panel: CharacterCreationPanel
var _continue_panel: ContinuePanel
var _settings_panel: SettingsPanel

func _ready() -> void:
	theme = UIThemeState.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main_panel()
	_build_creation_panel()
	_build_continue_panel()
	_build_settings_panel()
	_build_version_stamp()
	_show_main()
	UIThemeState.changed.connect(_on_theme_changed)

func _build_settings_panel() -> void:
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.back_pressed.connect(_show_main)
	add_child(_settings_panel)

func _build_creation_panel() -> void:
	_creation_panel = CharacterCreationPanel.new()
	_creation_panel.visible = false
	_creation_panel.back_pressed.connect(_show_main)
	_creation_panel.start_pressed.connect(_on_start_pressed)
	add_child(_creation_panel)


func _build_continue_panel() -> void:
	_continue_panel = ContinuePanel.new()
	_continue_panel.visible = false
	_continue_panel.back_pressed.connect(_show_main)
	_continue_panel.character_selected.connect(_on_character_selected)
	add_child(_continue_panel)

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
	var bg := TextureRect.new()
	bg.texture = BG_TEXTURE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
	# Centre the logo vertically in the gap above the button stack. Buttons sit
	# 400px above the bottom (anchor_bottom=1.0, offset_top=-400), so the gap
	# spans (0, H-400). Mid = H/2 - 200. Anchoring at 0.5 ± half-height with a
	# -200 shift keeps the logo centred regardless of viewport aspect (which
	# matters because stretch mode is "expand" — taller viewports show more
	# vertical canvas space).
	var logo_h := LOGO_MAX_WIDTH * 0.55
	logo.anchor_top = 0.5
	logo.anchor_bottom = 0.5
	logo.offset_left = -LOGO_MAX_WIDTH * 0.5
	logo.offset_right = LOGO_MAX_WIDTH * 0.5
	logo.offset_top = -200.0 - logo_h * 0.5
	logo.offset_bottom = -200.0 + logo_h * 0.5
	_main_panel.add_child(logo)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", int(BUTTON_GAP))
	buttons.anchor_left = 0.5
	buttons.anchor_right = 0.5
	buttons.anchor_top = 1.0
	buttons.anchor_bottom = 1.0
	buttons.offset_left = -BUTTON_SIZE.x * 0.5
	buttons.offset_right = BUTTON_SIZE.x * 0.5
	buttons.offset_top = -400.0
	buttons.offset_bottom = -180.0
	_main_panel.add_child(buttons)

	if SaveManager.has_any_saves():
		buttons.add_child(_make_button("COMMON_CONTINUE", _on_continue_pressed))
	buttons.add_child(_make_button("COMMON_NEW_GAME", _on_new_game_pressed))
	buttons.add_child(_make_button("COMMON_OPTIONS", _on_options_pressed))
	buttons.add_child(_make_button("COMMON_REPORT_BUG", _on_report_bug_pressed))
	buttons.add_child(_make_button("COMMON_OPEN_LOGS", _on_open_logs_pressed))
	buttons.add_child(_make_button("COMMON_QUIT", _on_quit_pressed))

func _make_button(text: String, callback: Callable, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.disabled = not enabled
	button.pressed.connect(callback)
	return button

func _hide_all() -> void:
	_main_panel.visible = false
	_creation_panel.visible = false
	_continue_panel.visible = false
	_settings_panel.visible = false

func _show_main() -> void:
	_hide_all()
	_main_panel.visible = true

func _show_creation() -> void:
	_hide_all()
	_creation_panel.reset_state()
	_creation_panel.visible = true

func _show_settings() -> void:
	_hide_all()
	_settings_panel.visible = true

func _on_continue_pressed() -> void:
	_hide_all()
	_continue_panel.refresh()
	_continue_panel.visible = true


func _on_character_selected(save_id: String) -> void:
	if SaveManager.load_game(save_id):
		get_tree().change_scene_to_file(GAME_SCENE)


func _on_new_game_pressed() -> void:
	_show_creation()

func _on_options_pressed() -> void:
	_show_settings()

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

func _on_start_pressed() -> void:
	# Reset all autoload state so no data from a previous character leaks
	# into the new one (e.g. after hardcore death + return to menu).
	PlayerState.reset()
	InventoryState.reset()
	# CharacterCreationPanel already wrote class_id, spec_id, gender,
	# avatar_id, player_name, and hardcore into PlayerState before emitting
	# start_pressed — re-apply them after the reset.
	_creation_panel.apply_to_player_state()
	PlayerState.character_id = _generate_uuid()
	SaveManager.save_game()
	get_tree().change_scene_to_file(GAME_SCENE)


static func _generate_uuid() -> String:
	var hex := "0123456789abcdef"
	var uuid := ""
	for i in 32:
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		uuid += hex[randi() % 16]
	return uuid
