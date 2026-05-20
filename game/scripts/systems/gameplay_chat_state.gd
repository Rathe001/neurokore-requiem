extends Node

## In-game chat for the gameplay lobby (the coop session, not the
## persistent global chat). Mirrors GlobalChatState's Steam.lobby_message
## handling but scopes everything to NetState's lobby_id so the same
## Steam callbacks can serve both lobbies without colliding.
##
## SP behaviour: send_chat is a no-op when not in a lobby. The chat
## panel still opens for typing — the message just goes nowhere. Keeps
## the UX identical between SP and MP and avoids a "MP only" banner.

signal chat_received(steam_id: int, member_name: String, text: String)

# Maximum characters per chat line. Anything longer is silently
# truncated client-side. Steam itself caps lobby messages at 4 KiB,
# but a UI-level limit keeps the on-screen log readable.
const MAX_MESSAGE_LENGTH: int = 256
# How many recent messages the panel keeps in its rolling log. Older
# entries fall off the bottom — we don't keep full session history,
# this is a "live chat" view not a transcript.
const MAX_HISTORY: int = 50

# Steam lobby member data key for each peer's class_id. Published by
# every peer on lobby join via setLobbyMemberData, replicated by Steam
# to all other peers automatically. The chat panel reads this for each
# sender via Steam.getLobbyMemberData and paints the name in the
# matching class color.
const CLASS_KEY: String = "class"

## True while the in-game chat panel's text input has focus. Player input
## (movement, skills, hotkeys) reads this every frame to gate input polling
## so typing W or "1" doesn't move the character or fire a skill. The
## chat panel sets this directly on open/close.
var typing: bool = false

var _signals_connected: bool = false


func _ready() -> void:
	# Same priority window as GlobalChatState (-85) — runs after SteamState
	# (-100) and NetState (-90) so SteamState.initialized is settled and
	# NetState.lobby_id is populated by the time chat starts.
	process_priority = -85
	if SteamState.initialized:
		_connect_steam_signals()
	else:
		SteamState.initialized_changed.connect(_on_steam_initialized)


func _on_steam_initialized(active: bool) -> void:
	if active:
		_connect_steam_signals()


func _connect_steam_signals() -> void:
	if _signals_connected:
		return
	_signals_connected = true
	Steam.lobby_message.connect(_on_lobby_message)
	# Publish our class on every successful lobby join/create — without
	# this, remote peers have no way to color the sender's name. Both
	# signals route through the same _publish_self handler.
	NetState.lobby_created_result.connect(_on_lobby_created)
	NetState.lobby_joined_result.connect(_on_lobby_joined)


func _on_lobby_created(success: bool, _new_lobby_id: int) -> void:
	if success:
		_publish_self()


func _on_lobby_joined(success: bool, _joined_lobby_id: int) -> void:
	if success:
		_publish_self()


# ── Public API ────────────────────────────────────────────────────────────

## Republish our class to the gameplay lobby. Call this if PlayerState's
## class_id ever changes mid-session (currently it doesn't, but classes
## are per-character so a future "swap character without leaving lobby"
## flow would need this). No-op when not in a lobby.
func republish_self() -> void:
	_publish_self()


## Broadcast a chat line to every other peer in the gameplay lobby.
## SP / not-in-lobby / empty-text are silent no-ops. Always echoes the
## message to the local listener so the sender sees their own line
## immediately, regardless of Steam loopback behaviour.
func send_chat(text: String) -> void:
	if text.is_empty():
		return
	if text.length() > MAX_MESSAGE_LENGTH:
		text = text.substr(0, MAX_MESSAGE_LENGTH)
	# Local echo first — the sender's panel always shows their line, even
	# in SP where there's no lobby to broadcast through. _on_lobby_message
	# filters out sender_id == self_id below to prevent the double-display
	# when Steam does loop the message back.
	var self_name := PlayerState.player_name
	if self_name.is_empty():
		self_name = SteamState.persona_name
	chat_received.emit(SteamState.steam_id, self_name, text)
	if NetState.lobby_id == 0:
		return
	Steam.sendLobbyChatMsg(NetState.lobby_id, text)


# ── Steam callback handlers ───────────────────────────────────────────────

func _on_lobby_message(received_lobby_id: int, sender_id: int, text: String, _chat_type: int) -> void:
	# Both gameplay AND global chat lobbies fire this signal — filter to
	# OUR lobby only. GlobalChatState applies the same filter on its side.
	if NetState.lobby_id == 0 or received_lobby_id != NetState.lobby_id:
		return
	# Local echo already happened in send_chat for our own messages.
	if sender_id == SteamState.steam_id:
		return
	# Lookup display name from NetState's gameplay-lobby member map first
	# (it carries character names, not Steam personas), with persona
	# fallback for any peer who hasn't published metadata yet.
	var member_name: String = NetState.lobby_members.get(sender_id, "")
	if member_name.is_empty():
		member_name = Steam.getFriendPersonaName(sender_id)
	chat_received.emit(sender_id, member_name, text)


# ── Internals ─────────────────────────────────────────────────────────────

# Publish our resolved class identity (spec_id if specced, else origin
# class_id) as Steam lobby member data so other peers can color our
# sender name in chat. setLobbyMemberData triggers a lobby_data_update
# on every other peer, and getLobbyMemberData returns the cached string
# instantly thereafter — no custom RPC required.
func _publish_self() -> void:
	if NetState.lobby_id == 0:
		return
	Steam.setLobbyMemberData(NetState.lobby_id, CLASS_KEY, String(resolved_self_class_id()))


# Returns the most specific class identity for color resolution: spec_id
# (e.g. &"count", &"forged") when the player has chosen a spec, falling
# back to the origin class_id (&"analog" / &"cyborg") for unspecced
# characters. Both keys live in AttributeState.CLASS_COLORS, so
# AttributeState.color_for_id handles either correctly.
## Not `static` — see AttributeState.color_for_id for the rationale.
func resolved_self_class_id() -> StringName:
	if PlayerState.spec_id != &"":
		return PlayerState.spec_id
	return PlayerState.class_id
