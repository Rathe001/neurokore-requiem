---
name: project_laser_pistol_perf_investigation
description: RESOLVED 2026-06-10 (82c37ce) — per-shot hitch was VFX node+GPU-resource allocation inside the awaited physics frame. Fixed with deferred VFX spawn + caching every per-shot resource. Pattern notes for future VFX work.
metadata:
  type: project
---

User-reported per-shot freeze on laser pistol fire. CSV runs (2026-05-25)
traced it to **per-shot VFX spawn inside the awaited physics frame**
(10-65ms phys spikes; corpses/enemies/projectiles ruled out).

**FIX SHIPPED 2026-06-10, commit `82c37ce`:**

1. Both hitscan paths (`_resolve_hitscan` + `_resolve_hitscan_exact`)
   spawn the entire fire-VFX stack one idle frame later via
   `_spawn_hitscan_vfx_deferred` (process_frame one-shot connect, NOT
   call_deferred — see [[project_perf_session_2026_05_25]]: deferred
   calls from physics don't escape the tick). Damage stays sync.
2. Beam meshes: cache was keyed by RAW FLOAT length → every shot was a
   cache miss creating 2 CylinderMeshes retained forever (leak + GPU
   buffer churn). Now 2 shared unit meshes + per-instance scale.
3. Energy pulse / impact burst: all previously-fresh-per-shot resources
   (SphereMesh, StandardMaterial3D, ParticleProcessMaterial, Curve,
   CurveTexture) now cached — singletons or per-color templates,
   duplicated only when a tween mutates them.

**Patterns for any future per-shot/per-hit VFX:**
- Never allocate Mesh / CurveTexture / ParticleProcessMaterial in a
  fire path — each is a GPU upload. Cache singletons or per-color.
- Never key a cache by a continuously-varying float (beam length) —
  use shared unit geometry + instance scale.
- Spawn VFX nodes OUTSIDE the awaited physics frame.
- Muzzle/beam/impact color fallbacks must share ONE source:
  elemental tint if set, else `_color_for_host` (class color).
