# Multiplayer

> **Status: Planned.** Lobby UI scaffolding is in place (Multiplayer button on the startup screen, currently disabled at `startup_screen.gd:123`). No networking is implemented yet. This document is the design intent and the implementation roadmap. Phases are sequenced in the order we'll actually build.

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

### Phase 0 — Foundation
Add `godot-steam-multiplayer-peer` to `addons/`. Initialize Steam in an autoload (`SteamState`?) using App ID 4689320 (already configured in Steamworks). Stub out a `NetState` autoload to manage lobby + peer lifecycle. Verify the plugin compiles and Steam initializes on launch.

### Phase 1 — Lobby
Enable the Multiplayer button. Build the lobby UI: Create Game / Browse Games / Friends List. Create Game collects name + party size + privacy (public/friends/private). Browse lists Steam lobbies with name, host, player count. Join transitions to a pre-game lobby room (chat + ready check). Start transitions to the existing `level_shell.tscn` with networking active. Test: 2 clients on different machines see each other in a Steam lobby, can chat, can launch into the game scene together (no gameplay sync yet).

### Phase 2 — Player presence
Spawn remote-player avatars on peer connect. Replicate own player position via `MultiplayerSynchronizer`. Despawn on disconnect. No combat — just walk around in the same world together. Confirms the transport works for the simplest possible state.

### Phase 3 — Enemies
Move enemy authority to host. Spawners run only on host; spawn events RPC-broadcast to clients with deterministic IDs. Position + state machine sync via synchronizers. Damage application via RPC (host computes, broadcasts hit visuals + HP delta). Death events RPC. After this phase, all 4 players can fight enemies in the same world.

### Phase 4 — Combat events
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

### Why `godot-steam-multiplayer-peer` over `GodotSteam`
Both are mature plugins, but `godot-steam-multiplayer-peer` presents as a standard Godot `MultiplayerPeer`, which means the rest of the codebase uses normal `@rpc` and `MultiplayerSynchronizer` nodes — no Steam-specific calls scattered through gameplay code. Easier to swap transports later (e.g., for a stress-test ENet build) without rewriting.

### Why 4 players
Each peer multiplies replication traffic by ~4× per replicated entity. At horde density, 4 is already pushing CPU on the host. 8 would force per-enemy delta compression or aggressive spatial culling — engineering work that doesn't pay off until we have multiplayer working at 4 first.

## Open questions

- **Host disconnect handling**: kick everyone back to lobby, or attempt host migration? Recommendation: kick to lobby for v1. Migration is a separate project.
- **Reconnect after brief drop**: Steam can hold the connection open ~30 s. Worth wiring a reconnect path if the engineering cost is small.
- **Scaling enemy count in MP**: hard cap (spawner refuses to exceed 50 active) or graceful degradation (fewer per pack, longer respawn cooldowns)?
- **Cross-region play**: Steam relay handles it transparently, but latency to a host on another continent will be 200ms+. Worth showing ping in the lobby browser.
- **Pet / drone replication**: Automaton drones, charm pets, IED traps — all need authority decisions. Probably "spawn-side authority" — whoever owns the controlling entity owns the spawned ones too, but they're host-replicated like enemies.

## Non-goals at launch

- PvP / arena / dueling
- Cross-platform (PC ↔ mobile ↔ console)
- Dedicated server option
- Spectator mode
- Cheat-resistance beyond "host runs the sim, reject obviously-impossible client claims"
- True session persistence (covered above)
