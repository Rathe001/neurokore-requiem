---
name: blood-decal-ring
description: DEPRECATED 2026-06-03. The decal-ring buffer system was deleted in Phase 2a of the audit (commit cleanup). Floor / wall / objects / characters / footprints all use LiquidLayer-stamps or per-instance decal lifecycles now. Kept only as historical record.
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**Deprecated 2026-06-03.** The global blood-decal ring (`_blood_decal_ring`,
`_track_blood_decal`, `BLOOD_DECAL_MAX`, priority tiers, all related state)
was deleted as part of audit Phase 2a. ~790 lines removed from
`prototype_attack_indicator.gd`.

Current state:
- **Floor pools, per-hit droplets** — rasterized into LiquidLayer
  (see [[liquid-layer-architecture]]).
- **Wall splatter + drips** — WallLiquidLayer.
- **Footprints** — LiquidLayer.stamp_oriented via spawn_fluid_footprint.
- **Character splats** — per-character meta-tracked list with own
  fade timer (`_blood_decals` meta + `CHARACTER_BLOOD_MAX_PER_CHAR`).
- **Object splats** — per-decal tween + `OBJECT_BLOOD_FADE_DURATION`,
  capped at `OBJECT_BLOOD_MAX_PER_KILL = 4` receivers per kill.

Nothing left that needs a global FIFO ring. Each remaining surface
type has its own lifecycle.

If you need to reconstruct the historical decision rationale (why
priority-3-tier eviction, why walls outrank floors, why small-first
eviction), pull the original from
`git log -p --follow .claude/memory/project_blood_decal_ring.md`
or the commit that deleted `_track_blood_decal`.
