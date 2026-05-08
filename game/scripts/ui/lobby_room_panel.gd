extends Control
class_name LobbyRoomPanel

## Pre-game lobby room — member list + chat + Leave (everyone) + Start
## (host only). Reads NetState for state and listens for lobby signals
## to refresh the member list and append chat / system messages.
##
## Start transitions to level_shell.tscn. Phase 1B does NOT yet sync the
## scene transition to other peers — that lands in Phase 2 along with
## the actual gameplay replication. For now, the host drops into the
## game alone; clients sit in the lobby until Phase 2.

signal leave_pressed
signal start_pressed

const GAME_SCENE := "res://scenes/world/level_shell.tscn"
const TITLE_FONT_SIZE := 16
const PANEL_WIDTH := 600.0
const MEMBERS_HEIGHT := 140.0
const CHAT_HEIGHT := 220.0
const SYSTEM_COLOR := Color(0.55, 0.62, 0.72, 0.9)

var _title_label: Label
var _members_box: VBoxContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _start_btn: Button
var _leave_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	NetState.lobby_state_changed.connect(_refresh)
	NetState.lobby_chat_received.connect(_on_chat_received)
	NetState.lobby_member_joined.connect(_on_member_joined)
	NetState.lobby_member_left.connect(_on_member_left)
	# Both host and client land on this signal — host emits it locally
	# from start_game(), client emits it after picking up the lobby
	# data update. Single transition path, no host/client branch needed.
	NetState.game_starting.connect(_on_game_starting)


func _exit_tree() -> void:
	NetState.lobby_state_changed.disconnect(_refresh)
	NetState.lobby_chat_received.disconnect(_on_chat_received)
	NetState.lobby_member_joined.disconnect(_on_member_joined)
	NetState.lobby_member_left.disconnect(_on_member_left)
	NetState.game_starting.disconnect(_on_game_starting)


# Called by the parent (StartupScreen) when this panel becomes visible.
# Wipes any stale chat log from a previous lobby and pulls a fresh
# snapshot from NetState.
func reset() -> void:
	if _chat_log != null:
		_chat_log.clear()
	_refresh()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	vbox.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	center.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "MENU_MP_LOBBY_ROOM"
	_title_label.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	_title_label.add_theme_color_override(&"font_color", Color(0.85, 0.92, 1.0, 1.0))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	# ── Members panel ─────────────────────────────────────────────────
	var members_label := Label.new()
	members_label.text = "MENU_MP_MEMBERS"
	members_label.add_theme_font_size_override(&"font_size", 12)
	members_label.add_theme_color_override(&"font_color", Color(0.7, 0.75, 0.85, 1.0))
	vbox.add_child(members_label)

	var members_scroll := ScrollContainer.new()
	members_scroll.custom_minimum_size = Vector2(PANEL_WIDTH, MEMBERS_HEIGHT)
	members_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(members_scroll)

	_members_box = VBoxContainer.new()
	_members_box.add_theme_constant_override(&"separation", 4)
	_members_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	members_scroll.add_child(_members_box)

	# ── Chat panel ────────────────────────────────────────────────────
	var chat_label := Label.new()
	chat_label.text = "MENU_MP_CHAT"
	chat_label.add_theme_font_size_override(&"font_size", 12)
	chat_label.add_theme_color_override(&"font_color", Color(0.7, 0.75, 0.85, 1.0))
	vbox.add_child(chat_label)

	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.custom_minimum_size = Vector2(PANEL_WIDTH, CHAT_HEIGHT)
	_chat_log.fit_content = false
	_chat_log.selection_enabled = true
	vbox.add_child(_chat_log)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Press Enter to send"
	_chat_input.custom_minimum_size = Vector2(PANEL_WIDTH, 32.0)
	_chat_input.text_submitted.connect(_on_chat_submitted)
	vbox.add_child(_chat_input)

	# ── Footer (Leave + Start) ────────────────────────────────────────
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 8)
	footer.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(footer)

	_leave_btn = Button.new()
	_leave_btn.text = "MENU_MP_LEAVE"
	_leave_btn.custom_minimum_size = Vector2(140.0, 36.0)
	_leave_btn.pressed.connect(_on_leave_pressed)
	footer.add_child(_leave_btn)

	_start_btn = Button.new()
	_start_btn.text = "MENU_MP_START"
	_start_btn.custom_minimum_size = Vector2(140.0, 36.0)
	_start_btn.pressed.connect(_on_start_pressed)
	footer.add_child(_start_btn)


func _refresh() -> void:
	# Title shows lobby name (set on host's createLobby) so members can
	# tell which room they're in at a glance.
	var lobby_name: String = ""
	if NetState.is_in_lobby():
		lobby_name = Steam.getLobbyData(NetState.lobby_id, NetState.LOBBY_NAME_KEY)
	_title_label.text = lobby_name if not lobby_name.is_empty() else "MENU_MP_LOBBY_ROOM"

	# Member list — host first, then everyone else. Host gets a "(host)"
	# tag so it's obvious who controls Start.
	for child in _members_box.get_children():
		child.queue_free()
	for member_id_v in NetState.lobby_members.keys():
		var member_id: int = int(member_id_v)
		var member_name: String = NetState.lobby_members[member_id]
		var label := Label.new()
		var suffix := "  (host)" if member_id == NetState.lobby_owner_id else ""
		label.text = "  %s%s" % [member_name, suffix]
		label.add_theme_font_size_override(&"font_size", 13)
		_members_box.add_child(label)

	# Start is host-only. Non-hosts see the button disabled with the
	# same label so the UI shape doesn't shift between roles.
	_start_btn.disabled = not NetState.is_host()


func _append_system(text: String) -> void:
	_chat_log.push_color(SYSTEM_COLOR)
	_chat_log.add_text("— %s\n" % text)
	_chat_log.pop()


func _append_chat(member_name: String, text: String) -> void:
	_chat_log.push_bold()
	_chat_log.add_text("%s: " % member_name)
	_chat_log.pop()
	_chat_log.add_text("%s\n" % text)


func _on_chat_received(_steam_id: int, member_name: String, text: String) -> void:
	_append_chat(member_name, text)


func _on_member_joined(_steam_id: int, member_name: String) -> void:
	_append_system("%s joined" % member_name)


func _on_member_left(_steam_id: int, member_name: String) -> void:
	_append_system("%s left" % member_name)


func _on_chat_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	_chat_input.clear()
	if trimmed.is_empty():
		return
	NetState.send_chat(trimmed)
	# Steam's lobby_message callback fires for our own messages too, so
	# we DON'T append locally — would double the line. The callback
	# routes through _on_chat_received as a normal incoming message.


func _on_leave_pressed() -> void:
	NetState.leave_lobby()
	leave_pressed.emit()


func _on_start_pressed() -> void:
	# Host calls start_game(), which sets up the SteamMultiplayerPeer
	# and broadcasts `started=1` to lobby data. The actual scene change
	# is deferred to the game_starting handler so it fires from the same
	# code path on host AND client (the client picks up the lobby data
	# update and emits game_starting from there).
	if not NetState.is_host():
		return
	if not NetState.start_game():
		# Peer creation failed — leave the user on the lobby room. The
		# warning print from NetState lands in the editor output. A
		# proper toast would be Phase 2 polish.
		return


func _on_game_starting() -> void:
	# Defer the scene change one frame: lets the SteamMultiplayerPeer
	# settle into multiplayer.multiplayer_peer before the new scene's
	# autoloads + nodes start querying it.
	start_pressed.emit()
	call_deferred("_change_to_game_scene")


func _change_to_game_scene() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
