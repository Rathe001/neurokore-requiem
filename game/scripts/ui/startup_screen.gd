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
var _global_chat_panel: GlobalChatPanel
var _create_lobby_panel: CreateLobbyPanel
var _browse_lobbies_panel: BrowseLobbiesPanel
var _mp_button: Button
# What to do after the user picks (or creates) a character on the
# ContinuePanel / CharacterCreationPanel: "sp" → load the save and
# launch the game scene (the original flow); "mp" → load the save and
# advance to the multiplayer panel instead. Letting the user enter MP
# without a character would land them in level_shell with empty
# PlayerState (no class, no level, no avatar).
var _post_select_target: String = "sp"

func _ready() -> void:
	theme = UIThemeState.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Title screen BGM. No-op if Music autoload reports the same track
	# is already playing (e.g., returning to title from settings).
	Music.play_track("res://resources/audio/music/title.mp3")
	_build_background()
	_build_main_panel()
	_build_creation_panel()
	_build_single_player_panel()
	_build_settings_panel()
	_build_multiplayer_panels()
	_build_version_stamp()
	_show_main()
	# Chrome restore is deferred until after the first scene frame draws.
	# Restoring earlier (top of _ready) makes the window opaque BEFORE the
	# boot-splash hand-off, leaving a beat where the splash image still
	# renders but its transparent bg_color reads as black on the now-opaque
	# window — visible as a fullscreen logo on black before the menu.
	# Waiting for frame_post_draw ensures the title scene is already on
	# screen when the chrome and opacity come back.
	_defer_restore_window_chrome()
	UIThemeState.changed.connect(_on_theme_changed)
	# Lobby creation / join results drive the MP transition. The host's
	# create-result triggers an immediate start_game (no waiting room);
	# the joiner's join-result waits for game_starting to fire (host has
	# already broadcast `started=1`), then drops them straight into the
	# game scene. Both paths converge on _on_game_starting below — the
	# old LobbyRoomPanel "wait until host clicks Start" interlude is gone.
	NetState.lobby_created_result.connect(_on_lobby_created_result)
	NetState.lobby_joined_result.connect(_on_lobby_joined_result)
	NetState.game_starting.connect(_on_game_starting)

func _exit_tree() -> void:
	UIThemeState.changed.disconnect(_on_theme_changed)
	NetState.lobby_created_result.disconnect(_on_lobby_created_result)
	NetState.lobby_joined_result.disconnect(_on_lobby_joined_result)
	NetState.game_starting.disconnect(_on_game_starting)
	if SteamState.initialized_changed.is_connected(_on_steam_initialized_changed):
		SteamState.initialized_changed.disconnect(_on_steam_initialized_changed)


# The project starts with a borderless, per-pixel-transparent window so the
# boot splash image's alpha channel shows the desktop through (no OS chrome
# around the logo). The title scene drawing its first frame is the trigger
# to swap back to a normal framed opaque window — restoring sooner leaves
# the splash visible on an already-opaque window for a beat (logo on black).
func _defer_restore_window_chrome() -> void:
	await RenderingServer.frame_post_draw
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)


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

	# Global chat is the new MP landing panel — character-selected players
	# enter chat first, then choose Create Lobby / Browse Lobbies from
	# inside it. The MultiplayerPanel above stays in the tree for callers
	# that bypass the chat (currently none, but kept so we can reroute
	# without rebuilding the tree).
	_global_chat_panel = GlobalChatPanel.new()
	_global_chat_panel.visible = false
	_global_chat_panel.back_pressed.connect(_on_global_chat_back)
	_global_chat_panel.create_lobby_pressed.connect(_show_create_lobby)
	_global_chat_panel.browse_lobbies_pressed.connect(_show_browse_lobbies)
	add_child(_global_chat_panel)

	_create_lobby_panel = CreateLobbyPanel.new()
	_create_lobby_panel.visible = false
	_create_lobby_panel.back_pressed.connect(_show_global_chat)
	_create_lobby_panel.submit_pressed.connect(_on_create_submit)
	add_child(_create_lobby_panel)

	_browse_lobbies_panel = BrowseLobbiesPanel.new()
	_browse_lobbies_panel.visible = false
	_browse_lobbies_panel.back_pressed.connect(_show_global_chat)
	_browse_lobbies_panel.lobby_selected.connect(_on_browse_join)
	add_child(_browse_lobbies_panel)

	# LobbyRoomPanel intentionally NOT instantiated — we used to route
	# through it as a "wait for host to start" interlude, but the new
	# flow auto-starts on lobby create and auto-joins on lobby join.
	# Keeping the panel in the tree caused a double scene-change race
	# because its own _on_game_starting handler ran ahead of ours and
	# left this StartupScreen detached when our deferred call fired.

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
	_mp_button = _make_button("MENU_MULTIPLAYER", _on_multiplayer_pressed, SteamState.initialized)
	if not SteamState.initialized:
		_mp_button.tooltip_text = "Steam is required for multiplayer"
		SteamState.initialized_changed.connect(_on_steam_initialized_changed)
	buttons.add_child(_mp_button)
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
	_global_chat_panel.visible = false
	_create_lobby_panel.visible = false
	_browse_lobbies_panel.visible = false

func _show_main() -> void:
	_hide_all()
	_main_panel.visible = true

func _show_creation() -> void:
	_hide_all()
	_creation_panel.reset_state()
	# Stamp the roster bucket BEFORE the panel becomes visible so any
	# subsequent character writeback uses the right mode_id. SP and MP
	# rosters are intentionally separate — a character created in one
	# never appears in the other.
	_creation_panel.mode_id = &"mp" if _post_select_target == "mp" else &"sp"
	_creation_panel.visible = true

