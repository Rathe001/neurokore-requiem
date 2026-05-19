---
name: xbot-character-pipeline
description: "Mixamo X Bot is the humanoid mesh + animation source for player and enemies. FBX-per-clip + shared BoneMap + runtime AnimationLibrary merge. Per-FBX retarget config sits in each .fbx.import's _subresources."
type: project
---

**Source.** Mixamo's free X Bot humanoid + 7 stock animations live in
`game/assets/characters/x_bot/`: `X Bot.fbx` (rigged mesh, T-pose) and
`Idle.fbx`, `Slow Run.fbx`, `Fast Run.fbx`, `Punching.fbx`, `Firing
Rifle.fbx`, `Hit Reaction.fbx`, `Jumping.fbx`, `Death From The
Front.fbx`. All downloaded **"Without Skin"** for animation FBXs so
they're motion-only (~10× smaller). Free for commercial use under
Adobe's terms — including Steam release, no credit required.

**Bone naming.** Godot 4.6's ufbx importer (`fbx/importer=0`) reads
Mixamo's `mixamorig:Bone` names and rewrites `:` to `_`, so runtime
bone names are `mixamorig_Hips`, `mixamorig_LeftArm`, etc. ufbx
handles cm→m unit conversion natively, so `nodes/root_scale=1.0`
is correct — explicitly setting 0.01 (the old FBX2glTF habit) makes
a 1.78cm enemy invisible at iso distance.

**BoneMap.** `x_bot_bonemap.tres` maps every humanoid profile bone
to its `mixamorig_*` counterpart. Assigned per-FBX via the Import
dock's `Advanced... → Skeleton3D → Retarget → Bone Map` field; each
`.fbx.import` ends up with a `_subresources["nodes"]["PATH:Skeleton3D"]
["retarget/bone_map"]` reference. **Critical**: every animation
FBX needs the same BoneMap assigned, otherwise its tracks don't
retarget cleanly onto the X Bot skeleton.

**Animation library**. `xbot_animations.gd` is a static helper that
preloads the 8 animation FBXs, walks each one's embedded
AnimationPlayer, pulls out the first non-RESET clip, duplicates +
loop-flags it, and assembles a single `AnimationLibrary` under the
name `"xbot"`. Cached at class level — `get_library()` builds once
on first call. `install_on(ap)` adds the library to any
AnimationPlayer idempotently. The merged keys are `idle`, `slow_run`,
`fast_run`, `punch`, `fire`, `hit`, `jump`, `death` — combat_constants
candidate arrays prefix `"xbot/<key>"` so `_play_anim` finds them
before falling back to legacy UAL1 / Quaternius names.

**Why the runtime merge instead of one big FBX**. Mixamo lets you
download multi-clip "packs" but the BoneMap retarget then has to
play retargeting tricks per clip; the per-FBX path with a single
shared library is cleaner and lets us swap individual clips
without re-downloading the whole pack.

**Adding a new animation.** Download from Mixamo Without Skin →
drop the `.fbx` into `game/assets/characters/x_bot/` → assign the
shared `x_bot_bonemap.tres` via Advanced → Retarget → Reimport →
preload it in `xbot_animations.gd` and call `_extract` with a new
key → add the qualified key (`"xbot/<key>"`) to the relevant array
in `combat_constants.gd`.

**Hip-track strip.** Mixamo's Run / Walk clips bake forward
locomotion into the hip bone's TYPE_POSITION_3D track. CharacterBody3D
drives the actual movement, so we re-anchor every hip-position
key to the first key's X/Z (Y stays for vertical bob). Without this
the visual drifts away from the body each animation cycle. Done in
`_extract` when `strip_hip_position=true` (passed for run clips).

**File locations.**
- `game/assets/characters/x_bot/` — FBX assets + BoneMap.tres + README
- `game/scripts/characters/xbot_animations.gd` — library merger
- `game/scripts/util/combat_constants.gd` — candidate arrays
- `game/scripts/prototype/prototype_enemy.gd` — calls install_on in _ready
- `game/scenes/prototype/prototype_enemy.tscn` + `prototype_ranged_enemy.tscn` —
  char_model ext_resource points at `X Bot.fbx`
