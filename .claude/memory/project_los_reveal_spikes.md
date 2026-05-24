---
name: project_los_reveal_spikes
description: "LoS culler reveals entire rooms' geometry in one frame when player crosses thresholds, producing 100-240ms proc spikes"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

After fixing ragdoll spikes (2026-05-24 perf log), the dominant
remaining freezes are **proc spikes (100-240ms) when the player walks
into a new room**:

- t=475.96: 240ms proc, draws 445→895, objects 1029→1394 in one frame
- t=464.92: 162ms, t=440.93: 156ms, t=521.07: 154ms — same pattern

Signature: sudden surge in `draws` + `objects` between two adjacent
samples with no event tag = LoS culler un-hiding a room's contents all
at once. Renderer + first-time shader lookup costs spike together.

**Possible fixes (priority order):**

1. **Cap reveal count per frame** in [[los_culler.gd]] — when many cells
   need to switch to visible the same tick, fade them in over several
   frames. Trade slight pop-in for smooth frame pacing.
2. **Pre-warm room geometry shaders at level load** for the procedural
   surface shader (already partially done) — extend to kit-bash panels
   and any per-room unique materials.
3. **MMI more aggressively** — fewer draw calls means less per-reveal
   cost. Pillars/walls already batched, but per-room props are not.

The pattern only became visible after ragdoll spikes were ratelimited
(see [[project_ragdoll_queue]]) — the proc spikes were always there,
just masked by the ragdoll noise.
