# Conventions

Tech stack, engineering conventions, and reference inspirations. Intentionally short — for anything not covered here, follow the [official GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).

## Tech stack

- **Engine:** Godot 4. Forward+ renderer on PC (PBR, SDFGI, volumetrics, dynamic shadows — the identity look). Mobile renderer path exists for the eventual mobile port (lower fidelity, same game).
- **Language:** GDScript by default — Python-like, integrates tightly with the editor, fast iteration. Performance escape hatch: hot paths can move to C# or GDExtension (C++/Rust) when profiling demands it. Deliberate later optimization, not an upfront architectural choice.
- **3D modeling & animation:** Blender (long-term). glTF export to Godot. Free, open source, strong interop.
- **2D tooling:** Aseprite for UI icons, decals, emissive patterns, hand-painted texture work.
- **Build pipeline:** `tools/steam/prepare_build.py` rotates `[Unreleased]` in the changelog into a versioned section, bumps semver, and writes the SteamPipe VDF `desc`. `deploy.sh` / `deploy.bat` chain it with the Godot export and `steamcmd` upload.

### Performance pillars

- Disciplined dynamic-light culling from the start — hordes + many dynamic lights is the danger combo.
- Poly budget per character kept low; surface detail comes from normal/roughness/emissive textures.
- Object pooling for entities and VFX (see `EntityPool` autoload).
- LOD on static world meshes where horde views are wide.
- Spatial partitioning for proximity queries (see `SpatialGrid` autoload).

Target spec: average PC, integrated graphics, 8GB RAM.

## Naming

| What | Convention | Example |
|---|---|---|
| Variables and functions | `snake_case` | `current_health`, `take_damage()` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_HEALTH`, `AOE_ATTACK_RANGE` |
| Classes (via `class_name`) | `PascalCase` | `class_name Player` |
| Private members | `_leading_underscore` | `_attack_cd`, `_die()` |
| Files (scenes and scripts) | `snake_case` | `world.tscn`, `enemy.gd` |
| Node names in scenes | `PascalCase` | `Player`, `CollisionShape2D` |
| Group names | `lowercase plural` | `&"enemies"`, `&"projectiles"` |

## Type hints

Always use them.

- Variables: `var x: int = 5` or `var x := 5` (inferred)
- Function parameters and return: `func damage(amount: int) -> void:`
- `@export`: `@export var max_health: int = 100`

## Annotations

- **`class_name Foo`** at the top of a script makes the type usable as an annotation across the codebase. Add it to any script other scripts will reference by type.
- **`@export`** exposes a variable in the editor's Inspector. Use it for any value that should be tunable per-instance without editing code.
- **`@onready var ref := $ChildName`** for child-node references — defers the lookup until the node is in the tree.

## Magic numbers

Numeric tuning values (speeds, damages, cooldowns, ranges) belong in named `const`s at the top of the script. If the value should be tunable per-instance, use `@export var` instead.

## Member order

```
extends Foo
class_name Bar

# 1. Signals
signal died

# 2. Constants
const SPEED := 240.0

# 3. @export variables
@export var max_health: int = 100

# 4. Other variables
var current_health: int
var _attack_cd := 0.0

# 5. @onready references
@onready var visual: Polygon2D = $Visual

# 6. Built-in lifecycle methods (_ready, _process, _physics_process, etc.)
func _ready() -> void: ...

# 7. Public methods
func take_damage(amount: int) -> void: ...

# 8. Private methods (_underscore prefix)
func _resolve_skill(index: int) -> Skill: ...
```

## StringName literals

Use `&"action_name"` (StringName literal) rather than `"action_name"` for input-action names and group names. Same behavior, signals intent, fractionally faster (no allocation).

## Built-in constants

Prefer `Vector2.ZERO`, `Color.WHITE`, `Color.TRANSPARENT` over numeric literals where a named constant exists.

## Loose coupling via groups

Use Godot's group system (`add_to_group(&"enemies")`, `get_tree().get_nodes_in_group(&"enemies")`) instead of direct references when an entity needs to find others by category. Avoids wiring scene trees together explicitly; scales naturally as content grows.

## Scene files

- One scene per file.
- Edit scenes in the Godot editor when possible. Hand-editing `.tscn` text is fine for small structural changes; the editor handles UIDs and sub-resources more reliably.
- Each reusable entity (player, enemy type, projectile) should live in its own scene file so it can be instanced.

## Infrastructure in place

- **`SpatialGrid` autoload.** O(nearby) proximity queries. All entities register/unregister; the grid updates each physics frame. Use `query_radius()`, `query_cone()`, `query_nearest()` instead of `get_nodes_in_group()` for proximity-dependent logic.
- **`EntityPool` autoload.** Recycles `Node3D` instances. Use `EntityPool.acquire(scene)` / `EntityPool.release(node)` instead of `instantiate()` / `queue_free()` for frequently spawned entities. Pooled today: enemies, projectiles, credit pickups. Pooled entities implement `_pool_release()` (cleanup before parking) and `reset()` (re-init after acquire).
- **Resource loaders use explicit file lists.** `DirAccess.list_dir_begin()` works in the editor but returns empty in exported Godot 4 builds. Loaders that walk `res://` for `.tres` files (perks, talents, monster affixes, named monsters) iterate const file lists with `ResourceLoader.exists()`. Hit by this four times before getting it right; do not regress.

## What we defer

Patterns we may adopt later. Listed so we don't forget — not in place now to avoid premature abstraction.

- **Component pattern.** Partially adopted — `PlayerCombat` extracts damage resolution and cooldown tracking from `PrototypePlayer`. Further extraction (separate `HealthComponent`, `HitboxComponent`) when 3+ entity types share the same logic.
- **Event bus / autoload signal hub.** Adopt when cross-system events become common.
- **Standalone scene per entity type.** Adopt when entities need to spawn at runtime or appear in multiple scenes.
- **Stricter GDScript warnings** (treat-warnings-as-errors). Adopt once the codebase stabilizes past prototype churn.

## Inspirations

The reference set the project actually pulls from.

**Diablo 2.** The foundational reference for genre, feel, and structure. Deliberate weighted combat, loot-driven progression, distinct monster families with shared visual language per zone, skill synergies creating hidden multipliers, environmental storytelling over cutscenes.

**Project Diablo 2 (PD2).** Demonstrated how much further the D2 design space could go. Build diversity per class (expanded runewords + skill changes revealed how many viable builds were latent in the original system); oskills and off-class abilities on items that create cross-class fantasy and build desire. *When a single item drop can make you want to reroll a character, the loot system is working correctly.*

**Vampire Survivors.** The end-game enemy density target. The feeling of being overwhelmed by sheer numbers, and the satisfaction of a build that handles it. The scale — not the auto-fire mechanic — is the reference.

**WoW: Legion.** Specifically for the class unlock system. Artifact weapon quests were memorable because they were tailored to the class fantasy — the quest felt like the class choosing you, not a menu option.

For tonal and visual influences (Neuromancer, The Thing, Videodrome, Return of the Living Dead, Flash Gordon), see [`world.md`](world.md).
