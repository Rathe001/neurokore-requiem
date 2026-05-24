extends Node

## MP host migration — election + transport rebind + re-authority.
##
## When the host (peer 1) disconnects mid-session and DebugConfig
## .host_migration_enabled is true, this autoload runs the handshake that
## promotes a surviving client to authority instead of dumping everyone to
## the main menu.
##
## ## Architecture
##
## **Election.** Deterministic — the surviving lobby member with the lowest
## Steam ID becomes the new host. All clients compute identical answers
## from the same `NetState.lobby_members` dict, so no negotiation traffic
## is needed; everyone simultaneously knows who's promoting and who's
## reconnecting as a client.
##
## **State source.** The new host's authoritative state comes from its own
## existing local mirror of every replicated entity. `MultiplayerSynchronizer`
## has kept enemy positions / HP / state / pickup data / door + switch
## state in sync on every peer. When `set_multiplayer_authority(1)` flips
## those entities to point at the new host's peer ID, AI starts running
## from already-synced state. Host-only fields (aggro lists, mission
## kill counts, LoS explored cells) are lost — survivors get fresh AI
## state and re-explore. This is acceptable for the "host crashed mid-
## fight, keep playing" use case; it's not perfect resumption.
##
## **Transport rebind.** All peers close their `SteamMultiplayerPeer`. The
## elected host creates a new HOST peer; surviving clients create CLIENT
## peers pointed at the new host's Steam ID. `Steam.setLobbyOwner()` makes
## the lobby ownership change official.
##
## **Re-authority.** A walk of `EnemiesContainer` / `PickupsContainer` /
## doors / switches / exits calls `set_multiplayer_authority(1)` on each
## entity. On the new host this auto-flips `_is_remote_enemy()` to false,
## re-enabling AI. On other clients nothing changes (still remote).
##
## ## Known limitations (Session 1 scope)
##
## - **Mid-RPC drops** — host dies while applying damage may show 1-frame
##   ghost state on survivors. Need playtest to characterize.
## - **AI working memory** — enemies forget aggro/lock-on on the new host.
##   The reset reads as a brief "huh?" pause in dense fights.
## - **Mission progress** — switch counts etc. live on the host as Mission
##   state; until that gets mirrored, missions may visually reset on
##   migration (counts re-derive from re-counting "used" switches).
## - **Election race when two clients drop simultaneously** — the math
##   handles it (deterministic) but it's un-testable without scripted
##   disconnects.
## - **GodotSteam `setLobbyOwner` from non-owner** — Steam docs unclear on
##   whether a non-owner can elevate themselves after the previous owner's
##   process has actually closed. May need a fallback (e.g. one of the
##   clients holds a "deputy" role and is the only one who can call it).
##
## ## Migration lifecycle (signals)
##
## `migration_starting` — fires on every surviving peer when host_disconnected
## is detected AND host_migration_enabled is true. UI shows the migrating
## overlay; gameplay should freeze input.
##
## `migration_completed(succeeded: bool)` — fires when the handshake
## resolves. On success, game resumes. On failure (timeout or rebind
## error), the standard `HostDisconnectedScreen` should be shown by
## listeners (PrototypeRoot currently owns that).

signal migration_starting
signal migration_completed(succeeded: bool)

# Max seconds to wait for transport + state handshake before giving up
# and falling back to the disconnect overlay. Tuned generously — Steam
# relay handoff can take a few seconds, and we'd rather wait 8s than
# fail a recoverable migration. If real testing shows steady completion
# in 2s, this can drop to 5s.
const MIGRATION_TIMEOUT_SEC: float = 8.0

# Tick interval for the migration state machine. 100ms is fast enough
# for the few hundred ms of network handoff but slow enough to avoid
# busy-looping during a multi-second wait.
const MIGRATION_TICK_INTERVAL_SEC: float = 0.1

enum State {
	IDLE,
	ELECTING,   # Just observed host drop; computing winner.
	REBINDING,  # Closing old peer; opening new host/client peer.
	REAUTHING,  # Walking entities to re-set multiplayer_authority.
	RESUMING,   # Handshake complete; game can resume.
}

var state: State = State.IDLE
# Steam ID of the elected new host. Same on every surviving peer because
# election is deterministic. 0 when no migration is in flight.
var elected_host_steam_id: int = 0
# True on the peer that became the new host (its Steam ID == elected).
# Drives the host vs. client code path in _rebind_transport.
var elected_self: bool = false
# Elapsed seconds since migration started. Watchdog gives up at
# MIGRATION_TIMEOUT_SEC if the handshake hasn't completed.
var _elapsed: float = 0.0
var _tick_accum: float = 0.0


