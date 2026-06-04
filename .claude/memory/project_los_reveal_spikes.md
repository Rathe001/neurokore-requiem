---
name: project_los_reveal_spikes
description: "LoS culler used to flip 100s of node.visible to true in one frame at room-cross — 100-240ms proc spikes. Fixed 2026-06-04 with per-frame reveal budgets in los_culler.gd."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

## Status: FIX SHIPPED 2026-06-04

Awaiting playtest verification that the soft reveal pacing reads OK
relative to the prior frame freeze. If pop-in is visible on doorway
rush, escalate to pre-warm (next section).

## The spike (pre-fix)

When the player crossed a cell boundary into a new room, two things
happened in the same frame:

1. `_physics_process` flipped every adjacent room's MMI `visible =
   true` (no fade, hard flip) in the `_room_geometry_cache` loop.
2. `_set_target(entity, true)` was called for every entity in the
   newly-adjacent rooms, queuing them in `_transitioning`. Next
   `_process`, the loop set `node.visible = true` for all of them.

~365 entities + ~12 geometry MMIs went from "not drawn" to "drawn" in
one frame. Proc time spiked 100-240ms (perf CSV at t=475.96: 240ms,
draws 445→895, objects 1029→1394). Visible as freeze whenever player
crossed a doorway.

Pattern only became visible after ragdoll spikes were ratelimited
(see [[project_ragdoll_queue]]) — the proc spikes were always there,
just masked.

## Fix

Two budgets in `los_culler.gd`:

- `MAX_REVEAL_NODES_PER_FRAME = 12` — entity flips per `_process` render
  tick.
- `MAX_REVEAL_GEOMS_PER_TICK = 4` — room-geometry flips per
  `_physics_process` physics tick.

**Hide flips are uncapped** — the renderer just stops drawing the node,
no GPU upload cost. Only `true → visible` is budgeted.

**Budget-blocked entries stay frozen at `transparency = 1.0` with
`node.visible = false`** and retry next frame. The `_transitioning`
entry survives because `settled` now requires `los && current < 0.005
&& node.visible` (or symmetric hide) — not just transparency.
Without that, a budget-blocked reveal would settle, leave
`_transitioning`, and never get its visible flip.

**The lerp is gated too** — `if revealing and reveal_budget <= 0:
continue` before the lerp call. If the lerp ran while node was still
budget-hidden, transparency would drift toward 0, so by the time we
finally flipped `visible = true` the entity would pop in at partial
opacity instead of fading from invisible.

## Trade-off

Soft ~400-500ms reveal lag on a busy room (365 entities ÷ 12/frame ≈
30 frames at 60fps) instead of a 240ms freeze. Gradual pop-in vs
frame stutter. Player walks through doorway, sees their immediate
surroundings instantly (first 12 fade in this frame), distant enemies
in the same room appear over the next half-second as budget rolls.

## Pre-warm is the next lever if budget isn't enough

If soft lag is still visible (e.g. player rushes a doorway and sees
enemies pop in close), **pre-warm at level load**: force every room's
MMIs + entity geometry through one render frame during the loading
screen window (à la [[vfx-warmup]]). Then runtime reveals are cache-
warm and the budget can be raised or removed. Not done yet — try this
fix first.

## Other levers if needed later

- **MMI per-room props** — pillars/walls already batched; per-room
  props (crates, lockers, computers) currently aren't. Fewer draw
  calls = less per-reveal cost.
- **Tune budgets** — `12 / 4` was a first cut. If perf is still bad,
  lower; if pop-in is too obvious, raise.

## Files

- `game/scripts/systems/los_culler.gd` — new constants
  (`MAX_REVEAL_NODES_PER_FRAME`, `MAX_REVEAL_GEOMS_PER_TICK`), budget
  logic in `_physics_process` room-geometry loop and `_process` entity
  transition loop.

Related: [[ragdoll-queue]] (previous biggest spike), [[vfx-warmup]]
(pre-warm pattern if budget isn't enough).
