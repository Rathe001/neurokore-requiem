extends Node3D
class_name PlayersContainer

## Owns one PrototypePlayer per peer (or just one in single-player). Each
## peer spawns its OWN avatar on `_ready` and any already-connected
## remote peers, then reacts to `multiplayer.peer_connected` /
## `peer_disconnected` for late-joiners and disconnects.
##
## Node naming and authority both use **Godot peer IDs**, NOT Steam ids.
## SteamMultiplayerPeer (per its source) sets `unique_id = 1` for the
## server and generates a fresh id per client — those ids ARE consistent
## across all peers (negotiated during handshake), but they are NOT the
## Steam ids tracked in NetState.lobby_members. Conflating the two
## causes phantom avatars (the host gets spawned both as "1" via
## get_unique_id and again as their Steam id from lobby_members).
##
## Authority side-effect: each Player node has multiplayer_authority set
## to its Godot peer id, so `is_multiplayer_authority()` returns true on
## the local peer's own avatar and false on remotes. PrototypePlayer
## gates input / physics / animation on that flag.

const PLAYER_SCENE: PackedScene = preload("res://scenes/prototype/player.tscn")

# Godot peer id used for the local player when there's no MultiplayerPeer
# (single-player). 1 mirrors Godot's "server" id; in SP mode
# is_multiplayer_authority() returns true regardless because Godot treats
# "no peer" as "I'm authority".
const SP_LOCAL_ID: int = 1

# godot_peer_id (int) -> PrototypePlayer
var _spawned: Dictionary = {}


func _ready() -> void:
	# NetState.is_in_lobby() is the SP/MP discriminator.
	# multiplayer.has_multiplayer_peer() can't be trusted because
	# GodotSteam plumbing leaves the engine flag in misleading states
	# across launch and lobby cycles.
	if not NetState.is_in_lobby():
		_spawn_for(SP_LOCAL_ID)
		return

	# MP: spawn local player at our own peer id (1 if host, generated id
	# if client), then one for each peer already connected at scene-load.
	# Remaining peers come in via multiplayer.peer_connected.
	var local_id: int = multiplayer.get_unique_id()
	_spawn_for(local_id)
	for peer_id in multiplayer.get_peers():
		_spawn_for(int(peer_id))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# Convenience for camera / HUD wiring — both want the player whose input
# this client controls. Falls back to first spawned player if the local
# id can't be resolved (shouldn't happen, but keeps things from crashing
# on a half-initialised peer).
func get_local_player() -> PrototypePlayer:
	var local_id: int = _local_peer_id()
	var player: PrototypePlayer = _spawned.get(local_id, null) as PrototypePlayer
	if player != null:
		return player
	# Defensive: return any spawned player if local lookup fails.
	for v in _spawned.values():
		return v as PrototypePlayer
	return null


func _local_peer_id() -> int:
	# Godot peer id space. 1 in SP (no peer), 1 on host, generated id on
	# clients. Always matches multiplayer_authority of the local Player.
	if not NetState.is_in_lobby():
		return SP_LOCAL_ID
	return multiplayer.get_unique_id()


func _on_peer_connected(peer_id: int) -> void:
	_spawn_for(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	# Look up the disconnecting peer's persona for the toast. We have to
	# map back from Godot peer id → Steam id → name; SteamMultiplayerPeer
	# exposes get_steam_id_for_peer_id when available.
	var member_name: String = "A player"
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.has_method(&"get_steam_id_for_peer_id"):
		var steam_id: int = peer.get_steam_id_for_peer_id(peer_id)
		if steam_id != 0:
			var stored: Variant = NetState.lobby_members.get(steam_id, "")
			if not String(stored).is_empty():
				member_name = String(stored)
	_despawn_for(peer_id)
	var local := get_local_player()
	if local != null:
		local.notification_requested.emit("%s disconnected." % member_name)


func _spawn_for(peer_id: int) -> PrototypePlayer:
	if _spawned.has(peer_id):
		return _spawned[peer_id]
	var player := PLAYER_SCENE.instantiate() as PrototypePlayer
	if player == null:
		push_error("[PlayersContainer] PLAYER_SCENE.instantiate() returned null or wrong type")
		return null
	# Name = stringified peer id so paths are identical on every peer.
	# MultiplayerSynchronizer routes updates by node path; mismatched
	# names would silently break replication.
	player.name = str(peer_id)
	# set_multiplayer_authority must run BEFORE add_child so the
	# attached synchronizer picks up the right authority on tree-enter.
	player.set_multiplayer_authority(peer_id)
	add_child(player)
	_spawned[peer_id] = player
	return player


func _despawn_for(peer_id: int) -> void:
	if not _spawned.has(peer_id):
		return
	var player := _spawned[peer_id] as PrototypePlayer
	_spawned.erase(peer_id)
	if is_instance_valid(player):
		_fade_and_free(player)


func _fade_and_free(player: PrototypePlayer) -> void:
	# Brief shrink-down so disconnects don't look like a hard pop.
	var tw := create_tween()
	tw.tween_property(player, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
	tw.tween_callback(player.queue_free)
