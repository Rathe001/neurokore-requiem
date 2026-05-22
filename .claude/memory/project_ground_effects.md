---
name: Ground effects (blood as the first instance)
description: Environmental floor types as a Divinity-style combat layer. Blood + procgen water/oil puddles ship today; oil/acid/ice/fire planned. Per-surface mitigation curve via Traction autoload.
type: project
---

Blood pools and the procgen oil/water puddles are the first two
concrete ground effects under the new per-surface model. Future
types (oil, acid, ice, fire, electricity) follow the same pattern:
one Area3D + enter/exit pair per overlap event, the rest is profile
data.

**How a ground type composes:**
- A profile entry in `Traction.GROUND_EFFECT_PROFILES` keyed by
  surface_id (e.g. &"blood"). Stores half_mit_k (the surface's
  resistance against traction) plus T0 base values for slow,
  friction, slip chance, stumble duration, and a display name.
- An Area3D under the visual (decal, mesh, particle origin) with a
  cylinder shape mask that fires `enter_<surface>_pool` /
  `exit_<surface>_pool` on the player.
- A counted state + factor methods on PrototypePlayer that call
  through to the per-surface Traction API (`slow_factor_for_surface`,
  `friction_factor_for_surface`, `stumble_chance_for_surface`).
- An HUD debuff entry built via the shared
  `_add_ground_debuff_entry(stat_id, surface_id, glyph, color, title)`
  helper — passes the surface_id and the tooltip auto-formats from
  the profile.

**Blood pool specifics:**
- Area3D ("SlipZone") child of each pool Decal. Cylinder radius
  tweens in lockstep with the visual pool size so the player only
  slips inside the actually-visible footprint.
- T0 values (mitigated by traction k=5 — entry-level):
  −15% move, 0.55 decel friction, 12% stumble chance, 0.3 s stumble.
- Generic skill-facing query API:
  - `PrototypeAttackIndicator.get_blood_pools_near(pos, radius)` →
    Array[Decal]. Filtered by priority FLOOR + recorded area
    ≥ 0.6 m² so mist drops and wall splats are excluded.
  - `PrototypeAttackIndicator.consume_blood_pool(pool)` — frees the
    SlipZone first (clean body_exited for any standing player),
    then routes through `_fade_and_free`.
  - Future Enculted "Blood Ritual" calls these. Forged "consume
    oil for HP" gets a parallel `get_oil_pools_near` /
    `consume_oil_pool` pair when oil ground type lands.

**Water puddle migration:** procgen oil/water puddles
(`DecalBuilder`) keep their existing enter_slow_pool /
exit_slow_pool API on the player; the only change is that
`_slow_pool_factor()` now reads through
`Traction.slow_factor_for_surface(&"water")` instead of the old
universal `slow_factor_for(traction)`. Profile k=8 preserves the
"easy to mitigate" feel at slightly tougher than blood.

**Override flags for "always negate":** Per-surface negation lives
on boots as a `negates_<surface>` modifier (any non-zero value).
Future "Ice Walker" perk: boot rolls `negates_ice = 1` and the
player flat-ignores ice regardless of traction. Asymptotic curve
covers the gradient; override handles the binary case.

**Player-only by design.** Enemies have no Traction stat so they
don't slip. Area3D mask is Layer 3 (Player) only. If we ever want
slipping enemies: add the Enemy layer to `_BLOOD_POOL_PLAYER_MASK`,
give PrototypeEnemy enter/exit pairs, and decide on enemy-side
mitigation (probably a flat EnemyClass field, not a stat curve).

**MP note:** Pool decals + Area3Ds are client-local (each peer has
its own blood ring buffer driven by locally-witnessed kills). Slip
effects fire on whichever pools the local client can see. Procgen
puddles ARE deterministic across peers but the Area3D still lives
in each client's local tree. Aligns with the rest of the
client-local VFX architecture.

**Future ground types** (planned k values for design intent):
- water k=8 (shipped), blood k=5 (shipped)
- oil k=30 (mid-tier slip + slow)
- acid k=60 (DoT focus, modest slow)
- ice k=80 (heavy slip + slow, hardest mundane surface)
- fire k=70 (DoT focus, no slip)

When a third type lands, extract the shared scan logic into a
`GroundEffects` autoload with a type-registered API. Until then,
parallel `get_X_pools_near` / `consume_X_pool` methods on
PrototypeAttackIndicator read cleaner than a polymorphic registry.
