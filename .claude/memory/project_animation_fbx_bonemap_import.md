---
name: project-animation-fbx-bonemap-import
description: Every new Mixamo animation FBX MUST be imported with the x_bot_bonemap retarget or its tracks silently fail to bind — clip "plays" but no bones move
metadata:
  type: project
---

When adding a new animation `.fbx` under `res://assets/animations/`, its
`.fbx.import` MUST carry the BoneMap retarget that every other animation FBX
has, or the clip's bone tracks will not resolve on the shared skeleton at
runtime:

```
_subresources={
"nodes": { "PATH:Skeleton3D": {
"retarget/bone_map": Resource("res://assets/characters/x_bot/x_bot_bonemap.tres")
} } }
```

Without it the tracks stay `Skeleton3D:mixamorig_*`; WITH it the retarget moves
the skeleton to the scene-unique `%GeneralSkeleton:mixamorig_*` form that the
player/enemy skeletons actually expose. Mismatch → AnimationMixer logs
`couldn't resolve track: 'Skeleton3D:mixamorig_RightUpLeg'` (one per bone per
character — hundreds of warnings) and the clip plays with ZERO bone movement.

**Why:** Strafe.fbx was copied in and imported headless (`--headless --import`),
which uses DEFAULT settings (`_subresources={}`). The strafe clip was selected
and "playing" (current_animation correct, speed_scale fine) but the character
froze because not one track bound. Burned many round trips chasing the picker /
anim-speed before the `couldn't resolve track` warnings revealed it.

**How to apply:** After dropping a new animation FBX in, open it in the editor
(Import dock) and assign the BoneMap on the Skeleton3D node, OR copy a working
animation's `.import` `_subresources` block before reimporting. Verify by
probing `track_get_path(0)` — it should read `%GeneralSkeleton:mixamorig_Hips`,
matching `Idle.fbx`. The headless `--import` will NOT add the bone map for you.
Related: [[project_xbot_character]], [[project_resource_loader_gotcha]].
