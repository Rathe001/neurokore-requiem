---
name: enemy-facing-slew
description: "Enemy visual rotation interpolates via rotate_toward at 8 rad/s instead of snapping on _face_direction. First call after _init_enemy still snaps so newly-spawned enemies don't slowly turn from imported default orientation."
type: project
---

`_face_direction` used to call `visual.look_at` directly — instant yaw snap. With AI logic firing facing decisions multiple times per second during combat, that read as visibly jittery.

**Architecture:**
- `_face_direction(dir)` computes target yaw via a temp `Transform3D.IDENTITY.basis.looking_at(dir, UP).get_euler().y`. Doesn't mutate the visual — just stores `_target_facing_y`.
- `_tick_facing(delta)` runs every `_physics_process` tick and slews `visual.rotation.y` toward `_target_facing_y` via `rotate_toward(from, to, delta_rad)` at `_FACING_TURN_SPEED = 8.0` rad/s (~458°/s — a full 180° flip in ~0.4s).
- **First call snaps:** `_target_facing_set` flag is false on a fresh enemy. The very first `_face_direction` call seeds `visual.rotation.y` directly so newly-pooled enemies don't slowly rotate from their imported default orientation.

**Why `rotate_toward` not `lerp_angle`:** constant angular velocity reads as physical motion. `lerp_angle` with a fixed weight is exponential — feels like swimming toward the target.

**Reset on pool re-acquire:** `_init_enemy` clears `_target_facing_set` and `_target_facing_y` so the next spawn gets the snap-on-first-call behavior.

**Tune `_FACING_TURN_SPEED`** if a specific archetype needs faster/slower turning (e.g. a tank should turn slowly, a drone should snap). Currently global.

**Slew runs on remote puppets too** — net-replicated enemies share the same smoothness without separate logic.

Related: [[enemy-face-override]] (pairs with the slew to let backpedal/strafe keep weapons on target).
