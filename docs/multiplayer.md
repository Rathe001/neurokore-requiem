# Multiplayer

> **Status: In progress.** Phases 0 through 7 + 2C are shipped and on `main`. All planned networking phases are complete. See [Implementation phases](#implementation-phases) below for the full sequence and what each one covers.
>
> **Verification gap to keep in mind:** local testing uses one Steam account in two processes (editor + `--mp-force-client` .exe), which is enough to verify lobby flow, scene transitions, and avatar spawning, but Steam P2P routing same-id-to-itself is undefined — actual cross-peer position sync, RPCs, and member-join callbacks need real two-account testing or shipping to playtest. Anything in Phase 2B+ that involves traffic between peers should be assumed *code-correct, runtime-unverified* until we get a second account into a lobby.

## Design pillars

- **Coop PvE only at launch.** No PvP, no dueling, no arena.
- **4-player party cap.** Each additional peer multiplies replication traffic and on-screen chaos; 4 is what the codebase can carry at horde-density without major rework.
- **Steam-first, no infrastructure costs.** Steam Lobby for matchmaking, Steam relay for game traffic. Zero monthly server bill.
- **Drop-in joins.** Mid-session joins are supported; not lobby-only.
- **Per-player characters; world state is the host's session.** Your character + inventory + talents survive across rooms. The world you're playing in belongs to whoever hosted it and ends when they leave.

## Architecture

### Transport

- **Plugin: [`godot-steam-multiplayer-peer`](https://github.com/expressobits/godot-steam-multiplayer-peer)**. Wraps Steam's `SteamNetworkingSockets` as a standard Godot `MultiplayerPeer`, so the rest of the codebase looks identical to ENet. Newer than `GodotSteam` but better fit for Godot 4's high-level multiplayer API.
- **Steam Lobby** for matchmaking, friend invites, server browser. Free, Valve-hosted.
- **Steam relay** for in-game traffic. Routes around symmetric NAT cases that direct P2P can't solve. Free.

### Authority

**Host-authoritative.** The peer who created the lobby runs the simulation:

- Enemy AI, positions, state machines
- Damage rolls, crit rolls, accuracy rolls
- Loot generation and rarity rolls
- Level/zone state — doors, switches, interactables
- Spawn timing, pack composition, named-monster rolls

Clients control:

- Their own character's input (movement, attacks, skill cast)
- Their own inventory and talent allocations

Client-side prediction (with host-authoritative rollback on rejection):

- Own player position and animation state

### Persistence — what's actually possible

The original ask was Battle.net-style "rooms persist for 30 minutes after the last player leaves." That model requires a centralized server holding the room object, which is what Battle.net is — Blizzard's cluster, not P2P. With peer-hosted games, when the host's process exits, the simulation evaporates with it. Host migration is technically possible but a multi-week stability project on its own and not where indie dev time should go.

What we offer instead:

- **Lobby**: persists as long as anyone is in it. Steam transfers ownership automatically if the creator leaves. So a friend can stay in the lobby and the room slot survives.
- **Game session**: lives in the host's process. Ends when the host disconnects.
- **Character data**: per-player local save + Steam Cloud, totally independent of any room. Levels, items, talents persist.

The practical effect: leave a game, come back, your character has all its stuff. The world you were in is gone, but you can join or host a new one and pick up where you left off in your *own* progression.

## Replicated state

### Continuous (positions, basic stats)

| Entity | Field | Frequency |
|---|---|---|
| Player | position, facing | 20 Hz |
| Player | animation state | on change |
| Player | HP / resource | on change |
| Enemy | position | 10 Hz when active, 0 Hz when idle/leashed |
| Enemy | state machine state | on change |
| Enemy | HP | on change |

### Event RPCs

- Damage applied (for damage numbers, hit flash visuals)
- Projectile spawn (host RPCs spawn event with deterministic seed + direction; clients dead-reckon)
- Hitscan beam + impact burst
- Loot drop (item data + `owner_id`)
- Loot pickup
- Enemy death
- Door / switch state change
- Level / zone transition

### Per-player local (never replicated)

- Inventory contents
- Talent allocations
- Skill cooldown timers
- HUD state, settings, accessibility config

## Loot ownership

Every world pickup carries an `owner_id: StringName` field.

- **Auto-drops** (enemy dies, chest opens, named monster falls): the host generates one drop per player and stamps each with that player's session id. Other players see the drop in the world but can't pick it up. Visual cue: dimmer outline / different ring color.
- **Manual drops** (player drags an item out of inventory and drops it): `owner_id` is empty. Any player can pick it up. This is how players hand off items — the trade mechanism for the launch.

Pickup flow: client requests pickup via RPC → host validates `owner_id` matches the requesting player or is empty → host broadcasts removal to all clients. No client-side speculative removal — pickups always wait for host confirm.

## Performance budget

At 4 peers (3 outbound + 3 inbound per peer) with ~50 active enemies:

| Stream | Math | Bandwidth |
|---|---|---|
| Enemy positions | 50 × 10 Hz × 3 peers × ~16 bytes (quantized) | ~24 KB/s up |
| Player positions | 4 × 20 Hz × 3 peers × ~16 bytes | ~4 KB/s up |
| Event RPCs (avg) | spiky | ~5 KB/s up |
| **Total** | | **~33 KB/s up, similar down** |

Well within typical residential bandwidth. Bigger constraint is host CPU running 4× as many client-input loops alongside the world sim.

**Hard MP horde cap: ~50 active enemies on screen** (vs. the SP target of 100+). Spawners need to throttle when in MP. Endgame "Vampire Survivors scale" hordes are a single-player-only feature unless we move enemy authority off the host (probably never).

## Implementation phases

Each phase ends with a runnable, testable game. Don't conflate phases.

The legend: **✅ shipped**, **🔜 next up**, **📅 planned**.

### ✅ Phase 0 — Foundation (commit `5a64928`)
Installed GodotSteam 4.18.1 GDExtension into `game/addons/godotsteam/`. Wired `SteamState` autoload (initialises Steam SDK via `steamInitEx`, ticks `Steam.run_callbacks()` per frame) and `NetState` autoload stub. App ID 4689320 baked into `steam_appid.txt` so the editor launch works without going through Steam.

### ✅ Phase 1A — Lobby plumbing (commit `1926fb6`)
`NetState` gained the Steam Lobby API: `create_lobby` / `join_lobby` / `leave_lobby` / `request_lobby_list` / `send_chat`. Hooked Steam callbacks (`lobby_created`, `lobby_joined`, `lobby_chat_update`, `lobby_message`, `lobby_match_list`). Tracks `lobby_id`, `lobby_owner_id`, `mode` (OFFLINE / HOST / CLIENT), and `lobby_members` for UI to read.

### ✅ Phase 1B — Lobby UI (commit `a00b429`)
Four panels under `game/scripts/ui/`: `multiplayer_panel`, `create_lobby_panel`, `browse_lobbies_panel`, `lobby_room_panel`. Wired through `startup_screen.gd` with NetState's `lobby_created_result` / `lobby_joined_result` driving the transitions. Lobby room has member list (host tagged), chat log + input, Leave + Start buttons.

### ✅ Phase 2A — Networked transport + scene transition (commit `2bebf03`)
On host's Start, `NetState.start_game()` creates a `SteamMultiplayerPeer` via `create_host(0)`, registers each lobby member as a known peer, binds `multiplayer.multiplayer_peer`, then sets `started=1` lobby data. Clients pick up the lobby data update (with a 1 Hz polling fallback) and `create_client(host_steam_id, 0)`. Both fire `game_starting`, the UI swaps to `level_shell.tscn`. `--mp-force-client` CLI flag added for same-Steam-id local testing — see [Local two-instance testing](#local-two-instance-testing).

Plus a defensive cleanup pass (commit `5fb3465`): quit-to-menu now calls `NetState.leave_lobby()` so a leaked peer can't bleed into a subsequent SP session.

### ✅ Phase 2B — Per-peer player avatars + position sync (commit `efe84b4`)
Restructured the player from a baked node in `level_shell.tscn` into a runtime-spawned scene. `scenes/prototype/player.tscn` (extracted) now carries a `MultiplayerSynchronizer` replicating `global_position`, `Visual.rotation`, and `net_moving`. New `PlayersContainer` script in `level_shell.tscn` spawns one Player per lobby member into a shared container; node paths match across machines so the synchronizers can route. `prototype_player.gd` now branches on `_is_remote_player()` — non-authority avatars get `_ready_remote()` (anim + mesh shadow layer only) and skip combat / abilities / overlays. Remote anim choice (idle vs run) is driven from the synced `net_moving` flag.

**Critical detection rule:** `multiplayer.has_multiplayer_peer()` is misleading because GodotSteam plumbing leaves it set in SP — use `NetState.is_in_lobby()` for the actual SP/MP discriminator everywhere.

Verified locally that both clients spawn two Player nodes (own + remote) on each side. Cross-peer sync NOT verified — same-account routing is undefined per Steam.

### Phase 2C — Cleanup ✅

Hardened the multiplayer flow for safe leave/re-enter and fixed null-dereference risks on remote players.

- **Quit-to-menu audit**: confirmed `main_menu.gd._on_quit_to_menu_pressed` → `NetState.leave_lobby()` → `_teardown_peer()` correctly closes the `SteamMultiplayerPeer`, sets `multiplayer.multiplayer_peer = null`, resets all lobby state, and emits `lobby_left`. Other peers see the disconnect via `peer_disconnected` → `_despawn_for`. No leaked state.
- **Despawn animation**: replaced hard `queue_free` in `PlayersContainer._despawn_for` with a 0.25s scale-down tween before freeing, so disconnects don't look like a hard pop.
- **Remote player safety audit**: added null guards on all public methods that access subsystems not initialized on remote players (`_combat`, `_shield`, `_grenade`, `_doomsayer`, `_ied`, `_drone_swarm`). Methods guarded: `fire_exile_shot`, `get_cooldown_ratio`, `get_cooldown_remain`, `get_shield_buff_kind`, `get_shield_buff_state`, `get_charm_count/max`, `get_trap_count/max`, `get_drone_count`. `take_damage`, `_die`, and `respawn` were already gated on `_is_remote_player()`.
- **Reconnection** deferred: Steam's brief connection hold makes this a nice-to-have, but re-binding a peer mid-session is non-trivial. Late joiners can rejoin through the lobby browser via Phase 7's drop-in flow.

### Phase 3 — Enemies ✅

Enemies spawn into a dedicated `EnemiesContainer` with a `MultiplayerSpawner` that replicates host spawns to all clients. Each enemy carries a `MultiplayerSynchronizer` broadcasting `global_position`, `Visual:rotation`, `net_health`, `net_max_health`, and `net_state` (State enum as int). Clients skip AI entirely (`_is_remote_enemy()` gate in `_physics_process`) and drive animations + health bars from synced values. Death detected client-side via `net_state == DEAD`; corpse cleanup handled by the spawner's removal replication.

Damage from player combat (cone/AoE/hitscan/exile) routes through `_deal_damage()` in `PlayerCombat` → `request_damage.rpc_id(1, ...)` on clients, with the host applying it authoritatively via `take_damage()`. XP, loot drops, and death side-effects only fire on the host. Spawning (`_spawn_wave`, `_spawn_boss`, `reset_level`) is gated behind `_is_mp_client()`.

### Phase 4 — Combat events ✅

All player damage sources (hitscan, projectile, grenade, trap, telekinesis, doomsayer DoT) route through `PrototypeEnemy.deal_damage()` — clients send `request_damage.rpc_id(1, ...)`, host applies authoritatively. Host broadcasts hit visuals (damage numbers, hit flash, squash) to all clients via `_client_show_hit` RPC on each enemy.

New `CombatVisuals` autoload wraps `PrototypeAttackIndicator` with RPC broadcasting: beams, hit cones, hit radials, impact bursts, explosions, and telegraphs (cone + radial) are all visible to every peer. Cosmetic-only, unreliable transport — a dropped visual has zero gameplay impact. Remote clients receive world-position + is_player flag; a temporary anchor Node3D is created at the origin for the indicator to attach to, then freed (immediately for impact visuals, delayed for telegraphs that parent to the host).

### Phase 5 — Loot ✅

New `PickupsContainer` (sibling of `EnemiesContainer`) holds all world pickups with a `MultiplayerSpawner` using a custom `spawn_function`. Item data is serialized via `Item.to_dict()` / `Item.from_dict()` (Skills stored as `resource_path` strings) and deserialized on every peer.

Per-player instanced drops: when an enemy dies in MP, the host rolls one independent item per lobby member, each stamped with that player's peer id as `owner_id`. Non-owned item labels are dimmed to 35% alpha. Credits are shared (not instanced) and auto-collect for the nearest local player.

Host-validated pickup: clients request via RPC on PickupsContainer (persistent node); host validates `owner_id`, confirms with serialized item data, then `queue_free`s (spawner replicates removal). Loot crates use the same per-player instanced drop pattern with host-only open + visual RPC. Manual inventory drops have empty `owner_id` (anyone can pick up). EntityPool is bypassed for credits in MP (spawner needs fresh instances); SP retains pooling.

### Phase 6 — World state ✅

Door, switch, and exit pad interactions are host-authoritative: clients send `_request_interact.rpc_id(1)`, host validates and performs the action, then broadcasts state changes to all clients. Doors broadcast open/close slide + unlock/relock counter via `_client_set_open` / `_client_unlock` / `_client_relock` RPCs. Switches broadcast `_client_mark_used` for one-shot deactivation. Exit pad broadcasts `_client_unlock` when the boss dies. Boss-death group callbacks (`on_boss_died`) are host-only gated on doors and exit.

Level reset (NG+ transition) is synchronized: host picks a seed, broadcasts `_client_reset_level(seed, is_procgen)` to all clients. Both peers clear enemies/corpses/pickups and rebuild: procgen path rebuilds geometry from the shared seed (deterministic layout), legacy path resets interactable states. Enemy spawning during rebuild is skipped on clients via an early return in `EnemySpawner.spawn_in_bounds` — enemies arrive from the host through `EnemiesContainer`'s `MultiplayerSpawner`. Both peers advance NG+ and reset the player independently.

### Phase 7 — Drop-in ✅

Mid-session join support. Three pieces: (1) **NetState late-join plumbing** — host calls `_peer.add_peer(new_id)` in `_on_lobby_chat_update` when a member joins during an active game, accepting their SteamMultiplayerPeer connection. The existing `_check_started_flag()` path already handles the client side (reads `started=1`, creates peer, fires `game_starting`). (2) **Level seed sync** — host stores the procgen seed in Steam lobby data (`LOBBY_SEED_KEY`) on initial build and every level reset. `LevelBuilder._ready()` reads it on the client side so late joiners build identical geometry. Host pins `rng_seed` to a captured value (not 0/time-fallback) so the seed is always deterministic and retrievable. (3) **World state snapshot** — after scene load, the late joiner sends `_request_snapshot.rpc_id(1)` to the host. Host responds with `_deliver_snapshot` containing all live enemies (position, rotation, health, state, level, boss flag, display name, node name), all pickups (item data or credit amount, position, owner_id, node name), and all interactable states (door locked/open/unlock-counter, switch used, exit locked). Joiner recreates enemies and pickups with matching node names so `MultiplayerSynchronizer` updates route correctly for ongoing play. `PlayersContainer._on_peer_connected` handles avatar spawning (already shipped in Phase 2B). Future spawns (enemies, pickups) arrive normally via `MultiplayerSpawner`.

## Technical decisions

### Why host-authoritative, not deterministic lockstep
Lockstep requires perfect determinism (RNG, floating point, frame timing) across peers and forces lockstep at the slowest peer's framerate. Host-authoritative is simpler, more permissive of jitter, and standard for coop PvE.

### Why Steam Lobby over a custom matchmaker
Free; built-in NAT traversal, friend invites, server browser. Only cost is tying launch to Steam — already the launch platform.

### Why GodotSteam (not godot-steam-multiplayer-peer)
We originally planned on `godot-steam-multiplayer-peer`. When we went to install it during Phase 0, the upstream repo had been paused (Dec 2025) with a notice steering users to GodotSteam. GodotSteam itself merged its old separate `MultiplayerPeer` repo into the main 4.x branch, so the all-in-one GodotSteam GDExtension now provides the Steam SDK wrapper, the `SteamMultiplayerPeer` (which still presents as a standard Godot `MultiplayerPeer`), and Stats / Cloud / Friends — one install instead of two. Project lives on Codeberg now (`codeberg.org/godotsteam/godotsteam`), not GitHub.

### Why 4 players
Each peer multiplies replication traffic by ~4× per replicated entity. At horde density, 4 is already pushing CPU on the host. 8 would force per-enemy delta compression or aggressive spatial culling — engineering work that doesn't pay off until we have multiplayer working at 4 first.

## Open questions

- **Host disconnect handling**: kick everyone back to lobby, or attempt host migration? Recommendation: kick to lobby for v1. Migration is a separate project.
- **Reconnect after brief drop**: Steam can hold the connection open ~30 s. Worth wiring a reconnect path if the engineering cost is small.
- **Scaling enemy count in MP**: hard cap (spawner refuses to exceed 50 active) or graceful degradation (fewer per pack, longer respawn cooldowns)?
- **Cross-region play**: Steam relay handles it transparently, but latency to a host on another continent will be 200ms+. Worth showing ping in the lobby browser.
- **Pet / drone replication**: Automaton drones, charm pets, IED traps — all need authority decisions. Probably "spawn-side authority" — whoever owns the controlling entity owns the spawned ones too, but they're host-replicated like enemies.

## Local two-instance testing

Without a second Steam account, you can run the editor + an exported `.exe` against the same Steam user — useful for verifying the lobby flow, scene transition, and any host/client UI divergence. The catch: NetState identifies the host by `lobby_owner_id == SteamState.steam_id`, which is true on both processes when they share an account, so the second process incorrectly identifies as host.

Workaround: launch the second instance with **`--mp-force-client`**:

```
build\windows\neurokore-requiem.exe --mp-force-client
```

This forces `is_host()` / `is_client()` / `is_authority()` to return client-side values regardless of Steam IDs. **Dev-only — never enable this in shipped builds.** Real multi-user testing (different Steam accounts) doesn't need the flag.

What this *does* validate locally: lobby creation, joining, browsing, chat plumbing, the Start transition, scene loading on both ends. What it *doesn't* validate: actual peer-to-peer network traffic between two same-account processes (Steam routing same-ID-to-itself is undefined). For that, real two-account testing is required and will happen for free once playtest builds reach actual users.

## Non-goals at launch

- PvP / arena / dueling
- Cross-platform (PC ↔ mobile ↔ console)
- Dedicated server option
- Spectator mode
- Cheat-resistance beyond "host runs the sim, reject obviously-impossible client claims"
- True session persistence (covered above)
