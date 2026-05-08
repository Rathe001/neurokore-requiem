extends Node

## Multiplayer lifecycle — owns the active Steam Lobby, tracks members,
## relays chat. Other gameplay systems ask NetState "are we in a lobby?",
## "am I the host?", "what's my peer id?" instead of reaching into Steam
## directly.
##
## Phase 1A: lobby plumbing only (create / join / leave / list / chat).
## The actual SteamMultiplayerPeer wiring + game-scene replication land in
## Phase 2; this layer's job is just the room you stand in BEFORE the game.
##
## Authority rationale: SP and MP-host follow the same code path, so most
## gameplay reads `is_authority()` (true for both) instead of branching on
## multiplayer at all. Only the MP-client returns false.

signal lobby_state_changed
signal lobby_created_result(success: bool, new_lobby_id: int)
signal lobby_joined_result(success: bool, joined_lobby_id: int)
signal lobby_left
signal lobby_member_joined(steam_id: int, member_name: String)
signal lobby_member_left(steam_id: int, member_name: String)
signal lobby_chat_received(steam_id: int, member_name: String, text: String)
signal lobby_match_list_updated(lobbies: Array)
## Fires on host AND every client at the moment we're transitioning into
## the game scene. UI listens for this and calls change_scene_to_file —
## NetState never touches scenes directly.
signal game_starting

enum Mode {
	OFFLINE,  # No lobby, no peer — single player.
	HOST,     # We created the lobby; we own the simulation.
	CLIENT,   # We joined someone else's lobby; they own the simulation.
}

# Mirrors Steam's k_ELobbyType. Public is what the lobby browser shows;
# Friends-only is invite-or-friends-list; Private is invite-only and
# doesn't show up in the public browser.
enum LobbyType {
	PRIVATE = 0,
	FRIENDS = 1,
	PUBLIC = 2,
	INVISIBLE = 3,
}

# Lobby metadata key used to filter the lobby browser to OUR game's
# lobbies (vs. other games using the same Steam app id, which shouldn't
# happen but defense-in-depth). Set on createLobby, filtered on
# requestLobbyList.
const LOBBY_GAME_KEY: String = "game"
const LOBBY_GAME_VALUE: String = "neurokore"
const LOBBY_NAME_KEY: String = "name"
const LOBBY_HOST_KEY: String = "host"
# Set to "1" by the host when Start is pressed. Every member receives a
# lobby_data_update callback; non-host clients read this and create their
# SteamMultiplayerPeer client connection in response. Lobby data is the
# right transport for this signal because it's already replicated to all
# members and survives ordering / late callbacks.
const LOBBY_STARTED_KEY: String = "started"
const LOBBY_SEED_KEY: String = "level_seed"

var mode: Mode = Mode.OFFLINE
var lobby_id: int = 0
var lobby_owner_id: int = 0
# steam_id (int) -> persona_name (String) for everyone currently in the
# lobby including the local player. Refreshed on every member join /
# leave so UI can read straight from this.
var lobby_members: Dictionary = {}
# True once we've created the SteamMultiplayerPeer and bound it to
# multiplayer.multiplayer_peer for this session. Reset on leave_lobby.
var game_started: bool = false

var _peer: SteamMultiplayerPeer = null
var _signals_connected: bool = false
var _poll_accum: float = 0.0
# Dev-only override. Two-process tests on a single Steam account fail
# our `lobby_owner_id == SteamState.steam_id` check (same id on both
# sides), so the second process incorrectly identifies as host. Pass
# `--mp-force-client` on the .exe command line to force CLIENT mode
# regardless of Steam IDs — only useful with same-account testing,
# never wanted in production builds.
var _force_client_for_testing: bool = false


func _ready() -> void:
	process_priority = -90  # after SteamState (-100), before gameplay autoloads
	_force_client_for_testing = "--mp-force-client" in OS.get_cmdline_args()
	if _force_client_for_testing:
		print("[NetState] --mp-force-client active: forcing CLIENT role regardless of Steam IDs.")
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
	# Async results from createLobby / joinLobby — both fire even when the
	# call fails, with status fields telling us why.
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	# Member entered / left / disconnected / kicked / banned. All four
	# arrive on the same callback with a `change_state` discriminator.
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_message.connect(_on_lobby_message)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	# Fires on every member when ANY lobby data changes. We use it to
	# detect the host setting `started=1` and trigger the client peer
	# connection + scene transition.
	Steam.lobby_data_update.connect(_on_lobby_data_update)


