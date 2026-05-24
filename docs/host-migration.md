# Host migration

> **Status: Experimental — Session 1 scaffolding shipped, untested across real Steam accounts.** Off by default behind `DebugConfig.host_migration_enabled`. Real verification requires 2+ Steam accounts in playtest rotation.

## Why this exists

[`docs/multiplayer.md`](multiplayer.md) explicitly calls host migration out of scope:

> Host migration is technically possible but a multi-week stability project on its own and not where indie dev time should go.

We started it anyway because the alternative ("host drop = everyone returns to menu") is the single worst MP UX moment in the game. The decision is to accept the multi-week cost across multiple iterative sessions, with the understanding that **the code path landing in Session 1 is the *easy* part; the *hard* part is bugs that only manifest at the moment of disconnect, which can only be found through real cross-account playtesting**.

## Architecture (Session 1)

When `DebugConfig.host_migration_enabled = true` AND `NetState.host_disconnected` fires on a client:

1. **Election** — `HostMigration._elect_new_host` walks `NetState.lobby_members`, drops the dead host (`lobby_owner_id`), and picks the surviving member with the lowest Steam ID. Deterministic on every peer — no negotiation traffic. The elected peer's local computation sets `elected_self = true`.

2. **Transport rebind** — `HostMigration._rebind_transport` closes the existing `SteamMultiplayerPeer` via `NetState._teardown_peer`. The new host calls `Steam.setLobbyOwner` + `_create_host_peer`. Other clients wait 0.5s (so the host's peer is listening) then `_create_client_peer` pointed at the new host's Steam ID.

3. **Re-authority** — `HostMigration._reauthority_and_resume` walks `enemies`, `pickups`, `doors`, `resettable` groups and calls `set_multiplayer_authority(1)` on each entity. On the new host, this auto-flips `PrototypeEnemy._is_remote_enemy()` to false, re-enabling AI. On other clients, RPCs now route to the new host's peer ID.

4. **Resume** — `HostMigration._complete_migration` emits `migration_completed(true)`. `PrototypeRoot` listens; on success, no overlay shows. On failure (timeout 8s, or any `_fail_migration` call), the standard `HostDisconnectedScreen` fires as fallback.

## State that DOES survive (because Synchronizer kept clients in sync)

- Enemy positions, HP, state machine state, level, boss flag, display name
- Pickup positions, item data, owner_id, credit amounts
- Door open/locked/unlock counter
- Switch used/not-used
- Exit lock state
- Player avatars (each peer authoritative for its own avatar; unchanged)
- Procgen level geometry (deterministic from `LOBBY_SEED_KEY`)

## State that does NOT survive (host-only mirror)

- **AI working memory** — enemies forget aggro targets, last-seen positions, in-flight skill timers
- **Mission progress** — switch counts re-derive from the "switch.used" flag on each switch, but anything counted in the host's mission state is reset
- **LoS culler explored cells** — resets; rooms re-reveal as the player enters them
- **In-flight projectile authoritative state** — host's projectiles in motion at the moment of drop are lost (clients see only the ghost visual; the actual damage projectile dies with the host)
- **Audio room state** — re-derives on enter
- **In-flight damage applications** — any host RPC that was mid-flight at drop is dropped; survivors may show 1-frame ghost state

## Iteration roadmap

This is multi-session work. Each session here is roughly a focused 4-hour block.

### ✅ Session 1 — Scaffolding (this commit)
- Election + rebind + re-authority code path
- Migration overlay coordination with disconnect overlay
- Feature flag (off by default)
- Design doc + memory entry
- **Deliverable:** compiles, doesn't break SP, doesn't break normal MP. Migration runs end-to-end on a host drop, with unknown bugs.

### 📅 Session 2 — Cross-account verification (requires playtester)
- Identify what actually breaks: race conditions, timing, GodotSteam `setLobbyOwner` behavior, peer ID collisions, Synchronizer routing
- Triage findings; fix the deterministic-from-logs bugs
- Add minimal UI feedback for the migration window

### 📅 Session 3 — State gap closure
- Decide whether mission progress / aggro / LoS need active mirroring
- Add Synchronizer fields to the entities that need them
- Test that gaps that remain are acceptable (i.e. "enemies pause for 1s then reacquire" is OK, "boss respawns" is not)

### 📅 Session 4+ — Edge cases
- Mid-RPC drops (host dies during damage application)
- Election when two peers drop simultaneously
- Migration during level transition
- Migration during boss fight
- Each of these needs a manual repro recipe; some will only be found in long playtest sessions

### 📅 Session N — Re-flip the flag
- Once playtest evidence shows >95% success rate over multiple sessions, flip `DebugConfig.host_migration_enabled = true` as the default and update `docs/multiplayer.md` to remove the "out of scope" disclaimer

## Testing notes (for the playtester)

To exercise migration:

1. Two Steam accounts in a lobby
2. Set `DebugConfig.host_migration_enabled = true` in the debug overlay (or hardcode for the build)
3. Both peers enter game
4. Host (peer 1) closes Steam process (Task Manager → end Steam.exe) or kills the game process
5. Watch logs on the surviving client; should see `[HostMigration] Host disconnected; starting migration handshake.` followed by `[HostMigration] Elected new host: ...` and `[HostMigration] Migration complete`

Failure modes to report:
- "Migration overlay shown but game frozen forever" — likely a rebind issue
- "All enemies disappear after migration" — re-authority didn't catch them or Spawner removed them
- "Damage stops being applied to enemies" — authority routing
- "Two peers both think they're host" — election race (shouldn't be possible from the math, but report regardless)
- "Steam disconnect within 30s of migration" — `setLobbyOwner` failed; Steam may be holding the lobby
