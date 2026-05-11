---
name: Death animations and corpses
description: Persistent corpses implemented in 3D prototype with bounded pool; zone persistence still TODO
type: project
originSessionId: 22dbe090-8006-4f89-8d5b-a0309affea09
---
3D prototype now has persistent corpses: dead enemies play their death animation and are then left in whatever pose the animation ends on (no flattening). If the rigged model lacks a death clip, a one-time fallback rotation tips them over on the X axis. On completion they're moved to `&"corpses"` group, collision disabled, floor ring hidden. A corpse manager on the root enforces `MAX_CORPSES = 100` with FIFO pruning.

**Why:** corpses in the world are part of the gritty/body-horror tone (see docs/world/tone.md) and give visible feedback that a zone has been cleared — reinforces the D2-style "enemies are pre-placed, fully clearable, no respawn" model. The flattening tween was removed on user feedback — unaltered model in its death pose reads better.

**How to apply:** corpse-pool cap is per-scene right now. When building real zones, persistence across zone swaps still needs work — corpses currently die with the scene. Design the zone entity cache to hang onto corpse nodes across zone transitions, not just the enemy roster.
