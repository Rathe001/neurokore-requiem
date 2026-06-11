---
name: project_laser_pistol_perf_investigation
description: RESOLVED 2026-06-10 (d0a92e4) — the per-shot freeze was StandardMaterial3D.duplicate() per shot forcing a ~25ms render-thread sync (x2 per shot). NOT the physics-frame placement, NOT GPU resource allocs. Golden rule - never create/duplicate Material RIDs in a per-shot path.
metadata:
  type: project
---

User-reported per-shot freeze on laser pistol fire. Took THREE
instrumentation rounds to land; the journey matters:

1. CSV (2026-05-25) blamed "VFX node spawn inside the awaited physics
   frame" (phys_ms 10-65 spikes). Deferring the VFX to an idle frame
   (82c37ce) moved the cost wholesale into Proc — the ATTRIBUTION was
   right but the mechanism wasn't.
2. Caching every per-shot GPU resource (meshes, CurveTextures,
   ParticleProcessMaterials) was correct hygiene but didn't dent the
   50ms either.
3. Per-segment usec timers (rounds 2+3) isolated it: 'setup' = 25ms in
   BOTH spawn_energy_pulse and spawn_beam, all node/light/tween work
   0.1ms. The only heavy setup op: **StandardMaterial3D.duplicate()**.

**ROOT CAUSE: creating a material RID mid-frame forces a sync with the
render thread's in-flight work (~one frame ≈ 25ms at 55fps).** It
re-arms between calls when node-adds queue new render work, so pulse +
beam each paid it once → ~50ms per shot. Same stall class regardless
of GPU (reproduced on an RTX 4070).

**FIX (d0a92e4):** pulse / beam / impact-flash use SHARED per-color
template materials (never duplicated) and fade via
**GeometryInstance3D.transparency** — a per-instance render property
that touches no material objects. Lights tween light_energy (also
per-instance-safe).

**Golden rules for ANY per-shot/per-hit/per-tick path:**
- Never `Material.new()` or `material.duplicate()` — share templates
  keyed by color/variant; fade via instance `transparency`.
- Never allocate Mesh / CurveTexture / ParticleProcessMaterial — cache
  singletons or per-color bundles (also fixed in blood burst, impact
  sparks, energy pulse, beam meshes).
- Never key caches by continuously-varying floats (beam length bug).
- Keep VFX spawn out of awaited physics frames (deferral pattern in
  _spawn_hitscan_vfx_deferred via process_frame one-shot).
- The [hitscan-vfx] >5ms print in player_combat.gd is a permanent
  tripwire — if it ever prints again, a regression reintroduced one
  of the above.
