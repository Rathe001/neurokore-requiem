---
name: project_gi_quality_setting
description: SDFGI is off by default; DisplayConfig.gi_quality (OFF/LOW/HIGH) drives runtime apply via DisplayState._apply_gi_preset, shown as "Global Illumination" in Display settings
metadata:
  type: project
---

SDFGI was responsible for a ~50-second "FPS bad at level start" stall:
procgen rebakes 4 cascades from scratch every level load, costing ~6-8ms
per frame during convergence (perf log 2026-05-24 showed steady 22-27ms
proc until t≈64, then permanent drop to 18ms when the final cascade
settled). Cyberpunk identity rides on emissive + bloom, not soft GI
bounce, so the visual hit of disabling is small.

Architecture (3 layers):

1. `DisplayConfig.gi_quality: GiQuality` (enum OFF/LOW/HIGH, default OFF).
2. `DisplayState._apply_gi_preset(env)` translates enum → SDFGI knob
   values. Tuning recipe lives here — update LOW/HIGH numerics in one
   place and every WorldEnvironment in the project picks them up on the
   next `apply()`.
3. `DisplayState._on_node_added` re-applies on every WorldEnvironment
   that enters the tree, so level loads / scene transitions don't
   reintroduce the old high-cost SDFGI even if the .tscn baked it in.

Presets:

| Preset | sdfgi_enabled | cells | cascades | occlusion | bounces | Cost      |
|--------|---------------|-------|----------|-----------|---------|-----------|
| OFF    | false         | -     | -        | -         | -       | 0         |
| LOW    | true          | 0.35  | 2        | false     | 1       | ~3ms/frame, ~10s converge |
| HIGH   | true          | 0.15  | 4        | true      | 2       | ~6-8ms/frame, ~50s converge (pre-v0.3 default) |

`level_shell.tscn` keeps the SDFGI knob lines in place (with
`sdfgi_enabled = false`) so the editor preview matches the default
shipping config. The runtime apply overrides them anyway — they're a
fallback / editor-preview value, not authoritative.

Related: [[project_perf_logger_feedback]], [[project_enemy_anim_pause]]
— the steady idle proc was a stack of three causes (logger feedback,
enemy anims on hidden bodies, SDFGI cascade convergence); SDFGI was the
last and biggest piece for procgen levels.
