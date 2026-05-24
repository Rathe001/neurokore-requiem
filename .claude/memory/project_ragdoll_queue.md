---
name: project_ragdoll_queue
description: "RagdollQueue autoload caps XBotRagdoll setup+activate at N/frame so multi-kill explosions don't stack 100-200ms spikes"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`RagdollQueue` autoload (`scripts/systems/ragdoll_queue.gd`) ratelimits
`XBotRagdoll.setup` + `activate` calls. Each pair builds 20
`PhysicalBone3D` + 20 Jolt joints (~30-50ms locally) — perf logs showed
5 simultaneous crit/explosion deaths producing a single 196ms frame
spike. Spreading the work across frames keeps each frame under ~50ms.

Usage in `prototype_enemy._die()`:

```gdscript
var got_slot := await RagdollQueue.await_slot()
if not is_inside_tree() or _generation != gen:
    return
if not got_slot:
    # budget saturated → degrade to legacy capsule corpse
    _spawn_ragdoll_corpse(...)
    did_skeletal_ragdoll = true
    return
XBotRagdoll.setup(skel)
...
```

Tunables in the autoload:
- `MAX_RAGDOLLS_PER_FRAME = 2` (bump for more carnage, drop if 2 hitches)
- `AWAIT_MAX_FRAMES = 8` (caller falls back to legacy capsule on saturation)

Related: [[project_xbot_ragdoll]] for ragdoll mechanics,
[[project_godot4_runtime_gotchas]] for the Jolt setup quirks the queue
sits on top of.