func _ready() -> void:
	# Run after NetState (-90) so the host_disconnected signal is wired
	# before we try to listen for it.
	process_priority = -80
	# Wait one frame so NetState's _ready (priority -90) has run and its
	# signal exists. Without this the connect call races with NetState
	# defining the signal.
	call_deferred(&"_wire_signals")


func _wire_signals() -> void:
	# NetState.host_disconnected is emitted on clients when peer 1 drops.
	# We intercept it BEFORE PrototypeRoot's existing overlay handler runs;
	# whether the overlay shows depends on the success/failure outcome of
	# the migration handshake. PrototypeRoot now gates its overlay on
	# host_migration_enabled — see the listener change there.
	if not NetState.host_disconnected.is_connected(_on_host_disconnected):
		NetState.host_disconnected.connect(_on_host_disconnected)


# ─── Migration entry point ────────────────────────────────────────────────

func _on_host_disconnected() -> void:
	if not _is_migration_enabled():
		# Flag off: fall through to the existing HostDisconnectedScreen
		# path that PrototypeRoot already handles. We emit nothing.
		return
	# SP guard — host_disconnected should never fire in SP (NetState only
	# subscribes to multiplayer.peer_disconnected on clients), but if it
	# somehow does, refuse to start migration because there's no lobby
	# to migrate within.
	if not NetState.is_in_lobby():
		print("[HostMigration] host_disconnected fired but not in a lobby; ignoring.")
		return
	if state != State.IDLE:
		# Already migrating from a prior drop; ignore re-entry.
		push_warning("[HostMigration] host_disconnected during active migration; ignoring.")
		return
	_start_migration()


# Allow direct invocation for testing (e.g. a debug button) without going
# through a real disconnect. Lets the user exercise election + re-authority
# in single-account testing where a real cross-peer drop isn't possible.
# No-op when migration is disabled, when not in a lobby, or when already
# migrating.
func force_start_migration_for_testing() -> void:
	if not _is_migration_enabled():
		push_warning("[HostMigration] force_start_migration_for_testing: flag is off")
		return
	if not NetState.is_in_lobby():
		print("[HostMigration] force_start_migration_for_testing: not in a lobby; no-op")
		return
	if state != State.IDLE:
		print("[HostMigration] force_start_migration_for_testing: already migrating (state=%d)" % state)
		return
	print("[HostMigration] force_start_migration_for_testing: simulating host drop")
	_start_migration()


func _start_migration() -> void:
	state = State.ELECTING
	_elapsed = 0.0
	_tick_accum = 0.0
	set_process(true)
	print("[HostMigration] Host disconnected; starting migration handshake.")
	migration_starting.emit()
	_elect_new_host()
	# Election runs synchronously; the next steps need a frame for Godot
	# to drain the dead peer's pending events before we close it.
	call_deferred(&"_rebind_transport")


# Deterministic election: surviving lobby member with the lowest Steam ID.
# Computed identically on every peer from the shared `lobby_members` dict.
# Excludes the dead host (still in lobby_members until Steam's chat update
# callback removes them, so filter by steam_id != lobby_owner_id).
func _elect_new_host() -> void:
	var dead_host_id: int = NetState.lobby_owner_id
	var candidates: Array[int] = []
	for member_id_v in NetState.lobby_members.keys():
		var member_id: int = int(member_id_v)
		if member_id != dead_host_id and member_id != 0:
			candidates.append(member_id)
	print("[HostMigration] Election: dead_host=%d, %d candidates: %s" % [dead_host_id, candidates.size(), candidates])
	if candidates.is_empty():
		push_warning("[HostMigration] No surviving lobby members to elect; aborting.")
		_fail_migration("no surviving members")
		return
	candidates.sort()
	elected_host_steam_id = candidates[0]
	elected_self = elected_host_steam_id == SteamState.steam_id
	# Solo-survivor case — I'm the only one left. We still want to run the
	# rebind so the player ends up as a host of an effectively-solo session
	# (lobby is preserved; others can still join via drop-in). Without this
	# the player would stay in client mode with no actual host, which would
	# break enemy spawning, damage, and pickups.
	if candidates.size() == 1 and elected_self:
		print("[HostMigration] Solo-survivor election: promoting self to host of 1-player session.")
	else:
		print("[HostMigration] Elected new host: %d (self=%s)" % [elected_host_steam_id, elected_self])


