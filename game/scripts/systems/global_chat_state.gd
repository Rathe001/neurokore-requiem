extends Node

## Global chat lobby — separate from NetState's gameplay lobby. Each peer
## joins (or creates) a single shared "global" lobby on entering MP and
## stays in it for cross-lobby social chat. NetState's gameplay lobby is
## independent: hosting / joining a coop game never kicks the player out
## of global chat. Both Steam lobbies coexist; their callbacks share the
## same Steam signals, so each handler filters on its own lobby_id.
##
## Lobby selection: the player joins the most-populated existing global
## lobby with capacity. If none exist (or all are full at the 250 cap),
## a new one is created and registered. This keeps players together
## without a central server until popularity forces sharding.

signal joined
signal left
signal members_changed
signal chat_received(steam_id: int, member_name: String, text: String)

# Lobby metadata key used to filter the public lobby list down to "global
# chat lobbies for THIS game." NetState uses "game" → "neurokore"; we
# layer this second key on top so the gameplay-lobby browser doesn't
# pick up our chat lobbies and vice versa.
const GLOBAL_KEY: String = "global_chat"
const GLOBAL_VALUE: String = "neurokore"

# Per-member data keys — each peer writes their own character metadata
# via Steam.setLobbyMemberData; everyone else reads it via
# getLobbyMemberData. Steam replicates these strings to all members of
# the lobby automatically, so no custom RPC plumbing is needed for the
# rich member-list display.
const NAME_KEY: String = "name"
const LEVEL_KEY: String = "level"
const CLASS_KEY: String = "class"
const SPEC_KEY: String = "spec"
const AVATAR_KEY: String = "avatar"
const GENDER_KEY: String = "gender"
const HARDCORE_KEY: String = "hardcore"

# Steam lobbies cap at 250 members. New global lobbies start at this
# size; once popular, the join-most-populated logic naturally shards
# across multiple lobbies as each one fills.
const MAX_GLOBAL_MEMBERS: int = 250

var lobby_id: int = 0
## steam_id (int) -> Dictionary{name, level, class_id, spec_id, avatar_id,
## gender, hardcore}. Refreshed on member join/leave and on any member's
## data_update. UI renders directly off this map.
var members: Dictionary = {}

var _signals_connected: bool = false
var _pending_create: bool = false
var _pending_join_id: int = 0
## Set while we're awaiting a `lobby_match_list` callback for our own
## requestLobbyList call. NetState owns the same Steam signal; we filter
## by this flag instead of trying to disambiguate the two requests, so a
## stale match-list answer from NetState doesn't trigger a global-chat
## auto-join.
var _match_list_pending: bool = false


func _ready() -> void:
	# After SteamState (-100) and NetState (-90); ahead of gameplay autoloads.
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
	# Same callbacks NetState binds — Steam fires them for ALL lobbies the
	# user is in. Each handler below filters by lobby_id so we only react
	# to events for the global chat lobby.
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_message.connect(_on_lobby_message)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_data_update.connect(_on_lobby_data_update)


# ── Public API ────────────────────────────────────────────────────────────

func is_in_global_chat() -> bool:
	return lobby_id != 0


