---
name: Enemy navigation — crouch, jump, leash
type: project
description: Enemies follow players through crouch tunnels and across pit pillars. Three coupled systems with non-obvious requirements
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
Three coupled enemy navigation features added 2026-05-02. Each has a synced dependency that's easy to miss when changing one in isolation.

**Crouch tunnels:**
- Navmesh in `level_shell.tscn` is baked at `agent_height = 0.9` (matches enemy `CROUCH_HEIGHT`). If you raise the navmesh agent_height back toward 1.6, low-ceiling corridors will bake as un-pathable and crouch becomes pointless.
- Enemy probes overhead every `CROUCH_PROBE_INTERVAL` (0.25s) with a stand-height capsule shape-cast. If blocked, capsule shrinks (`STAND_HEIGHT 1.7 → CROUCH_HEIGHT 1.0`) and chase speed multiplies by `CROUCH_SPEED_MULT 0.6`.
- Probes are staggered via random initial offset on `_init_enemy` so the population doesn't shape-cast on the same physics tick.

**Pit jumps:**
- `pit_builder._create_pit_jump_links` adds a `NavigationLink3D` between every pillar pair within `JUMP_LINK_MAX_DIST` (4.6m). Without these the navmesh bakes each pillar top as an isolated walkable island.
- Link `travel_cost` is **8.0** (high). Walking is preferred whenever a non-link path exists. Earlier value of 1.5 caused enemies to jump constantly because the link cost barely beat walking.
- Enemy listens to `NavigationAgent3D.link_reached` and triggers `_start_jump` toward the exit position. Gated on `can_jump` (export, default true) and `JUMP_COOLDOWN` (0.8s post-landing lockout).
- `JUMP_MISS_CHANCE` (0.18) rolls per leap — failed jumps undershoot to `JUMP_MISS_DIST_FACTOR` (0.55) of the gap and the enemy lands in the pit (per-pit kill area handles cleanup).
- The takeoff impulse runs in the agent's `link_reached` signal handler, AFTER the enemy's own `_physics_process` for that frame. To prevent the next frame's `is_on_floor()` floor-snap from zeroing the upward velocity, gravity branch in `_physics_process` is `if _state == State.JUMPING or not is_on_floor()` — keep this guard if you refactor.

**Per-enemy capability flags** (`can_crouch`, `can_jump` — both default true):
- `can_crouch=false`: skips the overhead probe; capsule stays at STAND_HEIGHT. Tall enemy will physically bump low ceilings instead of slipping under. Use for melee bruisers that should be funneled away from crouch tunnels.
- `can_jump=false`: silently ignores `link_reached`. The agent will idle at the link entry point. Use for ranged/support enemies that should stay in walking-only zones — encounter design must keep them out of pit rooms or they'll get stuck.

**Leash:**
- `MAX_CHASE_FROM_SPAWN_SQ` (225) still applies, but `KEEP_CHASE_PLAYER_RANGE_SQ` (144 = 12m radius) suppresses the leash when the player is mid-fight. Returning enemies that the player closes on flip BACK to aggro mid-return.
- Returning enemies still take 5% damage and ignore knockback. Don't lower this without re-thinking the kite exploit it was added to block.

**How to apply:** Adding new pit room layouts works automatically — `_create_pit_jump_links` runs from `build_room_pit` for every `RoomDef.pillars` entry. Pillars further than 4.6m centre-to-centre won't get a link and will be unreachable for enemies; either move them closer or raise `JUMP_LINK_MAX_DIST` (and `JUMP_AIRTIME` to keep flight realistic).
