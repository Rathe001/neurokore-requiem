# Multiplayer

> **Status: In progress.** Phases 0, 1A, 1B, 2A, and 2B are shipped and on `main`. **Phase 2C (cleanup) is the next chunk.** See [Implementation phases](#implementation-phases) below for the full sequence and what each one covers.
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

### 🔜 Phase 2C — Cleanup (NEXT)
The work to make the multiplayer flow safe to leave/re-enter without leaking state. Concrete items:
- **Mid-game disconnect**: when a peer drops, `multiplayer.peer_disconnected` already fires `_on_peer_disconnected` in `PlayersContainer` to despawn their avatar. Verify nothing else holds a reference (HUD, signals, target locks, etc.). Add a brief "X disconnected" notification.
- **Quit-to-menu from a running MP session**: `main_menu.gd._on_quit_to_menu_pressed` already calls `NetState.leave_lobby()` (added in Phase 2A). Audit: does that path also reset `multiplayer.multiplayer_peer` to null on every machine? Does the lobby leave callback propagate to other peers and trigger their despawn?
- **Despawn animation**: Currently `queue_free` is a hard snap. A 0.2s fade or character-drop would read better. Probably do this when we have proper death animation work in Phase 3+.
- **Reconnection** (nice-to-have): Steam holds connections briefly; if a peer drops and rejoins within ~30s, ideally we re-bind without forcing them through the lobby browser. Defer if it's significant work.
- **Audit `_alive` / `_health` / damage code paths on remote players**: in Phase 2B I early-return on `_is_remote_player()` in `_physics_process` etc., but `take_damage`, `_die`, `respawn` aren't gated. Phase 3 will properly handle these via authoritative state, but for 2C add defensive early-returns so a stray call from gameplay code doesn't NPE on a remote player's null `_combat`.

### Phase 3 — Enemies ✅

Enemies spawn into a dedicated `EnemiesContainer` with a `MultiplayerSpawner` that replicates host spawns to all clients. Each enemy carries a `MultiplayerSynchronizer` broadcasting `global_position`, `Visual:rotation`, `net_health`, `net_max_health`, and `net_state` (State enum as int). Clients skip AI entirely (`_is_remote_enemy()` gate in `_physics_process`) and drive animations + health bars from synced values. Death detected client-side via `net_state == DEAD`; corpse cleanup handled by the spawner's removal replication.

Damage from player combat (cone/AoE/hitscan/exile) routes through `_deal_damage()` in `PlayerCombat` → `request_damage.rpc_id(1, ...)` on clients, with the host applying it authoritatively via `take_damage()`. XP, loot drops, and death side-effects only fire on the host. Spawning (`_spawn_wave`, `_spawn_boss`, `reset_level`) is gated behind `_is_mp_client()`.

**Not yet covered (Phase 4):** projectile, grenade, trap, telekinesis, and doomsayer damage paths are gated against client-side application but don't send RPCs yet — those hits won't register on clients until Phase 4.

### 📅 Phase 4 — Combat events
Projectile spawn replication: host RPCs spawn event with seed + direction; clients dead-reckon trajectory and only the host evaluates collisions. Hitscan: host computes beam endpoint, broadcasts visual via RPC. Impact burst, damage numbers, hit flashes all via RPC. The combat visuals you'd expect.

### Phase 5 — Loot
Loot drop with `owner_id` field as designed. Manual-drop UI / inventory action ("Drop" button or drag-out-of-inventory). Pickup validation. Visual distinction between owned and free-for-all drops.

### Phase 6 — World state
Level / zone transition sync (host triggers, all clients follow). Door / switch / interactable state replicated. Host's local save now stores world progress (current zone, switches flipped, bosses killed). Other players' saves only store their character data.

### Phase 7 — Drop-in
Mid-session join handshake. Host serializes a state snapshot — current zone, all live enemies, all world loot, all current players' positions — and sends to the joining peer. Joiner spawns at a safe entry point (zone start) and starts receiving normal updates. The hard part is making the snapshot complete enough that nothing visible desyncs.

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
