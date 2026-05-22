---
name: Ground effects (blood as the first instance)
description: Environmental floor types (blood today; oil/frozen/fire planned) gate player movement via Area3D enter/exit + Traction-mitigated slip/slow/stumble. Foundation for Divinity-style combat layers and consumption skills.
type: project
---

Blood pools are the first concrete instance of a planned Divinity 2-style
ground-effect system: walking through one is a gameplay event, not just
a visual.

**Effects on the player (blood, current values):**
- `BLOOD_SLOW_FACTOR = 0.85` — mild −15% move speed, scales to 1.0 at
  `Traction.TIER_SLOW`.
- `BLOOD_FRICTION_FACTOR = 0.55` — decel step multiplier when releasing
  wish_dir (accel step is unaffected — feels like "wet boots can't
  grab when stopping" not "starting from rest is sluggish"). Restored
  to 1.0 at `Traction.TIER_SLIP`.
- `BLOOD_SLIP_CHANCE = 0.12` — on entry, roll a stumble (full input
  lockout for `BLOOD_STUMBLE_DURATION = 0.3 s`). Suppressed entirely
  at `Traction.TIER_SLIP`.

**Architecture (mirrors the existing oil/water `slow_pool` pattern):**
- Each pool decal carries a child `Area3D` named `SlipZone` with a
  `CylinderShape3D` whose radius is tweened in lockstep with the
  visual pool growth (so the player only slips inside the visible
  footprint, not the eventual target diameter).
- `body_entered` / `body_exited` call `player.enter_blood_pool()` /
  `exit_blood_pool()` — counted (not bool) for overlapping pools.
- `PrototypePlayer._blood_pool_factor()` and `_blood_friction_factor()`
  compose multiplicatively with the existing speed-factor chain.
- HUD: `_add_blood_pool_debuff_entry()` shows a red "B" with a
  Traction-aware tooltip mirroring the existing "Slowed" entry.

**Generic-API entry points (planned skill surface):**
- `PrototypeAttackIndicator.get_blood_pools_near(world_pos, radius)`
  → `Array[Decal]`. Filters by priority FLOOR + recorded `_blood_area`
  ≥ 0.6 m² so mist drops and wall splats are excluded — callers get
  only storytelling-grade pools.
- `PrototypeAttackIndicator.consume_blood_pool(pool)` — frees the
  SlipZone first so any standing player gets clean `body_exited`,
  then routes through `_fade_and_free`.

**Player-only by design.** Enemies don't have a Traction stat to
mediate against, same as the existing slow_pool system. Layer mask
is Player-only. Adding enemy slip later: add Enemy layer to
`_BLOOD_POOL_PLAYER_MASK`, give PrototypeEnemy an enter/exit pair,
and decide on the simpler enemy-side mitigation (probably a flat
factor on EnemyClass).

**Future ground types** (`frozen`, `oil`, `fire`, `electricity`):
- Frozen will reuse the slip-friction model with a MUCH lower
  `FRICTION_FACTOR` (~0.20 vs blood's 0.55). User explicitly called
  this out — frozen should feel significantly more punishing than
  blood underfoot.
- Each new type lands as parallel constants + parallel
  `get_X_pools_near()` until there are 3+, at which point the shared
  scan logic gets extracted to a `GroundEffects` autoload with a
  type registry.
- A planned **Enculted "Blood Ritual"** consumes pools for skill
  effect (the consume API exists for this). A planned **Forged**
  skill consumes oil pools for healing — same pattern.

**MP note:** blood pools are client-local (each peer has its own
ring buffer based on locally-witnessed kills). Slip effects therefore
fire on whichever pools the local client can see. Aligns with how
the existing slow_pool puddles work (procgen deterministic, but the
Area3D is local to each client's tree).
