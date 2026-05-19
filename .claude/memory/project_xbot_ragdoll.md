---
name: xbot-ragdoll
description: "X Bot per-bone ragdoll: PhysicalBone3D × 20 major bones with cone joints + capsule shapes. Status: WIP — bones still snap to T-pose on death even after pose-sync. Diagnostic logging in place."
type: project
---

**Status (2026-05-19).** Per-bone ragdoll setup compiles, simulates,
and accepts kill-impulses on hip + spine (corpses get sent flying
correctly). **Unsolved**: corpses visually snap to T-pose on
simulation start, regardless of which animation was playing at the
moment of death. Diagnostic logging added in
`XBotRagdoll.activate()` logs the LeftArm pre-sim pose vs. its
bind-rest — first thing to check on resume.

**Architecture.** `xbot_ragdoll.gd` is a static helper, two methods:
- `setup(skeleton)` — called deferred from `PrototypeEnemy._ready`.
  Adds 20 PhysicalBone3D children to the Skeleton3D (hips, spine ×3,
  neck, head, both arms (shoulder/upper/lower/hand), both legs
  (thigh/calf/foot)). Skips fingers. Each PhysicalBone3D gets a
  CapsuleShape3D sized to the bone's rest-length, anatomical mass
  (hips 12kg → hands 0.8kg, total ~68kg), joint_type=CONE,
  layer 6 (Corpses), and joint_constraints set with 90° swing /
  60° twist / bias=0 / softness=1. Tolerates both `mixamorig_*`
  and humanoid profile bone names (BoneMap retarget may rename).
  Idempotent — sets `xbot_ragdoll_setup` meta on the skeleton.
- `activate(skeleton, kill_from, kill_force)` — orthonormalizes each
  PhysicalBone3D's basis (kills Jolt non-uniform scale spam), syncs
  each PhysicalBone3D's transform to its bone's `get_bone_global_pose`
  (intended to inherit the death-moment animated pose), then calls
  `physical_bones_start_simulation()`. Applies a kill-direction
  impulse to Hips+Spine bones, scaled `dir * kill_force * pb.mass * 6.0`.

**What works.**
- 20 PhysicalBone3D nodes attach correctly per skeleton (diagnostic
  print confirms).
- `physical_bones_start_simulation()` runs.
- Kill-impulse launches corpses with appropriate velocity (impulse
  must be Newton-seconds = mass × Δv, hence the per-bone-mass scale).
- Joints hold the skeleton together — no detaching limbs.

**What doesn't work.**
- Corpses land in T-pose configuration regardless of what animation
  was playing alive. Attempts so far:
  - Tightened cone (40° swing, bias 0.6) → corpses pulled toward T.
  - Widened cone (90° swing, bias 0) → corpses still T-pose-ish.
  - Synced PhysicalBone3D transforms from `get_bone_global_pose`
    before simulation start → no visible change.
  - `anim_player.stop(true)` before activate → unchanged.

**Suspected root cause.** Either (a) the AnimationPlayer never wrote
actual deformation to the skeleton — bones stay at bind rest because
the X Bot animations' track paths target the wrong bone names after
the BoneMap retarget pass, OR (b) `physical_bones_start_simulation`
internally resets bones to bind before reading from PhysicalBone3D
transforms. The diagnostic line `[XBotRagdoll] LeftArm pre-sim pose
origin=... rest origin=... rot equal=true/false` will tell us
which: `rot equal=true` → (a); `rot equal=false` → (b).

**Tuning constants** (`xbot_ragdoll.gd` top of file):
- `_BONES` array — (bone_name, mass_kg, capsule_radius_m, joint_type)
- Joint config in setup loop: `swing_span`, `twist_span`, `bias`,
  `softness`, `relaxation`
- `IMPULSE_SCALE` in activate (currently 6.0): launch magnitude

**Integration.** `PrototypeEnemy._die` branches on
`skel.has_meta("xbot_ragdoll_setup")`: if true, stops AnimationPlayer
+ calls `XBotRagdoll.activate(skel, kill_from, kill_force)`. If
false (legacy UAL1 char_model), falls through to the existing
`PrototypeRagdollCorpse` rigid-body tumble. The fallback should
stay supported — easiest hedge if the per-bone path proves
fundamentally broken is to revert _die to always use it.

**If pivoting away from per-bone ragdoll**, the alternative the user
already considered was "play death animation, then static corpse" —
no physics, just freeze on the last animation frame. Much simpler
implementation (no PhysicalBone3D setup), preserves the authored
Mixamo death pose. Trade-off: explosions/players can't physics-kick
the corpse.