# ─── Public API ───────────────────────────────────────────────────────────

## Creates a Steam lobby with the given name + max members + privacy.
## Async — listen for `lobby_created_result` to know whether it worked.
func create_lobby(lobby_name: String, max_members: int, lobby_type: LobbyType) -> void:
	if not _ensure_steam():
		return
	if lobby_id != 0:
		push_warning("[NetState] create_lobby called while already in a lobby — leaving first.")
		leave_lobby()
	# Stash the requested name so _on_lobby_created can stamp it onto
	# the lobby metadata once the lobby exists. createLobby itself
	# doesn't take a name — the lobby starts nameless and we set it
	# via setLobbyData immediately after.
	_pending_lobby_name = lobby_name
	Steam.createLobby(int(lobby_type), max_members)


## Joins an existing lobby by its Steam lobby id (64-bit int).
## Async — listen for `lobby_joined_result`.
func join_lobby(target_lobby_id: int) -> void:
	if not _ensure_steam():
		return
	if lobby_id == target_lobby_id:
		return
	if lobby_id != 0:
		leave_lobby()
	Steam.joinLobby(target_lobby_id)


## Leaves the current lobby. Synchronous — on return, lobby_id == 0.
## Tears down any active SteamMultiplayerPeer too so a subsequent
## lobby join doesn't inherit stale peer state.
func leave_lobby() -> void:
	if lobby_id == 0:
		return
	_teardown_peer()
	Steam.leaveLobby(lobby_id)
	lobby_id = 0
	lobby_owner_id = 0
	lobby_members.clear()
	mode = Mode.OFFLINE
	game_started = false
	lobby_left.emit()
	lobby_state_changed.emit()


