---
name: Blood palette + fluid-type system
description: Per-enemy blood color via PrototypeAttackIndicator.BLOOD_PALETTES + @export var blood_type on PrototypeEnemy; adding a new fluid is a single palette entry
type: project
---

Blood / fluid color is a per-enemy property, threaded through every
spawn function (burst, splatter, kill scene, wall splat, pool, footprint
trail). Architecture lives in `prototype_attack_indicator.gd`:

- `BLOOD_PALETTES: Dictionary` (StringName → Color) — single source of
  truth. Current entries: `&"human"` (dark red), `&"cyborg"` (cyan-
  blue), `&"machine"` (black oil).
- `blood_color_for(blood_type)` — lookup helper, falls back to human.
- All `spawn_blood_*` functions take a final `blood_type: StringName`
  param with default `BLOOD_TYPE_HUMAN`.
- Texture caches are now `Dictionary` keyed by `blood_type` (splatter,
  pool, bootprint-right, bootprint-left) — one texture per (kind ×
  fluid type) regardless of horde size.

`PrototypeEnemy.blood_type` is an `@export var` (default `&"human"`)
threaded through every blood spawn call in `_die`, hit blood burst,
`_try_spawn_wall_blood`, and `_tick_bleed_out`. Future Cyborg and
Machine archetypes set their own blood_type either via the .tscn or
via `EnemyClass` (not yet wired — would mean adding `blood_type` to
`EnemyClass.gd` and applying it in `PrototypeEnemy._init_enemy`).

**Why:** User flagged future Cyborg (fluorescent blue) and Machine
(black oil) fluids during the bootprint refactor — wanted the system
"expandable" so adding new types doesn't require touching every spawn
callsite later.

**How to apply:** When adding a new fluid (e.g. acid for plant
monsters), add the entry to `BLOOD_PALETTES`, set the enemy's
`blood_type` to that key, done. If a fluid needs different surface
properties (e.g. acid should be brighter / emissive), extend the ORM
texture to be per-type too — currently `_get_blood_orm_texture()` is
shared across all fluids.

Footprint trails currently default to `&"human"` regardless of which
puddle the player walked through — `Footsteps._handle_bloody_footstep`
doesn't track which fluid type was underfoot. When that matters,
extend `PrototypeAttackIndicator.is_in_blood(pos)` to return the
fluid type (or null) instead of bool, and thread it to
`spawn_blood_footprint`.
