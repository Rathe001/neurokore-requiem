---
name: project_levelup_higher_lvl_spike
description: "Level-ups at higher levels (5, 6) still cost ~100ms proc despite VfxWarmup; Lvl 2 was fine"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

VfxWarmup pre-compiles the StandardMaterial3D variant the level-up
ring uses, and that fixed the Lvl 2 spike (perf log: 16ms proc at
t=96.93). But Lvl 5 (t=410.69) and Lvl 6 (t=461.86) both cost ~104ms
proc.

The shader is warm, so the cost is something else along the
`leveled_up` signal path. Suspects:

- **UI re-layout** — talent points granted, the talent / mission HUD
  re-paints
- **VFX scaling with level** — bigger ring, more particles, more
  emission lights at higher levels?
- **Per-level audio variants** — first-play of a Lvl 5/6-only stinger

Easy to investigate: add `print(Time.get_ticks_msec())` around each
listener of `PlayerState.leveled_up` and identify which one is heavy
at higher levels.

Related: [[project_vfx_warmup]] — current warmup scope.
