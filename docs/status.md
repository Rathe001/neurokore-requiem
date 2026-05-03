# Status

Early 3D prototype. Design docs cover most systems; progression/leveling, economy/crafting, end-game loop, and death/failure are still TBD and will be designed as the prototype reveals what's needed.

## Tech

Godot 4 + GDScript, Forward+ renderer. Fixed-camera low-poly 3D with PBR + realistic lighting (pivoted from the original isometric pixel-art plan). See [Tech Stack](design/tech-stack.md).

## Prototype scene

`game/scenes/world/prototype_3d.tscn` — corridor-and-rooms layout exercising core systems.

### Player & controls
- WASD movement, jump (Space), crouch (Ctrl hold), step-up over short obstacles
- Click-to-attack with **lock-on auto-aim** when LMB is held over an enemy
- **FPS mode** (V to toggle) — mouse-look first-person view; crosshair hover gives the same outline + tooltip as iso hover
- Group-based interactable discovery (F) — picks nearest node in `interactables` within ~2.5m
- Always-visible player (depth test off + render priority)
- Character creation uses **♂ / ♀** symbols (replaced "He/Him" / "She/Her" pronoun text)

### Combat
- **Player combat component** — `PlayerCombat` child node owns damage resolution (cone / AoE / projectile / hitscan), damage rolling, crits, cooldown tracking
- **Ranged weapons** — `PROJECTILE` and `HITSCAN` targeting modes; projectile nodes travel straight, self-destruct on hit / range; hitscan uses ray + narrow cone query clipped to wall distance; line telegraphs for both
- **All six specialist tier perks shipped** — Exile (Count), Amalgamation (Forged, with per-arm spawn offsets + dynamic stagger), Drone Swarm (Automaton, wandering hover drones with wall collision), IED (Survivalist, proximity traps tossed at cursor), Telekinesis (Polymath, grab-and-slam bolts), Doomsayer (Enculted, aura proccing stun / charm / weaken with persistent FIFO charm cap). See [tier perk table](design/attribute-system.md#specialized-class-tier-perks).

### Stats & UI
- **Attribute system** — 6 rollable stats (ORT/ING/AMB/DEV/OPT/CLA); Soul/Interface derived from origin kore-stat averages; tier thresholds per relationship type (primary / kore / opposing); tier-crossing signals; contribution-weighted stat scaling drives HP and resource maxes (primary 1.0x, kore 0.25x, opposing 0.10x)
- **Talents panel** (N) — per-class stat rows, 5-tier node grids, tier bars, locked-node preview with unlock %, allocation persists in `PlayerState`
- **Character panel stat bar** — compact multibar showing stat allocation % with relationship coloring and matching tooltips
- **Class UI themes** — `UIThemeState.SPEC_THEMES` keyed by class
- **HP & resource scaling** — base + level-ups + stat bonus tracked separately; gear swaps proportionally adjust current HP/resource

### Level & world
- **Modular level builder** — per-piece walls, floors, corridors, pits, doors, switches; rooms and corridors instantiated from `RoomDef` / `CorridorDef`
- **Doors & switches** — slide-open animations, lock state, `interact()`; switches target doors by `NodePath`
- **Variant wall/floor shaders** — smooth panel walls + flat tile (rooms); riveted panels + diamond tread (corridors). Corridor surfaces sit on a sub-mm Y bias so the room shader wins z-fight at the deliberate geometric overlap. Doors use mesh-local UVs (`tech_door.gdshader`)
- **Wall fade** — walls fade only when between camera and player AND overlapping the player on-screen (view-space test in `tech_wall.gdshader`)
- **World-space floor tiling** — texture density stays consistent across all floor piece sizes
- **Reflective floor puddles** — fbm-distorted decal with low-roughness dielectric + ripple normals; deterministic per-room placement
- **Per-piece floors with true pits** — pit corridors omit floor over the gap; kill zone at y=−4 destroys anything that falls in
- **Crouch corridors** — overhead probe forces enemies to crouch; lookahead probe + body-clearance probe distinguish "low ceiling" from "wall"
- **Pit-pillar nav links** — `NavigationLink3D` between pillars; enemies launch with arc impulse (some miss = fall in)
- **Hoverable interactable scaffolding** — shared base for clickable world objects with outline halo + tooltip dispatch + `reset_state()` hook
- **Spawn room starter chest** — locked exit door unlocked by looting the chest (rolls 2H weapon OR 1H + offhand at common rarity)
- **Exit pad** — listens on `boss_listeners`; unlocks when the boss dies, pulses, `interact()` triggers level reset

### Lighting
- **Proximity lighting** — lights dim with distance + LoS (`ProximityLighting` autoload); per-zone profiles drive outdoor vs. indoor falloff
- **Equippable light sources** — flashlight / scanner / UV; light state synced to held item
- **LoS culling** — enemies and corpses outside player line-of-sight skip non-essential ticks; AI gates use the same cached LoS

### Performance
- **Entity pooling** — `EntityPool` autoload for enemies, projectiles, credit pickups, item pickups; pooled entities implement `_pool_release()` / `reset()`
- **SpatialGrid** autoload for radius / cone queries (replaces per-tick get_tree scans)
- **Aggro cascade cap** — group aggro chain depth-capped at 2 (`MAX_AGGRO_CASCADE`)

## Enemies

Spawning model is **D2-style**, not horde-streaming: enemies are placed at level load, do not respawn during play, and the level can be fully cleared.

- The current `EnemySpawner` in the prototype scene is a temporary density stress-test, not the target architecture. Don't build features on top of it that assume continuous spawning.
- Future systems should assume placement-at-load, defeated-stays-defeated, level-complete-when-cleared.
- Pool/spatial-partition work for horde density still matters (see [Platform](design/platform.md)) — the pool fills from level data, not a streaming source.

### Enemy classes (overlays)
- `EnemyClass` resource at `game/resources/enemies/classes/{id}.tres` defines per-archetype tuning: melee / ranged attack mode, attack range / cooldown / windup, optional support overlay (heal / damage-buff aura). Combinations like melee+heal or ranged+buff are first-class.

### Monster packs (rare-pack affixes)
- `MonsterAffix` resources at `game/resources/enemies/affixes/`. EnemySpawner rolls per spawn point; leader + companions share the affix list. Affix multipliers compound onto level-rolled stats and recolor the floor ring.

### Named monsters
- `NamedMonster` resources at `game/resources/enemies/named/`. 0.5% per spawn, preempts pack roll, forces identity (display name, ring tint, visual scale, HP/damage mults) and floors drop rarity.

### Corpses
- Dead enemies play their death animation in-pose (no flattening); fallback X-axis tip if no death clip exists. They move to the `corpses` group, collision disabled, floor ring hidden. Corpse manager enforces `MAX_CORPSES = 100` with FIFO pruning.
- Persistent corpses give visible "this zone is cleared" feedback. The flattening tween was removed deliberately to reinforce the body-horror tone.
- **Open:** corpse persistence across zone swaps — corpses currently die with the scene.

## Open design areas

- **Tier perk mechanics for origin classes** — Analog/Cyborg balance perks. Specialist perks all ship.
- **Kore stat scaling multipliers** — currently ~0.25x placeholder
- **Visual metamorphosis** — modular meshes + shader channels per stat
- **NPC identity reactions** — reps/vendors react to dominant stat identity
- **Morality system** — [on hold](design/morality-system.md), may resurface as hidden narrative system
- Progression / leveling, economy / crafting, end-game loop, death / failure