## Find an existing global chat lobby with capacity, or create one. Async —
## listen for `joined`. Safe to call when already connected (no-op).
func ensure_in_global_chat() -> void:
	if not SteamState.initialized:
		return
	if lobby_id != 0:
		# Already in. Republish self in case PlayerState changed since last
		# join (e.g. user came back to MP with a different character).
		_publish_self()
		_refresh_members()
		return
	if _pending_create or _pending_join_id != 0 or _match_list_pending:
		return
	# Filter the public lobby list to OUR global chat tag — keeps the
	# gameplay lobby browser's filter from racing us, and keeps us from
	# accidentally joining gameplay lobbies as chat rooms.
	Steam.addRequestLobbyListStringFilter(GLOBAL_KEY, GLOBAL_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	_match_list_pending = true
	Steam.requestLobbyList()


func leave_global_chat() -> void:
	if lobby_id == 0:
		return
	Steam.leaveLobby(lobby_id)
	lobby_id = 0
	members.clear()
	left.emit()
	members_changed.emit()


func send_chat(text: String) -> void:
	if lobby_id == 0 or text.is_empty():
		return
	Steam.sendLobbyChatMsg(lobby_id, text)
	# Local echo so the sender sees their own message immediately. Steam's
	# lobby_message loopback for self is unreliable in single-member
	# lobbies; we'd rather echo and dedupe than drop the user's own
	# chat. _on_lobby_message filters out sender_id == self to prevent
	# the double-display.
	var self_name := PlayerState.player_name
	if self_name.is_empty():
		self_name = SteamState.persona_name
	chat_received.emit(SteamState.steam_id, self_name, text)


## Republish our character metadata. Call after PlayerState changes
## (level up, character swap, etc.) so other members see fresh data.
func republish_self() -> void:
	_publish_self()


# ── Steam callback handlers ───────────────────────────────────────────────

func _on_lobby_match_list(matched_lobbies: Array) -> void:
	if not _match_list_pending:
		return
	_match_list_pending = false
	if lobby_id != 0:
		return  # already joined while the request was in flight
	# Pick the most-populated existing global lobby with capacity. This
	# concentrates the player base into the largest active room and only
	# spawns new rooms when they're full at the 250-member cap.
	var best_lid: int = 0
	var best_count: int = -1
	for lid_variant in matched_lobbies:
		var lid: int = int(lid_variant)
		var count := Steam.getNumLobbyMembers(lid)
		var limit := Steam.getLobbyMemberLimit(lid)
		if limit > 0 and count >= limit:
			continue
		if count > best_count:
			best_count = count
			best_lid = lid
	if best_lid != 0:
		_pending_join_id = best_lid
		Steam.joinLobby(best_lid)
		return
	# No existing room — create one, marked PUBLIC so it shows up in
	# subsequent match-list requests from other peers.
	_pending_create = true
	# Cast to int — NetState.LobbyType and Steam.LobbyType are the same
	# k_ELobbyType values but Godot's strict type checker won't bridge
	# the two enum types automatically.
	Steam.createLobby(int(NetState.LobbyType.PUBLIC), MAX_GLOBAL_MEMBERS)


func _on_lobby_created(connect_status: int, new_lobby_id: int) -> void:
	# We only care about creates we initiated. NetState also calls
	# createLobby for gameplay lobbies; without this guard we'd claim the
	# wrong callback.
	if not _pending_create:
		return
	_pending_create = false
	if connect_status != 1:
		push_warning("[GlobalChatState] Lobby creation failed (status %d)" % connect_status)
		return
	lobby_id = new_lobby_id
	Steam.setLobbyData(lobby_id, GLOBAL_KEY, GLOBAL_VALUE)
	_publish_self()
	_refresh_members()
	print("[GlobalChatState] Created global chat lobby: %d" % lobby_id)
	joined.emit()


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	# Only claim joins we initiated. NetState's gameplay-lobby join routes
	# through the same Steam signal; the pending-id check disambiguates.
	if _pending_join_id != joined_lobby_id:
		return
	_pending_join_id = 0
	if response != 1:
		push_warning("[GlobalChatState] Join failed (response %d)" % response)
		return
	lobby_id = joined_lobby_id
	_publish_self()
	_refresh_members()
	print("[GlobalChatState] Joined global chat lobby: %d (%d/%d)" % [
		lobby_id, Steam.getNumLobbyMembers(lobby_id), Steam.getLobbyMemberLimit(lobby_id)
	])
	joined.emit()


func _on_lobby_chat_update(changed_lobby_id: int, _changed_id: int, _maker_id: int, _change_state: int) -> void:
	if changed_lobby_id != lobby_id:
		return
	_refresh_members()


func _on_lobby_message(received_lobby_id: int, sender_id: int, text: String, _chat_type: int) -> void:
	if received_lobby_id != lobby_id:
		return
	# We already echoed our own send locally in send_chat — don't
	# duplicate the line if Steam's loopback delivers it back.
	if sender_id == SteamState.steam_id:
		return
	var member_name: String = Steam.getFriendPersonaName(sender_id)
	chat_received.emit(sender_id, member_name, text)


func _on_lobby_data_update(updated_lobby_id: int, _member_id: int, _success: int) -> void:
	# Fires when ANY member updates their lobby member data — that's our
	# trigger to re-read the rich-display fields (level / class / etc.)
	# from the changed peer.
	if updated_lobby_id != lobby_id:
		return
	_refresh_members()


# ── Internals ─────────────────────────────────────────────────────────────

func _refresh_members() -> void:
	members.clear()
	if lobby_id == 0:
		return
	var count := Steam.getNumLobbyMembers(lobby_id)
	for i in count:
		var sid: int = Steam.getLobbyMemberByIndex(lobby_id, i)
		members[sid] = _read_member_data(sid)
	members_changed.emit()


func _read_member_data(steam_id: int) -> Dictionary:
	# Self gets read straight from PlayerState — bypassing the lobby
	# member data round-trip that Steam doesn't always service locally
	# in the same frame as the setLobbyMemberData write. Without this
	# the player's own row showed "?" and "Lv. 0" until a remote member
	# triggered a lobby_data_update, which in a 1-person lobby never
	# happens.
	if steam_id == SteamState.steam_id:
		var self_name := PlayerState.player_name
		if self_name.is_empty():
			self_name = SteamState.persona_name
		return {
			"name": self_name,
			"level": PlayerState.level,
			"class_id": PlayerState.class_id,
			"spec_id": PlayerState.spec_id,
			"avatar_id": PlayerState.avatar_id,
			"gender": String(PlayerState.gender),
			"hardcore": PlayerState.hardcore,
		}
	var name_str: String = Steam.getLobbyMemberData(lobby_id, steam_id, NAME_KEY)
	if name_str.is_empty():
		# New peer who hasn't published yet — fall back to their Steam
		# persona so the row shows SOMETHING. Will refresh once their
		# setLobbyMemberData round-trips.
		name_str = Steam.getFriendPersonaName(steam_id)
	return {
		"name": name_str,
		"level": int(Steam.getLobbyMemberData(lobby_id, steam_id, LEVEL_KEY)),
		"class_id": StringName(Steam.getLobbyMemberData(lobby_id, steam_id, CLASS_KEY)),
		"spec_id": StringName(Steam.getLobbyMemberData(lobby_id, steam_id, SPEC_KEY)),
		"avatar_id": int(Steam.getLobbyMemberData(lobby_id, steam_id, AVATAR_KEY)),
		"gender": Steam.getLobbyMemberData(lobby_id, steam_id, GENDER_KEY),
		"hardcore": Steam.getLobbyMemberData(lobby_id, steam_id, HARDCORE_KEY) == "1",
	}


# Publish our character metadata as Steam lobby member data. Steam
# replicates these strings to every other peer in the lobby and fires
# lobby_data_update on each, which is what drives the rich member-list
# refresh on remote peers.
func _publish_self() -> void:
	if lobby_id == 0:
		return
	Steam.setLobbyMemberData(lobby_id, NAME_KEY, PlayerState.player_name)
	Steam.setLobbyMemberData(lobby_id, LEVEL_KEY, str(PlayerState.level))
	Steam.setLobbyMemberData(lobby_id, CLASS_KEY, String(PlayerState.class_id))
	Steam.setLobbyMemberData(lobby_id, SPEC_KEY, String(PlayerState.spec_id))
	Steam.setLobbyMemberData(lobby_id, AVATAR_KEY, str(PlayerState.avatar_id))
	Steam.setLobbyMemberData(lobby_id, GENDER_KEY, String(PlayerState.gender))
	Steam.setLobbyMemberData(lobby_id, HARDCORE_KEY, "1" if PlayerState.hardcore else "0")
