---
name: project_host_migration_plan
description: "Host migration is multi-session work; Session 1 ships scaffolding behind DebugConfig.host_migration_enabled flag, future sessions iterate from cross-account playtest findings"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

User explicitly opted into multi-session host migration work despite the
docs flagging it as out of scope. Session 1 shipped (commit pending):

- `HostMigration` autoload — election + rebind + re-authority
- `DebugConfig.host_migration_enabled` (off by default)
- `PrototypeRoot._on_host_disconnected` routes through migration; falls
  back to `HostDisconnectedScreen` on failure
- Design doc at `docs/host-migration.md` covers architecture +
  iteration roadmap

**Election rule:** surviving lobby member with lowest Steam ID wins.
Deterministic on every peer from `NetState.lobby_members` minus
`lobby_owner_id`.

**State that survives:** anything covered by an existing
`MultiplayerSynchronizer` (enemy pos/HP/state, pickup data, door
locked/open, switch used). Already-replicated state is the win — the
new host inherits it just by re-pointing authority.

**State that doesn't:** AI aggro lists, mission progress counters, LoS
explored cells, in-flight projectiles, in-flight damage RPCs.

**Test path:** requires 2+ Steam accounts. Set the debug flag, kill the
host process, watch the surviving client's logs. Cannot be verified in
the editor / `--mp-force-client` flow because that's same-account
routing (Steam P2P same-id is undefined).

**Iteration plan:** see `docs/host-migration.md` for the full session
roadmap. Each session targets one bug class:
- Session 2: deterministic bugs found in cross-account testing
- Session 3: state gap closure (mirror what's host-only)
- Session 4+: edge cases (mid-RPC drops, races, mid-transition drops)
- Session N: flip flag default-on once >95% success rate

Related: [[project_multiplayer_plan]] for the broader MP architecture
(8 phases shipped); [[feedback_mp_sp_parity]] for the standing rule
that every feature must be SP+MP correct.
