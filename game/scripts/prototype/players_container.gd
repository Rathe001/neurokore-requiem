extends Node3D
class_name PlayersContainer

## Owns one PrototypePlayer per peer (or just one in single-player). Each
## peer spawns the SAME set of players in `_ready` based on the current
## NetState.lobby_members snapshot — no MultiplayerSpawner needed because
## the spawn pattern is deterministic across all peers.
##
## Why deterministic-spawn-on-ready instead of host-replicated spawning:
##   - Per-player MultiplayerSynchronizer routing requires identical
##     node paths on every peer. Naming each player by its Steam id and
##     having every peer spawn-by-id-list keeps paths in lockstep.
##   - The HUD's `&"player"` group lookup runs in HUD._ready (sibling
##     of this node, runs AFTER us in tree order). Spawning here means
##     the local player exists by the time HUD looks for it.
##
## Authority: each spawned Player has its multiplayer_authority set to
## that player's Steam id. SteamMultiplayerPeer uses Steam ids as peer
## ids, so `is_multiplayer_authority()` returns true on the local
## player and false on remotes. PrototypePlayer gates input / physics /
## animation logic on that flag.

const PLAYER_SCENE: PackedScene = preload("res://scenes/prototype/player.tscn")

# Peer id used for the local player when there's no MultiplayerPeer
# (i.e. single-player). 1 mirrors Godot's "server" id; in SP mode
# is_multiplayer_authority() returns true regardless because Godot
# treats "no peer" as "I'm authority".
const SP_LOCAL_ID: int = 1

# peer_id (int, Steam id when networked) -> PrototypePlayer
var _spawned: Dictionary = {}


func _ready() -> void:
	# multiplayer.has_multiplayer_peer() can't be used as the SP/MP
	# discriminator — GodotSteam plumbing leaves the engine flag in
	# misleading states across launch and lobby cycles. NetState.is_in_lobby()
	# is the authoritative signal: only true once we've actually created
	# or joined a Steam Lobby.
	var local_id: int = _local_peer_id()
	# Always spawn the local player. In SP this is the only one; in MP
	# it's our own avatar and we add the other lobby members below.
	_spawn_for(local_id)
	if NetState.is_in_lobby():
		for member_id_v in NetState.lobby_members.keys():
			var member_id: int = int(member_id_v)
			if member_id != local_id:
				_spawn_for(member_id)
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
	# get_unique_id() works for both SP (returns 1 by default, OR the
	# Steam id if GodotSteam auto-bound a peer) and MP (returns our
	# Steam id once we've joined a lobby). Either way it's the right
	# value to use as the local player's multiplayer authority.
	return multiplayer.get_unique_id()


func _spawn_from_lobby_members() -> void:
	# NetState.lobby_members was populated in _on_lobby_joined / created.
	# Even if a connection isn't fully handshaken yet, spawning the
	# placeholder Players means the synchronizers are ready to receive
	# the first state update the moment the link comes up.
	for member_id_v in NetState.lobby_members.keys():
		_spawn_for(int(member_id_v))
	# Edge case: host may load the scene before any clients have actually
	# connected at the multiplayer layer (lobby members are known via
	# Steam, but multiplayer.peer_connected fires later). The lobby
	# member list still has them, so we spawn proactively.


func _on_peer_connected(peer_id: int) -> void:
	# Only happens for peers that join after we entered the scene — the
	# initial set was covered by _spawn_from_lobby_members. Phase 7
	# drop-in coop will rely on this; for Phase 2B it's mostly defensive.
	_spawn_for(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var member_name: String = NetState.lobby_members.get(peer_id, "")
	if member_name.is_empty():
		member_name = "A player"
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
