---
name: blood-migration-status
description: "Snapshot of the floor → LiquidLayer migration as of 2026-06-01. Tracks what's shipped, what's still on the old Decal system, and the next concrete step (walls)."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

## Where we are (2026-06-01)

The legacy per-decal floor-pool system has been replaced with
[[project_liquid_layer]] for floor pools + per-hit droplets. ~280
lines of legacy code deleted in commit `197fb06`. **Verify state
against `git log --oneline` before assuming this is current.**

## Shipped (on LiquidLayer)

- **Floor pools** — `PrototypeAttackIndicator.spawn_blood_decal` now
  routes to `_stamp_to_liquid_layer`. Mist drops get 0.10-0.22m
  radius, kill-scene central pools get 0.55m. Corpse settle pools
  call `layer.stamp()` directly with 0.9m radius from
  `PrototypeEnemy._spawn_settle_pool`.
- **Per-hit droplets** — `PrototypeEnemy._stamp_hit_droplets()`,
  called from `take_damage` right after `spawn_blood_burst`. 6 base
  drops, +3 crit, +4 melee_1h. 8-22cm radius squared-rolled (most
  small specks + occasional big drips), scattered 0.6-2.0m out in a
  forward-biased cone.
- **Slip-zone Area3D** — standalone group `&"blood_slip_zone"`,
  spawned once per corpse settle pool. Not per droplet (would be
  too many overlapping areas). `is_in_blood(world_pos)` scans the
  group for footstep system polling.

## Update 2026-06-03

- **Footprints migrated** — `spawn_fluid_footprint` now stamps into
  the per-fluid LiquidLayer via new `stamp_oriented` method. WHITE
  silhouette texture; color from layer shader; back-compat shim on
  `spawn_blood_footprint` so callers (Footsteps.gd) didn't change.
  Hit a hidden lifecycle bug with `process_frame.connect` cleanup —
  see [[liquid-layer-stamp-lifecycle]] before adding any new
  `stamp_*` variants.
- **Slippery / Poor Traction debuff window tied to the visual trail.**
  `_active_ground_surfaces` checks `bloody_steps_remaining` meta
  alongside `_blood_pool_count`, so the debuff persists as long as
  prints are visibly being tracked. Same pattern for future fluids.

## Still on the old Decal system (pending tasks)

- **#110 Walls — DONE.** `spawn_blood_wall_splatter` routes through
  `WallLiquidLayer.stamp()` with overlay quads + dual SubViewport
  masks (one per ±X / ±Z axis). Shader handles wall sampling +
  lighting; stamps persist in CLEAR_MODE_NEVER. Full polish session
  (Phase 6 + 7 commits, mid-late May) iterated color, drip streaks,
  thickness gradient, aging. This bullet predated the migration
  landing.
- **#111 Objects + characters — still pending.**
  `spawn_blood_on_character` (line 1399) for per-character splats
  and `_spawn_object_blood_decal` (line 1644) for props /
  interactables / pillars. Both still create Decal3D nodes directly.
  Different pipelines from floor/wall (per-instance Decal, not a
  shared SubViewport mask) so the migration shape is its own work.
  See [[project_object_blood_pipeline]] for the receiver opt-in +
  side-decal mechanism that survives migration.
- **#112 Fluid type generalization (in-progress 2026-06-03)** —
  Floor LiquidLayer naming + lookup unified. `fluid_id` now matches
  `blood_type` directly (`&"human"`, not `&"blood_human"`); a single
  `LiquidLayer.find_for(tree, fluid_id)` static helper routes every
  spawn call site. Silent fallbacks replaced with one-time
  push_warning calls so missing layers surface in dev.
  Still pending: instancing additional LiquidLayer scenes for
  non-human fluids (cyborg / machine / oil / water — needs different
  color uniforms per instance); wall LiquidLayer multi-fluid support
  (currently a singleton — would need per-axis masks per fluid).

## Approach hint for walls (task #110)

Walls are vertical surfaces, so the SubViewport-mask + top-down
projector approach LiquidLayer uses for floors doesn't transfer
directly. Two reasonable directions:

1. **Per-wall LiquidLayer** — Each wall mesh gets its own
   SubViewport mask + shader pass. Means walking past a freshly
   painted wall reveals it has its own coverage texture. Heavy on
   memory (one 1024² target per wall is ~4MB), might need lower
   resolution. Cleanest architecturally — same shader, same stamp
   API, different orientation.
2. **One world-space cube/tri-planar mask** — A single 3D texture
   or three orthogonal SubViewport masks (one per axis) sampled
   tri-planar from the wall shader. Lighter memory, harder to
   author the stamp space mapping.

Recommend option 1 if memory cost stays under ~80MB (20 walls per
room × 4MB ≈ tight but doable on 8GB target spec). Option 2 if not.

## Gotchas already burned

- **`is_in_blood` had a duplicate after the refactor.** The OLD one
  scanned `_blood_decal_ring` for floor decals (which no longer
  exist there); the NEW one scans the slip-zone group. Deleted the
  old, kept the new. Commit `70d0940`.
- **`_blood_decal_ring` still exists** — used by walls, footprints,
  character splats, receivers (everything still on the old system).
  Don't delete the ring infrastructure until those migrations land.
- **`get_blood_pools_near` / `consume_blood_pool` were deleted.** No
  callers existed (Enculted Blood Ritual not implemented yet). When
  that skill lands, re-add by either reading the LiquidLayer mask
  texture or querying the slip-zone group.
- **Color tone is sensitive.** The user iterated through "too
  bright", "too dark", "looks like raw tissue", "looks like
  flower petals" feedback. Current sweet spot is in
  [[project_liquid_layer]] — don't drift far from those values
  without testing in both lit and shadowed rooms.

## Files touched in this migration

- `game/scripts/systems/liquid_layer.gd` (new)
- `game/scenes/world/liquid_layer.tscn` (new)
- `game/shaders/liquid_surface.gdshader` (new)
- `game/scenes/world/level_shell.tscn` (added BloodLayer instance)
- `game/scripts/prototype/prototype_attack_indicator.gd` (gutted
  legacy pool path, added `_stamp_to_liquid_layer` +
  `spawn_blood_slip_zone` + new `is_in_blood`)
- `game/scripts/prototype/prototype_enemy.gd` (settle pool +
  per-hit droplet stamps + slip-zone spawn)
- `game/scripts/prototype/prototype_player.gd` (one comment update
  for the new slip-zone name)
