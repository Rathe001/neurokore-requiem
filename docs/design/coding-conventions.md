# Coding Conventions

Engineering conventions for the Godot codebase under `game/`. Intentionally short — for anything not covered here, follow the [official GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).

---

## Naming

| What | Convention | Example |
|---|---|---|
| Variables and functions | `snake_case` | `current_health`, `take_damage()` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_HEALTH`, `AOE_ATTACK_RANGE` |
| Classes (via `class_name`) | `PascalCase` | `class_name Player` |
| Private members | `_leading_underscore` | `_attack_cd`, `_die()` |
| Files (scenes and scripts) | `snake_case` | `world.tscn`, `enemy.gd` |
| Node names in scenes | `PascalCase` | `Player`, `CollisionShape2D` |
| Group names | `lowercase plural` | `"enemies"`, `"projectiles"` |

---

## Type Hints

Always use them.

- Variables: `var x: int = 5` or `var x := 5` (inferred)
- Function parameters and return: `func damage(amount: int) -> void:`
- `@export`: `@export var max_health: int = 100`

---

## Annotations

- **`class_name Foo`** at the top of a script makes the type usable as an annotation across the codebase. Add it to any script that other scripts will reference by type.
- **`@export`** exposes a variable in the editor's Inspector. Use it for any value that should be tunable per-instance without editing code (per-enemy stats, per-spawner counts).
- **`@onready var ref := $ChildName`** for child-node references — defers the lookup until the node is in the tree.

---

## Magic Numbers

Numeric tuning values (speeds, damages, cooldowns, ranges) belong in named `const`s at the top of the script. If the value should be tunable per-instance, use `@export var` instead.

---

## Member Order in a Script

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

---

## Built-in Constants

Prefer `Vector2.ZERO`, `Color.WHITE`, `Color.TRANSPARENT` over numeric literals where a named constant exists.

---

## StringName Literals

Use `&"action_name"` (StringName literal) rather than `"action_name"` for input-action names and group names. Same behavior, signals intent, fractionally faster (no allocation).

---

## Loose Coupling via Groups

Use Godot's group system (`add_to_group(&"enemies")`, `get_tree().get_nodes_in_group(&"enemies")`) instead of direct references when an entity needs to find others by category. This avoids needing to wire scene trees together explicitly and scales naturally as content grows.

---

## Scene Files (.tscn)

- One scene per file.
- Edit scenes in the Godot editor when possible. Hand-editing `.tscn` text is fine for small structural changes but the editor handles UIDs, sub-resources, and references more reliably.
- Each reusable entity (player, enemy type, projectile) should eventually live in its own scene file so it can be instanced. The current world scene has enemies inline as a prototype shortcut — extract to standalone scenes when we have more than one enemy type or need to spawn at runtime.

---

## Infrastructure In Place

- **Spatial partitioning** — `SpatialGrid` autoload provides O(nearby) proximity queries for combat, pickups, and interactables. All entities register/unregister themselves; the grid updates positions each physics frame. Use `SpatialGrid.query_radius()`, `query_cone()`, or `query_nearest()` instead of `get_nodes_in_group()` for proximity-dependent logic.
- **Object pooling** — `EntityPool` autoload recycles `Node3D` instances. Use `EntityPool.acquire(scene)` / `EntityPool.release(node)` instead of `instantiate()` / `queue_free()` for frequently spawned entities (enemies, projectiles, pickups). Pooled entities must implement a `reset()` method to re-initialize state.

## What We Defer

These are reasonable patterns we may adopt later. Listed here so we don't forget — not in place now to avoid premature abstraction.

- **Component pattern** (separate `HealthComponent`, `HitboxComponent` nodes) — adopt when 3+ entity types share the same logic.
- **Event bus / autoload signal hub** — adopt when cross-system events become common.
- **Resource-based stats** (`.tres` files for entity / weapon / skill stats) — adopt when designer-tunable content grows beyond a handful of values.
- **Standalone scene per entity** — adopt when entities need to spawn at runtime or appear in multiple scenes.
- **Stricter GDScript warnings** (treat-warnings-as-errors) — adopt once the codebase stabilizes past prototype churn.