## Asks Steam for the public lobby list. Async — listen for
## `lobby_match_list_updated`. Filtered to only lobbies tagged with
## our game key, world-wide distance.
func request_lobby_list() -> void:
	if not _ensure_steam():
		return
	# Filter: only OUR game's lobbies. Steam app ids are unique so this is
	# belt-and-suspenders, but if we ever fork the project this is what
	# stops the two forks from seeing each other's rooms.
	Steam.addRequestLobbyListStringFilter(LOBBY_GAME_KEY, LOBBY_GAME_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.requestLobbyList()


## Host-only. Creates a SteamMultiplayerPeer, registers every lobby
## member as a known peer, binds the peer to the MultiplayerAPI, then
## stamps `started=1` onto lobby data so clients trigger their own
## peer connection. Fires `game_starting` locally so the UI can swap
## to the game scene; clients fire the same signal from
## _on_lobby_data_update once Steam delivers the data update.
func start_game() -> bool:
	if not is_host():
		push_warning("[NetState] start_game called by non-host; ignored.")
		return false
	if game_started:
		return true
	if not _create_host_peer():
		return false
	game_started = true
	# Setting lobby data is broadcast to all members — this is what
	# tells clients to spin up their own SteamMultiplayerPeer. Doing it
	# AFTER the host peer is up means clients can't race ahead and try
	# to connect before the host is listening.
	Steam.setLobbyData(lobby_id, LOBBY_STARTED_KEY, "1")
	print("[NetState] Game starting (host) — peer ready, %d known members." % lobby_members.size())
	game_starting.emit()
	return true


## Sends a chat message to all members of the current lobby.
## Other peers receive it via `lobby_chat_received`.
func send_chat(text: String) -> void:
	if lobby_id == 0 or text.is_empty():
		return
	Steam.sendLobbyChatMsg(lobby_id, text)


# ─── State queries ────────────────────────────────────────────────────────

# True when this peer owns the world simulation. SP and MP-host both
# return true. MP-client returns false. Use this to gate enemy AI ticks,
# damage rolls, loot generation, level / zone state mutations.
func is_authority() -> bool:
	if _force_client_for_testing:
		return false
	return mode != Mode.CLIENT


func is_in_lobby() -> bool:
	return lobby_id != 0


func is_host() -> bool:
	if _force_client_for_testing:
		return false
	return mode == Mode.HOST


func is_client() -> bool:
	if _force_client_for_testing:
		return true
	return mode == Mode.CLIENT


## Store the current level seed in lobby data so late joiners can rebuild
## the same geometry. Called by LevelBuilder on initial build and by
## PrototypeRoot on level reset.
func set_level_seed(seed_val: int) -> void:
	if lobby_id != 0:
		Steam.setLobbyData(lobby_id, LOBBY_SEED_KEY, str(seed_val))


## Read the level seed from lobby data. Returns 0 when unavailable.
func get_level_seed() -> int:
	if lobby_id == 0:
		return 0
	var s := Steam.getLobbyData(lobby_id, LOBBY_SEED_KEY)
	return int(s) if s != "" else 0


# ─── Steam callback handlers ──────────────────────────────────────────────

var _pending_lobby_name: String = ""


func _on_lobby_created(connect_status: int, new_lobby_id: int) -> void:
	# Steam's k_EResult enum: 1 = OK. Anything else is a failure (auth
	# expired, no internet, lobby quota hit, etc.). We don't try to
	# discriminate the failure modes here — the user retries from the UI.
	if connect_status != 1:
		push_warning("[NetState] Lobby creation failed (status %d)" % connect_status)
		_pending_lobby_name = ""
		lobby_created_result.emit(false, 0)
		return
	lobby_id = new_lobby_id
	lobby_owner_id = SteamState.steam_id
	mode = Mode.HOST
	# Stamp metadata so the lobby browser can find + display this lobby.
	# `name` is what the user typed; `host` is the persona; `game` is the
	# filter key.
	Steam.setLobbyData(lobby_id, LOBBY_GAME_KEY, LOBBY_GAME_VALUE)
	Steam.setLobbyData(lobby_id, LOBBY_HOST_KEY, SteamState.persona_name)
	if not _pending_lobby_name.is_empty():
		Steam.setLobbyData(lobby_id, LOBBY_NAME_KEY, _pending_lobby_name)
	_pending_lobby_name = ""
	_refresh_members()
	print("[NetState] Lobby created: %d (%s)" % [lobby_id, Steam.getLobbyData(lobby_id, LOBBY_NAME_KEY)])
	lobby_created_result.emit(true, lobby_id)
	lobby_state_changed.emit()


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# response == 1 means joined successfully. Other values: the lobby is
	# full, doesn't exist anymore, the user is banned, etc. Caller's UI
	# should show a friendly "couldn't join" toast and bounce back.
	if response != 1:
		push_warning("[NetState] Lobby join failed (response %d)" % response)
		lobby_joined_result.emit(false, 0)
		return
	lobby_id = joined_lobby_id
	lobby_owner_id = Steam.getLobbyOwner(lobby_id)
	# `mode` distinguishes "I created the lobby" from "I joined someone
	# else's lobby" — Steam doesn't tell us which one we did, so we infer
	# from owner_id == self.
	mode = Mode.HOST if lobby_owner_id == SteamState.steam_id else Mode.CLIENT
	_refresh_members()
	print("[NetState] Lobby joined: %d (%s, %d/%d members)" % [
		lobby_id,
		Steam.getLobbyData(lobby_id, LOBBY_NAME_KEY),
		Steam.getNumLobbyMembers(lobby_id),
		Steam.getLobbyMemberLimit(lobby_id),
	])
	lobby_joined_result.emit(true, lobby_id)
	lobby_state_changed.emit()


func _on_lobby_chat_update(_changed_lobby_id: int, changed_id: int, _maker_id: int, change_state: int) -> void:
	# change_state values from Steam's k_EChatMemberStateChange flags:
	#   1 = entered, 2 = left, 4 = disconnected, 8 = kicked, 16 = banned.
	# We treat anything-but-entered as "left" — UI doesn't care why.
	var member_name: String = Steam.getFriendPersonaName(changed_id)
	_refresh_members()
	if change_state == 1:
		print("[NetState] Member joined: %s (%d)" % [member_name, changed_id])
		# Accept late-joining peers into the active game. Without this,
		# the SteamMultiplayerPeer ignores connections from members who
		# joined the lobby after start_game().
		if game_started and _peer != null and is_host():
			_peer.add_peer(changed_id)
			print("[NetState] Late join: added peer %d to active game." % changed_id)
		lobby_member_joined.emit(changed_id, member_name)
	else:
		print("[NetState] Member left: %s (%d, state %d)" % [member_name, changed_id, change_state])
		lobby_member_left.emit(changed_id, member_name)
	lobby_state_changed.emit()


func _on_lobby_message(_received_lobby_id: int, sender_id: int, text: String, _chat_type: int) -> void:
	var member_name: String = Steam.getFriendPersonaName(sender_id)
	print("[NetState] Chat from %s (%d): %s" % [member_name, sender_id, text])
	lobby_chat_received.emit(sender_id, member_name, text)


func _on_lobby_match_list(matched_lobbies: Array) -> void:
	# Steam returns just lobby ids — fetch the metadata we'll show in the
	# browser. Member count needs a network round-trip per lobby, which
	# Steam already did before firing the callback, so getNumLobbyMembers
	# is cheap here.
	var infos: Array = []
	for lid_variant in matched_lobbies:
		var lid: int = int(lid_variant)
		infos.append({
			&"lobby_id": lid,
			&"name": Steam.getLobbyData(lid, LOBBY_NAME_KEY),
			&"host": Steam.getLobbyData(lid, LOBBY_HOST_KEY),
			&"member_count": Steam.getNumLobbyMembers(lid),
			&"member_limit": Steam.getLobbyMemberLimit(lid),
		})
	print("[NetState] Lobby list: %d result(s)" % infos.size())
	lobby_match_list_updated.emit(infos)


func _on_lobby_data_update(_arg0: int, _arg1: int, _arg2: int) -> void:
	_check_started_flag()


# Pulled out so the once-per-second polling fallback can call it too —
# both routes share the same gating logic. Polling is defensive: if the
# Steam callback ever fails to deliver (signal rename across versions,
# delivery quirk on a specific user, etc.) the poll still picks up the
# `started=1` data within ~1s and triggers the client connection.
func _check_started_flag() -> void:
	if lobby_id == 0 or game_started:
		return
	var started: String = Steam.getLobbyData(lobby_id, LOBBY_STARTED_KEY)
	if started != "1":
		return
	# Host already wired its peer in start_game(); only clients land here.
	if is_host():
		return
	if not _create_client_peer():
		return
	game_started = true
	print("[NetState] Game starting (client) — connecting to host %d." % lobby_owner_id)
	game_starting.emit()


func _process(delta: float) -> void:
	if lobby_id == 0 or game_started:
		return
	_poll_accum += delta
	if _poll_accum < 1.0:
		return
	_poll_accum = 0.0
	_check_started_flag()


func _create_host_peer() -> bool:
	var peer := SteamMultiplayerPeer.new()
	# create_host returns Godot's Error enum (OK = 0). Anything else is
	# fatal here — peer is unusable, surface the failure to the caller
	# so the UI can stay on the lobby room with an error toast.
	var err: int = peer.create_host(0)
	if err != OK:
		push_warning("[NetState] create_host failed (err %d)" % err)
		return false
	# Tell the peer about every other lobby member so it's expecting
	# their inbound connections. The host's own steam_id is implicit;
	# only OTHER members need adding.
	for member_id_v in lobby_members.keys():
		var member_id: int = int(member_id_v)
		if member_id != SteamState.steam_id:
			peer.add_peer(member_id)
	multiplayer.multiplayer_peer = peer
	_peer = peer
	return true


func _create_client_peer() -> bool:
	if lobby_owner_id == 0:
		push_warning("[NetState] _create_client_peer: no lobby_owner_id known.")
		return false
	var peer := SteamMultiplayerPeer.new()
	var err: int = peer.create_client(lobby_owner_id, 0)
	if err != OK:
		push_warning("[NetState] create_client failed (err %d)" % err)
		return false
	multiplayer.multiplayer_peer = peer
	_peer = peer
	return true


func _teardown_peer() -> void:
	if _peer == null:
		return
	# Closing first triggers a clean disconnect for all peers; clearing
	# multiplayer_peer afterwards drops the reference so a future
	# create_host / create_client starts from scratch.
	_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null


func _refresh_members() -> void:
	lobby_members.clear()
	if lobby_id == 0:
		return
	var count: int = Steam.getNumLobbyMembers(lobby_id)
	for i in count:
		var member_id: int = Steam.getLobbyMemberByIndex(lobby_id, i)
		var member_name: String = Steam.getFriendPersonaName(member_id)
		lobby_members[member_id] = member_name


# ─── Internals ────────────────────────────────────────────────────────────

func _ensure_steam() -> bool:
	if not SteamState.initialized:
		push_warning("[NetState] Steam not initialized; networking unavailable.")
		return false
	return true
