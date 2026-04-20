# Status

Early 3D prototype. Design docs cover most systems; itemization, progression/leveling, economy/crafting, end-game loop, and death/failure are still TBD and will be designed as the prototype reveals what's needed.

## Tech

Godot 4 + GDScript, Forward+ renderer. Fixed-camera low-poly 3D with PBR + realistic lighting (pivoted from the original isometric pixel-art plan). See [Tech Stack](design/tech-stack.md).

## Prototype scene

`game/scenes/world/prototype_3d.tscn` — small corridor-and-rooms layout used to exercise core systems.

Working:

- WASD movement, click-to-attack
- Wall collision (per-segment `StaticBody3D` + `BoxShape3D`)
- Doors with slide-open animation, lock state, and `interact()` (F key)
- Switches that target a door via `NodePath` (toggle / open / close / unlock actions)
- Group-based interactable discovery — player picks the nearest node in `interactables` group within ~2.5m on F
- Always-visible player (depth test off + render priority)
- Line-of-sight wall fade — walls go transparent only when between camera and player and overlapping the player on screen (view-space projection in `tech_wall.gdshader`, fed by `player_world_pos` global shader uniform)
- Persistent corpses with bounded pool — see [Enemies](#enemies) below
- Class/spec UI themes wired through `UIThemeState` (`SPEC_THEMES` lookup keyed by `class/spec`)

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

- Itemization
- Progression / leveling
- Economy / crafting
- End-game loop
- Death / failure
