---
name: project_perf_session_2026_05_25
description: Perf session findings on 2026-05-25 — script-side cost minus 7.55ms HUD, FluorescentFlicker throttled, dimmed lights culled. Avoid blanket visibility_range_end on enemy mesh subtrees (it regressed baseline 58→44fps).
metadata:
  type: project
---

A long perf session on 2026-05-25 covered baseline optimizations + the
laser pistol hitscan path. Final state: 60fps baseline, 60fps firing,
occasional transient spikes during room transitions / heavy combat.

**Key wins (all kept):**

- `0f78461` + `dd23fb2` — Enemy `_physics_process` pause when invisible
  AND state ∈ {IDLE, CHASING, RETURNING}. See
  [[project_enemy_physics_pause]].
- `9972366` — No-op guards in `_update_anim_player_active` /
  `_update_physics_process_active` so re-writing the same value doesn't
  churn Godot's SceneTree (eliminated ~65ms off LoS-reveal spike).
- `ab96d10` — Re-randomize `_idle_skip_counter` on every wake so
  batches revealed together don't phase-lock.
- `4fcaeb6` — Anim pause for visible+IDLE+far (>20m XZ). Saved ~7ms
  baseline at horde density.
- `73df01b` — Two changes: ProximityLighting toggles `light.visible`
  when energy < 0.01 (drops dimmed lights from renderer culling pass)
  AND FluorescentFlicker `_physics_process` throttled 60Hz → 15Hz with
  randomized per-instance phase.
- `e9eca15` — PrototypeHud cached find_children results + bumped
  refresh 10Hz → 2Hz. The biggest single-script-function saving:
  `PrototypeHud._process` from 7.55ms → 0.00ms (inclusive).
- `14e441c` + `49e09b4` — Defer hitscan VFX spawn out of physics frame
  via `tree.process_frame.connect(..., CONNECT_ONE_SHOT)`. Note:
  `call_deferred` from `_physics_process` DOESN'T actually defer past
  the physics tick — MessageQueue flushes immediately after, and
  `TIME_PHYSICS_PROCESS` includes that flush. `process_frame.connect`
  is the only way to definitively shift work to the next idle tick.
- `7c79939` — Strip hitscan VFX: dropped GPUParticles + 2nd beam mesh
  + 2nd light + extra tween properties. Per-shot cost ~10-15ms →
  ~2-3ms.
- `eb12e5c` (partial) — LoS culler `MAX_DIST_SQ` 40m → 30m and
  `STAGGER_GROUPS` 2 → 3. Both kept.

**Anti-pattern: DON'T apply `visibility_range_end` blanket-style.**

Committed in `eb12e5c`, reverted in `49f2ccf`. Applying
`visibility_range_end` + `VISIBILITY_RANGE_FADE_SELF` to every
`GeometryInstance3D` in every enemy mesh subtree (~3200 instances at
322 enemies × ~10 children each — body + bone-attached weapons +
outline hull etc.) added a per-frame camera-distance check + dither-
fade pass on the render thread that cost more than the LoS culler's
binary hide saves. Baseline fps dropped 58 → 44 in one commit.

If we ever want to revisit, the smart scope is:
- Apply to the SINGLE body MeshInstance3D only, not every bone
  attachment
- OR only enable when `enemy_count > N` threshold
- OR use VISIBILITY_RANGE_FADE_DISABLED (no dithering pass)

**Profiler reading lessons:**

- "Self" time mode hides cumulative cost of called children. Switch to
  "Inclusive" to find functions that look cheap but call expensive ones.
- Per-call cost in the profiler is `Time / Calls` (e.g., 0.5ms over
  1500 calls = 0.3μs each, cheap individually but adds up).
- Tree walks (`find_children` over root) at ~10k nodes cost ~5-7ms
  each. Cache the result and refresh only when `tree.get_node_count()`
  changes.
- `Performance.PHYSICS_3D_*` monitors return 0 on Jolt backend — the
  Jolt adapter doesn't expose them. Don't rely on those columns.

**CSV filter pattern that actually shows baseline:**

```bash
# Idle baseline: in-game, no firing, no spike
awk -F',' 'NR>1 && $29 == "" && $6 > 100 && $11 == 0 {fps+=$2; n++}
  END {print fps/n}' perf_log.csv
```

The mistake I made early: filtering `enemies > 100` alone catches BOTH
periodic samples (baseline) AND spike samples (transient). Periodic
samples have `event == ""`; spike samples have `event != ""`.

Related: [[project_perf_logger]], [[project_los_reveal_spikes]],
[[project_enemy_anim_pause]], [[project_enemy_physics_pause]]