# ─── Transport rebind ──────────────────────────────────────────────────────

func _rebind_transport() -> void:
	if state == State.IDLE:
		return  # Failed during election.
	state = State.REBINDING
	# Close the existing client peer. NetState._teardown_peer disconnects
	# the host_disconnected handler so we don't re-enter migration during
	# our own cleanup.
	NetState._teardown_peer()
	if elected_self:
		# Promote: I am the new host. Take lobby ownership in Steam, then
		# open a host peer. Other clients will create client peers to me.
		if NetState.lobby_id != 0 and SteamState.initialized:
			# setLobbyOwner can fail silently if Steam considers the previous
			# owner still alive — we still try; client peers will connect to
			# whoever's the host even if lobby metadata lags.
			Steam.setLobbyOwner(NetState.lobby_id, elected_host_steam_id)
		NetState.lobby_owner_id = elected_host_steam_id
		NetState.mode = NetState.Mode.HOST
		if not NetState._create_host_peer():
			_fail_migration("create_host_peer failed on elected host")
			return
	else:
		# Stay client. Point at the new host's Steam ID and reconnect.
		NetState.lobby_owner_id = elected_host_steam_id
		NetState.mode = NetState.Mode.CLIENT
		# Give the new host a half-second to open its peer first. Without
		# this delay the client's create_client races ahead of the host's
		# create_host and the connection is rejected.
		await get_tree().create_timer(0.5).timeout
		if state == State.IDLE:
			return  # Aborted while waiting.
		if not NetState._create_client_peer():
			_fail_migration("create_client_peer failed")
			return
	# Re-authority and resume on a deferred call so the new peer has a
	# frame to bind before we touch multiplayer_authority on entities.
	call_deferred(&"_reauthority_and_resume")


# ─── Re-authority pass + resume ───────────────────────────────────────────

func _reauthority_and_resume() -> void:
	if state == State.IDLE:
		return
	state = State.REAUTHING
	# Every replicated entity needs its authority re-pointed at peer 1
	# (the new host). On the new host, this re-enables AI ticks on enemies
	# because PrototypeEnemy._is_remote_enemy() returns false when the
	# local peer ID matches the entity's authority. On other clients,
	# entities stay remote (no-op on AI but the new authority is correct
	# so RPCs route to the right place).
	var tree := get_tree()
	for enemy in tree.get_nodes_in_group(&"enemies"):
		if is_instance_valid(enemy):
			enemy.set_multiplayer_authority(1)
	for pickup in tree.get_nodes_in_group(&"pickups"):
		if is_instance_valid(pickup):
			pickup.set_multiplayer_authority(1)
	for door in tree.get_nodes_in_group(&"doors"):
		if is_instance_valid(door):
			door.set_multiplayer_authority(1)
	for switch in tree.get_nodes_in_group(&"resettable"):
		if is_instance_valid(switch):
			switch.set_multiplayer_authority(1)
	# Players already own their own avatars — each player node's authority
	# is its own peer ID, which doesn't change during migration. No-op for
	# the player walk.
	state = State.RESUMING
	# One more deferred call to let the re-authority propagate before we
	# announce success. Synchronizers re-evaluate their direction on the
	# next process tick.
	call_deferred(&"_complete_migration")


func _complete_migration() -> void:
	if state != State.RESUMING:
		return
	state = State.IDLE
	set_process(false)
	print("[HostMigration] Migration complete (elected_self=%s)" % elected_self)
	migration_completed.emit(true)


func _fail_migration(reason: String) -> void:
	push_warning("[HostMigration] Migration failed: %s" % reason)
	state = State.IDLE
	set_process(false)
	elected_host_steam_id = 0
	elected_self = false
	migration_completed.emit(false)


# ─── Watchdog tick ────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if state == State.IDLE:
		return
	_elapsed += delta
	_tick_accum += delta
	if _tick_accum < MIGRATION_TICK_INTERVAL_SEC:
		return
	_tick_accum = 0.0
	if _elapsed > MIGRATION_TIMEOUT_SEC:
		_fail_migration("timeout after %.1fs in state %d" % [_elapsed, state])


# ─── Helpers ──────────────────────────────────────────────────────────────

func _is_migration_enabled() -> bool:
	if DebugState.config == null:
		return false
	return DebugState.config.host_migration_enabled
