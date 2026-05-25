---
name: project_laser_pistol_perf_investigation
description: In-progress diagnosis (paused 2026-05-25) — phys spikes correlate 100% with ranged_1h equipped, but enemies/projectiles/casings aren't the cost. Working hypothesis is rigid-body corpses; next CSV will have a corpses column to confirm.
metadata:
  type: project
---

User reported lag specifically tied to laser pistol firing. The
[[project_perf_logger]] CSV proved the correlation but not the cause.
This memory captures where the investigation left off so we can resume
without re-deriving the data.

**Established facts from the CSV (2605 rows, fresh launch):**
- 147 / 147 phys spikes had `weapon_id = ranged_1h` (perfect correlation)
- 82 / 147 had `firing = 1` during the spike; 65 had `firing = 0` but
  ranged_1h still equipped (residual cost outlives the trigger pull)
- Worst spike 244ms phys with `enemies_active=6, projectiles=2,
  casings=0`. 6 enemies × 0.5ms = 3ms expected, so enemies aren't the
  source.
- Spikes happen even at `enemies=196, enemies_active=0, projectiles=0,
  casings=0`. Whatever costs phys isn't anything the existing columns
  count.
- Sustained ~60-180ms phys across many seconds — accumulating cost,
  not transient.

**Ruled out:**
- The laser fire path itself: `spawn_muzzle_flash` (OmniLight + tween),
  `spawn_beam` (2 meshes + 2 OmniLights + tween), `spawn_wall_projectile_impact`
  (Decal). All render-side, no physics objects.
- Shell casings (`ranged_1h` is NOT in `_EJECT_VARIANTS`, so casings=0).
- Wall decals (cap 80, but Decal nodes have no physics).
- Projectiles (laser is hitscan, count stays at 0 or 1-2 from enemy fire).
- Skeletal ragdolls from THIS weapon: laser pistol has
  `crit_chance_range = (0.0, 0.0)` and isn't an explosion weapon, so
  `_last_hit_was_crit` and `_last_hit_was_explosion` both stay false →
  the death path takes the cheap death-anim branch, NOT the
  XBotRagdoll PhysicalBone3D branch.

**Working hypothesis: rigid-body corpse accumulation.**
Three death paths in `prototype_enemy.gd`:
1. `XBotRagdoll` (PhysicalBone3D) — gated by crit/explosion + RagdollQueue
2. Death anim path — no rigid body, plays Mixamo clip then sinks
3. Legacy `_spawn_ragdoll_corpse` — `PrototypeRagdollCorpse` RigidBody3D
   with `continuous_cd=true` and `LAYER_CORPSE` in its own collision_mask
   (corpse-corpse collision). LIFETIME=20s.

If somehow path 3 (or path 1 via dismember/explosion fallback) is firing
for some kills, rapid laser pistol clearing of a room could pile up
15-30 rigid corpses, and Jolt's broad-phase with CCD enabled would
plausibly produce the observed 100-200ms phys.

**Next step (paused for user break, 2026-05-25):**
Latest commit `479779d` added a `corpses` column to the perf logger
(count of `&"ragdoll_corpses"` group). On the next session resumption:
1. Have user generate a fresh CSV with laser pistol combat
2. Check whether `corpses` climbs into double-digits during phys spikes
3. If yes — the obvious fixes are: drop `LAYER_CORPSE` from corpse
   collision_mask (kill corpse-corpse collision), disable
   `continuous_cd`, lower LIFETIME from 20s to ~10s, or cap concurrent
   corpses with FIFO eviction
4. If no — keep digging; possibly look at `XBotRagdoll` PhysicalBone3D
   count via a tree walk, or other physics-side accumulators

User explicitly OK with rebuilding the laser pistol visual effect for
performance IF the visual is the cause. Current analysis says it
probably isn't — corpses (or some other accumulator) more likely.

Related: [[project_ragdoll_queue]], [[project_xbot_ragdoll]],
[[project_perf_logger]], [[project_enemy_physics_pause]]
