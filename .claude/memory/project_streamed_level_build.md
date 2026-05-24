---
name: project_streamed_level_build
description: "LevelBuilder._build_level yields every N pieces so the loading screen stays responsive; prototype_root awaits the new `built` signal before hide_loading"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

Level construction was a 5.8-second freeze at level entry: 241 enemies +
~30-40 rooms built in one synchronous frame (perf log confirmed). Fix:

1. `_build_level()` is async — yields `await get_tree().process_frame`
   after every `PIECES_PER_FRAME` pieces (currently 2).
2. New `signal built` + `var is_built: bool` on LevelBuilder.
3. New `await_built()` helper — idempotent; returns immediately if
   already built, else awaits the signal.
4. `_ready` and `rebuild` both `await _build_level()` then set
   `is_built = true; built.emit()`.
5. `prototype_root._ready` calls `await initial_builder.await_built()`
   on the non-NG+ path (NG+ already awaited via `rebuild()`).

PerfLogger emits `build_start` / `build_end` event rows so the CSV log
shows the streamed build's wall-clock duration.

**Why:** Loading-screen freeze was perceptual. Single-frame work that
takes 5.8s prevents the loading-screen draw too. Cooperative yielding
trades slightly more total wall time for a responsive UI.

**How to apply:** Any future bulk work that touches many nodes at once
(NPC spawn, prop placement, decal placement) should follow the same
pattern — batch + yield + signal-on-done.

Tunables:
- `PIECES_PER_FRAME = 2` (drop to 1 if per-piece cost grows; raise if
  hitches return)

Related: [[project_enemy_spawning_model]], [[project_ragdoll_queue]] for
the ragdoll-frame budget that sits on top of this for runtime deaths.
