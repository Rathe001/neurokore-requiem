extends Control

const LOGO_TEXTURE: Texture2D = preload("res://assets/ui/logo-transparent.png")
const BG_TEXTURE: Texture2D = preload("res://assets/ui/texture2.png")
const GAME_SCENE := "res://scenes/world/level_shell.tscn"
const LOGO_MAX_WIDTH := 520.0
const BUTTON_SIZE := Vector2(200.0, 36.0)
const BUTTON_GAP := 8.0

var _main_panel: Control
var _creation_panel: CharacterCreationPanel
var _single_player_panel: ContinuePanel
var _settings_panel: SettingsPanel
var _multiplayer_panel: MultiplayerPanel
var _create_lobby_panel: CreateLobbyPanel
var _browse_lobbies_panel: BrowseLobbiesPanel
var _lobby_room_panel: LobbyRoomPanel

func _ready() -> void:
	theme = UIThemeState.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main_panel()
	_build_creation_panel()
	_build_single_player_panel()
	_build_settings_panel()
	_build_multiplayer_panels()
	_build_version_stamp()
	_show_main()
	UIThemeState.changed.connect(_on_theme_changed)
	# Lobby creation / join results route us into the LobbyRoom panel.
	# Async because Steam answers these calls a few frames after the
	# request — wiring through NetState signals keeps the UI flow
	# synchronous-feeling without hard-coding timing.
	NetState.lobby_created_result.connect(_on_lobby_created_result)
	NetState.lobby_joined_result.connect(_on_lobby_joined_result)

func _build_settings_panel() -> void:
	_settings_panel = SettingsPanel.new()
	_settings_panel.visible = false
	_settings_panel.back_pressed.connect(_show_main)
	add_child(_settings_panel)


func _build_multiplayer_panels() -> void:
	_multiplayer_panel = MultiplayerPanel.new()
	_multiplayer_panel.visible = false
	_multiplayer_panel.back_pressed.connect(_show_main)
	_multiplayer_panel.create_pressed.connect(_show_create_lobby)
	_multiplayer_panel.browse_pressed.connect(_show_browse_lobbies)
	add_child(_multiplayer_panel)

	_create_lobby_panel = CreateLobbyPanel.new()
	_create_lobby_panel.visible = false
	_create_lobby_panel.back_pressed.connect(_show_multiplayer)
	_create_lobby_panel.submit_pressed.connect(_on_create_submit)
	add_child(_create_lobby_panel)

	_browse_lobbies_panel = BrowseLobbiesPanel.new()
	_browse_lobbies_panel.visible = false
	_browse_lobbies_panel.back_pressed.connect(_show_multiplayer)
	_browse_lobbies_panel.lobby_selected.connect(_on_browse_join)
	add_child(_browse_lobbies_panel)

	_lobby_room_panel = LobbyRoomPanel.new()
	_lobby_room_panel.visible = false
	_lobby_room_panel.leave_pressed.connect(_show_multiplayer)
	add_child(_lobby_room_panel)

func _build_creation_panel() -> void:
	_creation_panel = CharacterCreationPanel.new()
	_creation_panel.visible = false
	_creation_panel.back_pressed.connect(_show_single_player)
	_creation_panel.start_pressed.connect(_on_start_pressed)
	add_child(_creation_panel)


func _build_single_player_panel() -> void:
	_single_player_panel = ContinuePanel.new()
	_single_player_panel.show_create_button = true
	_single_player_panel.panel_title = "MENU_SINGLE_PLAYER"
	_single_player_panel.visible = false
	_single_player_panel.back_pressed.connect(_show_main)
	_single_player_panel.character_selected.connect(_on_character_selected)
	_single_player_panel.create_character_pressed.connect(_on_new_game_pressed)
	add_child(_single_player_panel)

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

	buttons.add_child(_make_button("MENU_SINGLE_PLAYER", _on_single_player_pressed))
	buttons.add_child(_make_button("MENU_MULTIPLAYER", _on_multiplayer_pressed))
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
	_single_player_panel.visible = false
	_settings_panel.visible = false
	_multiplayer_panel.visible = false
	_create_lobby_panel.visible = false
	_browse_lobbies_panel.visible = false
	_lobby_room_panel.visible = false

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

func _on_single_player_pressed() -> void:
	_show_single_player()


func _on_multiplayer_pressed() -> void:
	_show_multiplayer()


func _show_multiplayer() -> void:
	_hide_all()
	_multiplayer_panel.visible = true


func _show_create_lobby() -> void:
	_hide_all()
	_create_lobby_panel.set_default_name("%s's Game" % SteamState.persona_name)
	_create_lobby_panel.visible = true


func _show_browse_lobbies() -> void:
	_hide_all()
	_browse_lobbies_panel.visible = true
	_browse_lobbies_panel.refresh()


func _show_lobby_room() -> void:
	_hide_all()
	_lobby_room_panel.visible = true
	_lobby_room_panel.reset()


func _on_create_submit(lobby_name: String, max_members: int, lobby_type: int) -> void:
	NetState.create_lobby(lobby_name, max_members, lobby_type as NetState.LobbyType)
	# Stay on the form until lobby_created_result fires — that handler
	# decides whether to advance to the lobby room or surface an error.


func _on_browse_join(target_lobby_id: int) -> void:
	NetState.join_lobby(target_lobby_id)


func _on_lobby_created_result(success: bool, _new_lobby_id: int) -> void:
	if success:
		_show_lobby_room()
	# On failure we just stay on the create form — the warning print
	# from NetState lands in the editor output. A toast would be a Phase
	# 1C polish pass.


func _on_lobby_joined_result(success: bool, _joined_lobby_id: int) -> void:
	if success:
		_show_lobby_room()

func _show_single_player() -> void:
	_hide_all()
	_single_player_panel.refresh()
	_single_player_panel.visible = true


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
