---
name: project-upper-body-overlay
description: Player aim/swing overlay — legs locomote via the picker while UpperBodyAimModifier blends the spine→arms to the fire pose (loop) or melee swing (one-shot)
metadata:
  type: project
---

`UpperBodyAimModifier` (`scripts/characters/upper_body_aim_modifier.gd`) is a
`SkeletonModifier3D` added under the player skeleton at runtime. It runs AFTER
the AnimationPlayer and slerps the upper-body bones (spine, neck, head,
shoulders/arms/hands — `_UPPER_SHORT_NAMES`) toward a sampled clip pose, weighted
by a ramped `_weight`. The LEGS stay on the normal locomotion picker, so the
player aims/swings while moving and the feet stay grounded.

Two modes (mutually exclusive — you hold a gun OR swing melee):
- **Aim hold** (ranged): `tick(delta, aiming)` loops the class fire clip; weight
  ramps in/out. `pulse_recoil()` restarts the cycle per shot.
- **Swing** (melee, MOVING only): `play_swing(clip, duration)` scrubs the swing
  clip once over the attack duration; stationary melee still plays a full-body
  swing. Driven by `_swing_overlay_if_moving()` in `prototype_player.gd`.

Player wiring (all in `prototype_player.gd`): `_drive_aim_overlay(delta)` each
tick; attack-anim choice gates on **ranged-vs-melee class** via
`_attack_is_melee()` (NOT `is_bullet_weapon()` — energy guns carry no ammo and
were wrongly swinging); `_attack_locks_movement()` no longer freezes melee
(skill casts + bare-hand punches still anchor); locomotion `speed_scale` tracks
actual horizontal velocity; moving-while-attacking costs 60%
(`ATTACK_MOVE_SLOW_FACTOR`, replaced the old backpedal penalty).

**Why:** The old approach swapped the WHOLE body to the fire/swing clip while
attacking — floated feet (fire clip hips sit higher) and froze the legs. The
overlay is additive: at weight 0 it's a no-op, so it can't break locomotion.

**How to apply:** Add a new overlaid bone to `_UPPER_SHORT_NAMES`. For a new
animated overlay, configure() it with a clip name and the per-id track cache
rebuilds. Strafe quirks live nearby: single right `Strafe.fbx`, left is a
runtime mirror via `_extract_mirrored` (swap L/R bones, reflect X) that SKIPS
the Hips so the root facing isn't spun; strafe needs `STRAFE_ANIM_SPEED_MULT`
(~2x) because its baked ground speed is half the run clips'. Strafe selection
uses hysteresis to stop clip-restart flicker. Related:
[[project_animation_fbx_bonemap_import]], [[project_weapon_attachment]],
[[project_anim_stretch_pattern]], [[project_looping_anim_hold]].
