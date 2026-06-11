---
name: project-upper-body-overlay
description: Player aim/swing overlay — legs locomote via the picker while UpperBodyAimModifier blends the spine→arms to the fire pose (loop) or melee swing (one-shot). Hips is REFERENCE-ONLY (compensation), never written.
metadata:
  type: project
---

`UpperBodyAimModifier` (`scripts/characters/upper_body_aim_modifier.gd`) is a
`SkeletonModifier3D` added under the player skeleton at runtime. It runs AFTER
the AnimationPlayer and slerps the upper-body bones (spine, neck, head,
shoulders/arms/hands — `_UPPER_SHORT_NAMES`) toward a sampled clip pose, weighted
by a ramped `_weight`. The LEGS stay on the normal locomotion picker, so the
player aims/swings while moving and the feet stay grounded.

**HIPS RULE (learned the hard way, f25e918): never write the Hips bone from an
overlay — the legs hang off it.** The overlay used to stamp the fire clip's
Hips rotation to cancel strafe-clip torso twist; that rotated the whole lower
body to the fire pose's pelvis (~90° leg twist in every direction while
aiming). Fix: Hips track is sampled as a REFERENCE and the spine-root override
is pre-rotated by `hips_loc⁻¹ × hips_clip`, so the upper body reaches the
clip's authored world orientation while pelvis+legs stay locomotion-owned.
The bug hid for weeks because a second bug (facing/leg-anim picker gated on
raw `_is_attack_committed()` instead of `_attack_locks_movement()`, fixed
a763d16) froze the legs while firing — fixing the freeze exposed the twist.

Two modes (mutually exclusive — you hold a gun OR swing melee):
- **Aim hold** (ranged): `tick(delta, aiming)` loops the class fire clip; weight
  ramps in/out. `pulse_recoil()` restarts the cycle per shot.
- **Swing** (melee, MOVING only): `play_swing(clip, duration)` scrubs the swing
  clip once over the attack duration; stationary melee still plays a full-body
  swing. Driven by `_swing_overlay_if_moving()` in `prototype_player.gd`.

Player wiring (all in `prototype_player.gd`): `_drive_aim_overlay(delta)` each
tick; attack-anim choice gates on **ranged-vs-melee class** via
`_attack_is_melee()` (NOT `is_bullet_weapon()` — energy guns carry no ammo and
were wrongly swinging); BOTH the velocity gate AND the facing/leg-anim picker
gate on `_attack_locks_movement()` (ranged fire never freezes either);
locomotion `speed_scale` tracks actual horizontal velocity; moving-while-
attacking costs 60% (`ATTACK_MOVE_SLOW_FACTOR`).

**Clip grounding (a763d16):** Mixamo clips don't share a ground reference
(foot-contact minimums spanned −0.108..+0.087). `XBotAnimations.
_ground_clips_once` shifts every clip's Hips Y track so its own contact
minimum is 0, at first install on an in-tree skeleton (deaths/jumps excluded).
Without it, the idle-anchored character seat made other clips float per
equipped class (pistol strafe floated ~13cm). Measurement tool:
`scripts/tools/audit_clip_ground.gd` (contact min + hips yaw per clip).

**How to apply:** Add a new overlaid bone to `_UPPER_SHORT_NAMES` (never
Hips). For a new animated overlay, configure() it with a clip name and the
per-id track cache rebuilds. Strafe selection uses hysteresis to stop
clip-restart flicker; two authored strafe FBXs (left/right). Related:
[[project_animation_fbx_bonemap_import]], [[project_weapon_attachment]],
[[project_anim_stretch_pattern]], [[project_looping_anim_hold]].
