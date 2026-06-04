---
name: enemy-los-search-and-formation
description: "Two AI follow-ups landed 2026-06-04 in prototype_enemy._chase_tick: ranged-LoS sidestep so cover doesn't freeze ranged enemies, and angular ring-formation bias so melee enemies spread around the player instead of bunching."
type: project
---

Two complementary additions to `prototype_enemy._chase_tick`:

## Ranged: LoS-search sidestep (was: stand still forever)

Hold band used to be unconditional: in kite distance → set velocity to zero. If the player ducked behind cover, the enemy held the spot and never re-acquired a firing angle.

Now the hold-band branch splits on `has_los`:
- **LoS clear** → stand still (the cast path above fires when cooldown allows). Resets `_los_search_stuck_timer`.
- **LoS broken** → sidestep perpendicular to `to_target` at `CHASE_SPEED * 0.5`, facing the target via `_face_override`. Direction (`_los_search_dir`) is seeded per-enemy via instance_id parity so a cluster behind cover spreads both ways. If horizontal velocity stays below `_WALL_STUCK_VEL_SQ` for `_LOS_SEARCH_FLIP_TIMEOUT` (0.6s), flip direction — we hit a wall on this side, try the other.

Vars/constants live next to `_wall_stuck_*` near the bottom of the file. Reset alongside `_wall_stuck_timer` whenever state leaves CHASING.

## Melee: ring formation (was: instance_id parity strafe)

Old strafe block: between swings, if not crowded (1.6m radius local check), strafe `±perp` based on `instance_id & 1`. Pure parity. Result with 4 melee converging: everyone arrived from the same arc the chase came from and stayed there.

New block does a SINGLE spatial query around the **target** (not self) at `_FORMATION_QUERY_RADIUS = 4m`. The returned ally list serves both:
1. **Crowded check** — distance-squared filter inside the loop replaces the old self-centered query.
2. **Formation check** — compute each ally's angular position around the target (`atan2(rel.x, rel.z)`), find the one with the smallest `wrapf(delta, -PI, PI)` from mine, strafe AWAY from them.

Sign convention (verified by hand trace, top-down view):
- `perp = UP × to_target_norm` resolves to "CW around target" (in the sense that moving along +perp decreases the enemy's `atan2(rel.x, rel.z)` angle).
- Nearest ally at `delta > 0` (higher angle than me, CCW of me) → strafe +perp (CW, away from them).
- Nearest ally at `delta < 0` (CW of me) → strafe -perp.
- No ally returned → fall back to instance_id parity so isolated pairs don't both choose the same side.

## Why this is one memory, not two

Both touch the same chase-tick branches and share the same overall pattern: spatial query → angular reasoning → perpendicular strafe with `_face_override` to keep the weapon on target. The ranged variant runs in the kite band, the melee variant in the attack band. If a future change touches one, the other is almost certainly the same shape.

## MP safety

`_chase_tick` runs only on the host (enemy AI is host-authoritative). Strafe velocity flows through the existing position-sync replication. Clients never run this code path. No new RPCs.

## Files

- `game/scripts/prototype/prototype_enemy.gd` — both edits in `_chase_tick` (~line 2167 ranged, ~line 2186 melee) + new constants/vars at the bottom (`_LOS_SEARCH_FLIP_TIMEOUT`, `_los_search_dir`, `_los_search_stuck_timer`, `_FORMATION_QUERY_RADIUS`)

Related: [[enemy-facing-slew]] (the slew that makes the new sidestep read smooth), [[enemy-face-override]] (lets sidestep face target while moving perpendicular).
