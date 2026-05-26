---
name: project_perf_session_2026_05_25
description: Long perf session on 2026-05-25 ended in a hard reset. Solid 60fps baseline restored by reverting to cea4d12 + cherry-picking bug fixes. Tag `perf-session-rollback-point` preserves the work-in-progress for revisit.
metadata:
  type: project
---

A long perf session on 2026-05-25 chased "laser pistol lag" through 15+
commits — enemy pause/throttle, HUD overlay caching, light culling,
FluorescentFlicker throttle, hitscan VFX defer + strip-down, beam mesh
sharing, PerfLogger tag_event skip-walks, etc. Most pieces measured as
wins individually but the cumulative behavior change degraded gameplay
combat fps below the 60fps baseline the user started with.

**Decision: hard reset to `cea4d12` + cherry-pick bug fixes only.**
The pre-revert HEAD was tagged `perf-session-rollback-point` (commit
`9ec0a64`) so the work isn't lost — re-pick selectively in a future
session if revisiting.

**Bug fixes that landed (kept):**
- `cea4d12` Audio panning drift fix (anchor sources to AudioListener3D)
- `461ec39` Sync melee anim peaks to impact moment + one fire SFX per
  enemy attack (was d483df3)
- `2aa73fa` Blood decals full opacity (was 8083b0a)
- `745ab2f` Slow 1H + 2H melee attack_speed (was e280196)
- `b8d31a1` Stretch blade swing — bump cooldown + lower anim speed floor
  (was 98e5ef6)
- `4e65451` interactable_builder dedup (was ba6ad31)

**Perf work REVERTED (lost — re-pick from `perf-session-rollback-point`
if revisiting):**
- Enemy `_physics_process` pause when invisible+pauseable
- Enemy anim pause when visible+IDLE+far (20m)
- LoS culler no-op guards, MAX_DIST_SQ 40→30, STAGGER_GROUPS 2→3
- ProximityLighting `light.visible = false` toggle on dim
- FluorescentFlicker throttle 60Hz → 15Hz
- HUD overlay tree-walk cache (was 7.55ms/refresh)
- Hitscan VFX defer via `tree.process_frame.connect`
- Hitscan VFX strip-down (no GPU sparks, no beam glow halo, no mid light)
- Beam mesh shared unit cylinder + per-instance scale
- PerfLogger expanded columns (enemy state, player ctx, transients,
  Jolt monitors, corpses)
- PerfLogger tag_event default skip walks

**Lessons saved here (don't forget):**

1. **Diagnostic instrumentation has real cost.** Three separate logger
   hot-spots bit us this session: HUD overlay tree-walks (~7.55ms),
   PerfLogger periodic tree-walks (~30ms), and PerfLogger tag_event
   tree-walks (~15-30ms per fire). If we add diagnostics back, design
   for low overhead from day one.

2. **`call_deferred` from `_physics_process` doesn't defer past the
   tick.** Godot's `MessageQueue.flush()` runs immediately after
   `_physics_process` callbacks and `TIME_PHYSICS_PROCESS` includes
   it. Use `tree.process_frame.connect(cb, CONNECT_ONE_SHOT)` to
   actually shift work to the idle tick.

3. **`Performance.PHYSICS_3D_*` returns 0 on Jolt backend.** The Jolt
   adapter doesn't expose those monitors. Don't waste columns on them.

4. **Don't apply `visibility_range_end` blanket-style to enemy mesh
   subtrees.** ~3200 instances at 322 enemies × ~10 children each
   produces a per-frame camera-distance check + dither-fade pass that
   cost more than the LoS culler's binary hide. Baseline dropped 58→44
   in one commit. If revisiting, scope to the single body MeshInstance3D
   only, or gate behind `enemy_count > N`.

5. **CSV idle-baseline filter that actually works:**
   ```bash
   awk -F',' 'NR>1 && $29 == "" && $6 > 100 && $11 == 0 {fps+=$2; n++}
     END {print fps/n}' perf_log.csv
   ```
   Empty event column = periodic sample, not spike. firing=0 = idle.
   Combining `enemies > 100` alone mixes periodic AND spike rows.

6. **Each "win" needs an end-to-end CSV verification.** I shipped
   multiple "improvements" that the CSV later showed weren't net wins.
   The fix loop should be: measure → change → measure → keep or
   revert. Not: change → change → change → measure once at the end.

7. **The user's perception matters more than the metric.** Even when
   the CSV showed avg baseline 58-60fps, the user kept reporting "20fps
   doing nothing." Combat-moment spikes (the user's actual frustration)
   are what they're measuring, not the periodic-sample average.

8. **Check what else is running on the machine before chasing engine
   regressions.** At the end of the session the user noted WoW was
   open in the background — WoW idles at noticeable CPU + GPU draw
   even on the login screen. Future "perf got worse" reports should
   start with "what other apps are open?" before assuming the change
   set is the culprit. This may explain part of why the cumulative
   perf work felt like it wasn't paying off — the test bench was
   noisy.

Related: [[project_perf_logger]], [[project_perf_logger_feedback]],
[[project_los_reveal_spikes]], [[project_enemy_anim_pause]]
