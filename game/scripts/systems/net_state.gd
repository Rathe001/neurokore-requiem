extends Node

## Multiplayer lifecycle — owns the active Steam Lobby, the current
## SteamMultiplayerPeer, and the host/client role. Other gameplay systems
## ask NetState "are we in a lobby?", "am I the host?", "what's my peer id?"
## rather than reaching into the Steam API directly.
##
## Phase 0 stub: structural only. Lobby creation/join/leave and the actual
## peer management land in Phase 1. The autoload is registered now so
## downstream systems can compile against it.
##
## Mode rationale: the code path for "we're in single player" is the same
## as "we're host with no other peers," so most game systems don't need
## to branch on multiplayer at all — they just check `is_authority()`,
## which is true for the SP player and the MP host.

signal lobby_state_changed
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)

enum Mode {
	OFFLINE,  # No lobby, no peer — single player.
	HOST,     # We created the lobby; we own the simulation.
	CLIENT,   # We joined someone else's lobby; they own the simulation.
}

var mode: Mode = Mode.OFFLINE
var lobby_id: int = 0


func _ready() -> void:
	process_priority = -90  # after SteamState (-100), before gameplay autoloads


# True when this peer owns the world simulation. SP and MP-host both
# return true. MP-client returns false. Use this to gate enemy AI ticks,
# damage rolls, loot generation, level / zone state mutations.
func is_authority() -> bool:
	return mode != Mode.CLIENT


func is_in_lobby() -> bool:
	return lobby_id != 0


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT
