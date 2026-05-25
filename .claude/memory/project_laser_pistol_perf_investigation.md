---
name: project_laser_pistol_perf_investigation
description: Resolved-to-hypothesis (2026-05-25) — phys spikes are per-shot node-spawn cost in the laser pistol fire path (~6 nodes + 3 tweens + materials per shot, ~10-20ms in the physics frame). Not corpses, not active enemies. Fix candidates: pool decals/meshes, defer VFX spawn out of physics frame, or simplify visual.
metadata:
  type: project
---

User reports lag tied to laser pistol firing. Three CSV runs traced
the cost to **per-shot node-spawn overhead inside the physics frame**.
Earlier hypotheses about corpses and enemy count were ruled out by the
expanded perf logger.

**Final diagnosis from CSV evidence:**

1. **NOT corpses** — `corpses` column added in 479779d; max 5 during
   spikes, avg 1.5. Corpses are negligible.
2. **NOT enemies** — 24 phys spikes recorded with
   `enemies_active=0 AND corpses=0 AND projectiles=0`, avg 60ms phys.
   Nothing else in the physics simulation when the spike fires.
3. **NOT existing decals** — periodic samples with 280-420 decals
   showed phys 3.7-7.2ms (normal). The cost is in the SPAWN, not the
   ongoing presence.
4. **NOT all weapons equally** — melee_2h fires showed phys 10-42ms,
   ranged_1h (laser) first fire after switch was 3.94ms, second fire
   spiked to 65.19ms. Clear per-shot transient cost specific to
   ranged hitscan visuals.

**Root cause: per-shot VFX spawn inside the physics frame.**

`PlayerCombat._resolve_hitscan` awaits a physics frame for `intersect_ray`,
then synchronously spawns the entire fire VFX stack while still inside
that physics frame. Per shot:

- `spawn_muzzle_flash` — 1 OmniLight3D (pooled) + 1 tween
- `spawn_beam` — 1 Node3D + 2 MeshInstance3D + 2 OmniLight3D (pooled)
  + 1 tween
- `spawn_wall_projectile_impact` (if no enemy hit) — 1 Decal + 2 tweens
- `spawn_impact_burst` (if enemy hit) — 1 MeshInstance3D + 1 OmniLight3D
  (pooled) + 1 GPUParticles3D + new ParticleProcessMaterial + new Curve
  + new CurveTexture + new SphereMesh + 2 new StandardMaterial3D + 1 tween

Per shot: 6-10 node allocations + 3-4 tween allocations + 3-5 material/
resource allocations. Each `add_child` is ~0.5-1ms (init + _ready +
signal connections + group/tree bookkeeping). Total per shot: 10-20ms,
all attributed to phys_ms because it ran inside the awaited physics
frame.

**Fix candidates (none shipped yet — paused for user direction):**

A. **Defer VFX spawn out of the physics frame** (lowest visual risk).
   The hitscan needs the physics frame for intersect_ray; the VFX
   doesn't. Call `_spawn_hitscan_visuals.call_deferred(...)` after the
   raycast resolves. Spawn cost shifts to idle frame; phys_ms drops
   to just the raycast cost (~0.2ms).

B. **Pool the Decal nodes** for wall impacts (same pattern as the
   OmniLight3D pool already in `_acquire_light` / `_release_light`).
   Caps allocation churn even if spawn stays in physics frame.

C. **Simplify the visual** — drop the mid-beam light, drop the wall
   decal entirely on misses (or use a tiny brief flash instead), pool
   the impact_burst's resources. The most code-change but cheapest
   per-shot.

D. **All three** for the largest cumulative win.

**User explicitly OK with rebuilding the visual for performance**, with
the constraint that it should look similar. Option A preserves the
visual exactly. Option C trades visual fidelity for the biggest win.

Related: [[project_perf_logger]], [[project_vfx_warmup]],
[[project_enemy_physics_pause]]
