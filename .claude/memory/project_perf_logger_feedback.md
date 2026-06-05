---
name: project_perf_logger_feedback
description: "PerfLogger spike rows used to fire every frame during sustained slowdowns, each doing expensive tree walks that fed back into the next frame's measured proc time, locking into permanent spike mode"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

PerfLogger had a positive feedback loop: any frame with proc>50ms or
phys>50ms wrote a spike row, and each row did three `find_children`
recursive walks of the entire tree (~6654 nodes → ~25ms overhead).
That overhead was measured by `Performance.TIME_PROCESS` on the next
frame, triggering another spike row, etc. Once the system entered
spike mode it never recovered — sustained 60-100ms proc with player
idle (vs. expected 14ms baseline).

Symptom in 2026-05-24 perf log: post-build steady-state proc stuck
at 65-100ms with player at spawn, screenshot showing 156 draws and
115k tris. Hardware should handle that easily. CPU was the
bottleneck, and the logger was 30-50% of it.

Fix (shipped 2026-05):
- Spike rows throttled to one every 200ms (`SPIKE_MIN_INTERVAL_SEC`)
- Spike rows skip the expensive tree walks (`skip_tree_walks` param
  to `_write_row`); periodic 1Hz samples and event tags still do
  full enumeration so trend data is preserved

**Lesson:** any per-frame instrumentation that runs only on spike
detection must not contribute meaningfully to the metric it's
measuring, or it self-amplifies. Throttle aggressively or sample
without measuring the sampler's cost.

Related: [[project_streamed_level_build]] — same log showed the
build appearing to take 10s; the logger was actually eating each
yielded frame, real build time is closer to 5-6s.