func _show_settings() -> void:
	_hide_all()
	_settings_panel.visible = true

func _on_single_player_pressed() -> void:
	_post_select_target = "sp"
	_show_single_player()


func _on_multiplayer_pressed() -> void:
	# MP requires a character (class, spec, talents) to be loaded before
	# entering. Route through the same character-select panel as SP, but
	# remember to advance to the multiplayer panel instead of the game
	# scene once a character is picked or created.
	_post_select_target = "mp"
	_show_single_player()


func _on_steam_initialized_changed(value: bool) -> void:
	if _mp_button != null:
		_mp_button.disabled = not value
		if value:
			_mp_button.tooltip_text = ""


func _show_multiplayer() -> void:
	_hide_all()
	_multiplayer_panel.visible = true


# New MP landing — show global chat. Auto-joins / creates the global
# lobby if not already connected. Idempotent: re-showing the panel just
# republishes the player's character data without re-joining.
func _show_global_chat() -> void:
	_hide_all()
	GlobalChatState.ensure_in_global_chat()
	_global_chat_panel.refresh()
	_global_chat_panel.visible = true


# Back from global chat = back to main menu. Drop out of the chat lobby
# so the player frees their slot when they're not actively in MP.
func _on_global_chat_back() -> void:
	GlobalChatState.leave_global_chat()
	_show_main()


func _show_create_lobby() -> void:
	_hide_all()
	_create_lobby_panel.set_default_name("%s's Game" % SteamState.persona_name)
	# Re-tint each show — the panel was built before any character was
	# loaded, so the build-time accent is the neutral default. By the
	# time we reach this screen the player has selected a class.
	_create_lobby_panel.apply_theme()
	_create_lobby_panel.visible = true


func _show_browse_lobbies() -> void:
	_hide_all()
	_browse_lobbies_panel.visible = true
	_browse_lobbies_panel.refresh()


# _show_lobby_room intentionally removed — the lobby room is no longer
# part of the MP flow. Create / Join now auto-transition to the game
# scene via NetState.game_starting → _on_game_starting below.


func _on_create_submit(lobby_name: String, max_members: int, lobby_type: int, password: String) -> void:
	NetState.create_lobby(lobby_name, max_members, lobby_type as NetState.LobbyType, password)
	# Stay on the form until lobby_created_result fires — _on_lobby_created_result
	# fires start_game immediately and the game_starting signal swaps to
	# the game scene from there.


func _on_browse_join(target_lobby_id: int) -> void:
	NetState.join_lobby(target_lobby_id)


func _on_lobby_created_result(success: bool, _new_lobby_id: int) -> void:
	if not success:
		# On failure stay on the create form — the warning print from
		# NetState lands in the editor output. A toast would be a polish
		# pass; for now the user just clicks Create again.
		return
	# Host: kick the game off immediately. start_game() spins up the
	# SteamMultiplayerPeer and stamps `started=1` on the lobby; the
	# game_starting signal fires from the same call and our handler
	# swaps to the game scene a frame later.
	if not NetState.start_game():
		push_warning("[StartupScreen] start_game failed after create — peer setup error.")


func _on_lobby_joined_result(success: bool, _joined_lobby_id: int) -> void:
	# Joiner stays on the global chat panel until the host's `started=1`
	# is observed and game_starting fires (drop-in flow). No lobby room
	# anymore — joiners drop straight into the game scene the instant
	# the start signal lands.
	if not success:
		return


func _on_game_starting() -> void:
	# Defer one frame so the SteamMultiplayerPeer has settled into
	# multiplayer.multiplayer_peer before the new scene's autoloads /
	# nodes start querying it. Same rationale the old LobbyRoomPanel
	# used; logic moved here so create / join paths converge.
	call_deferred("_change_to_game_scene")


func _change_to_game_scene() -> void:
	# Defensive: the deferred dispatch can fire after the scene has
	# already swapped (e.g. if anything else also handled game_starting
	# and beat us to it). get_tree() returns null on a freed Control,
	# so bail rather than null-deref.
	var tree := get_tree()
	if tree == null:
		return
	LoadingScreen.cover_scene_transition()
	tree.change_scene_to_file(GAME_SCENE)

func _show_single_player() -> void:
	_hide_all()
	# Reuse the same ContinuePanel instance for both flows but reconfigure
	# its filter + title each time it appears so SP only ever lists
	# &"sp" characters and MP only ever lists &"mp" characters.
	if _post_select_target == "mp":
		_single_player_panel.mode_filter = &"mp"
		_single_player_panel.panel_title = "MENU_MULTIPLAYER"
	else:
		_single_player_panel.mode_filter = &"sp"
		_single_player_panel.panel_title = "MENU_SINGLE_PLAYER"
	_single_player_panel.refresh()
	_single_player_panel.visible = true


func _on_character_selected(save_id: String) -> void:
	if not SaveManager.load_game(save_id):
		return
	if _post_select_target == "mp":
		# Land in global chat — character data is now loaded into
		# PlayerState, which GlobalChatState reads when publishing the
		# member-list metadata.
		_show_global_chat()
	else:
		LoadingScreen.cover_scene_transition()
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
	# MP path skips the immediate game-scene launch — character is now
	# saved and PlayerState populated, advance to the global chat lobby
	# (the new MP landing) so the user can socialize while choosing
	# whether to host or browse.
	if _post_select_target == "mp":
		_show_global_chat()
	else:
		LoadingScreen.cover_scene_transition()
		get_tree().change_scene_to_file(GAME_SCENE)


static func _generate_uuid() -> String:
	var hex := "0123456789abcdef"
	var uuid := ""
	for i in 32:
		if i == 8 or i == 12 or i == 16 or i == 20:
			uuid += "-"
		uuid += hex[randi() % 16]
	return uuid
