---
name: enemy-face-override
description: "Enemy locomotion picker reads `_face_override` Vector3 instead of always facing the move direction — lets backpedal/strafe keep weapons trained while moving perpendicular/backwards."
type: project
---

The enemy locomotion picker used to do `if moving: _face_direction(_want_dir)`. That meant when an enemy backpedaled (`_want_dir = away from player`), they faced away from the player and spun back around to fire each cycle.

**Pattern:** new `_face_override: Vector3` member, consumed by the picker before `_want_dir`:
```gdscript
if _face_override.length_squared() > 0.0001:
    _face_direction(_face_override)
elif moving:
    _face_direction(_want_dir)
```

**Reset:** `_chase_tick` zeros `_face_override` at the top of every tick. Branches that want it set assign before `return`. Currently:
- Ranged backpedal → face the player
- Melee strafe in attack range → face the player

**Pairs with the `_face_direction` slew** ([[enemy-facing-slew]]): the override sets a target yaw, the slew interpolates at 8 rad/s. Result reads as natural body rotation, not snap.

**Don't forget to reset** if you add a new branch that uses it — leftover overrides from a previous tick would keep an enemy facing the wrong direction through subsequent picker frames.

Related: [[enemy-facing-slew]], [[enemy_state_machine]].
