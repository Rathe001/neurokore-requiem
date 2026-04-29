# Status

Early 3D prototype. Design docs cover most systems; progression/leveling, economy/crafting, end-game loop, and death/failure are still TBD and will be designed as the prototype reveals what's needed.

## Tech

Godot 4 + GDScript, Forward+ renderer. Fixed-camera low-poly 3D with PBR + realistic lighting (pivoted from the original isometric pixel-art plan). See [Tech Stack](design/tech-stack.md).

## Prototype scene

`game/scenes/world/prototype_3d.tscn` — small corridor-and-rooms layout used to exercise core systems.

Working:

- WASD movement, jump (Space), crouch (Ctrl hold)
- Click-to-attack
- Wall collision (per-segment `StaticBody3D` + `BoxShape3D`)
- Doors with slide-open animation, lock state, and `interact()` (F key / skill slot 1)
- Switches that target a door via `NodePath` (toggle / open / close / unlock actions)
- Group-based interactable discovery — player picks the nearest node in `interactables` group within ~2.5m on F
- Always-visible player (depth test off + render priority)
- Line-of-sight wall fade — walls go transparent only when between camera and player and overlapping the player on screen (view-space projection in `tech_wall.gdshader`, fed by `player_world_pos` global shader uniform)
- Persistent corpses with bounded pool — see [Enemies](#enemies) below
- Class UI themes wired through `UIThemeState` (`SPEC_THEMES` lookup keyed by class)
- **Attribute system** — 6 rollable stats (ORT/ING/AMB/DEV/OPT/CLA) derived from equipped items; Soul and Interface are averaged from their origin's three team stats; tier unlock thresholds per relationship type (primary/team/opposing); `PlayerState` tier-crossing signals; data integrity asserts on startup
- **Talents panel** (N) — per-class stat rows with 5-tier node grids; tier bars fill by whole unlocked tiers; tier/node tooltips; locked node preview with unlock % shown; allocation persists in `PlayerState`
- **Character panel stat bar** — compact multibar on character sheet shows stat allocation % with relationship coloring and hover tooltips matching the talents panel
- **FPS mode** (V to toggle) — first-person camera with mouse look, crosshair, fill light; crosshair hover triggers same outline + tooltip as iso mouse hover; skill 1 interacts with crosshair target
- **Platformer elements** — jump over pits; crouch-only corridors (solid ceiling block forces crouch, player is locked in crouching until they clear the zone); enemies that fall into pits die
- **Per-piece floors with true pits** — each room and corridor has its own floor mesh; pit corridors omit floor over the gap; a kill zone at y=−4 destroys anything that falls in
- **World-space floor tiling** — `tech_floor.gdshader` tiles by world position so texture density stays consistent across all floor piece sizes
- **Variant wall/floor shaders** — rooms use smooth panel walls + flat tile floor; corridors use riveted-panel walls + diamond-tread floor (`tech_wall_riveted.gdshader` / `tech_floor_grate.gdshader`). Corridor surfaces sit on a sub-millimetre Y bias so the room surface wins the depth tie at the geometric overlap that hides seams between pieces — without that bias, mismatched coplanar shaders flicker per frame
- **Door-specific shader** — door slabs use `tech_door.gdshader` (mesh-local UVs) so the panel pattern stays anchored to the slab as it slides instead of scrolling across world-space tiling
- **Reflective floor puddles** — procedural blob-masked decal (`puddle.gdshader`) with fbm-distorted silhouette, low-roughness dielectric, and time-driven ripple normals. Placement is deterministic per-room (id-hashed seed) so re-entering doesn't shuffle. Configured per-room via `RoomDef.puddle_count` / `puddle_size`
- **Hoverable interactable scaffolding** — shared base class for clickable world objects (doors, switches, exit pad). Wraps an outline halo around the source mesh, manages hover/tooltip dispatch, and exposes a `reset_state()` hook the level-reset loop calls via the `resettable` group
- **Exit pad** — `PrototypeExit` listens on the `boss_listeners` group; when the boss dies the pad unlocks, pulses, and `interact()` triggers a level reset

## Enemies

Spawning model is **D2-style**, not horde-streaming: enemies are placed at level load, do not respawn during play, and the level can be fully cleared.

- The current `EnemySpawner` in `game/scenes/world.tscn` is a temporary density stress-test, not the target architecture. Don't build features on top of it that assume continuous spawning.
- Future systems should assume placement-at-load, defeated-stays-defeated, level-complete-when-cleared.
- Pooling/spatial-partitioning work for horde density still matters (see [Platform](design/platform.md)) — the pool fills from level data, not a streaming source.
- Persistence of cleared state across save/load belongs with this model.

### Corpses

Dead enemies play their death animation and are left in whatever pose the animation ends on (no flattening). If the rigged model has no death clip, a one-time fallback rotation tips them on the X axis. On completion they move to the `corpses` group, collision is disabled, and the floor ring hides. A corpse manager on the prototype root enforces `MAX_CORPSES = 100` with FIFO pruning.

The flattening tween was removed deliberately — unaltered model in its death pose reads better and reinforces the gritty/body-horror tone (see [Tone](world/tone.md)). Persistent corpses also give visible feedback that a zone has been cleared, reinforcing the no-respawn model.

**Open work:** corpse-pool cap is per-scene right now. When real zones come online, persistence across zone swaps still needs designing — corpses currently die with the scene.

## Open design areas

- Itemization — attribute system core implemented (see [attribute-system.md](design/attribute-system.md)); tier perk mechanics, team stat scaling multipliers, visual metamorphosis, and NPC identity reactions still TBD
- Morality system — [on hold](design/morality-system.md), may resurface as a hidden narrative system
- Progression / leveling
- Economy / crafting
- End-game loop
- Death / failure
