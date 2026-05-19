# X Bot — Mixamo base humanoid + animations

Mixamo's free auto-rigged humanoid, used as the project's standard
rig for the player and all humanoid enemies. Animations downloaded
from Mixamo target this character's skeleton and retarget cleanly via
Godot's BoneMap onto any other Mixamo-skeleton mesh.

## Files in this folder

- `XBot.fbx` (or `X_Bot.fbx`) — the rigged character mesh, T-pose.
  Download once, "With Skin", no animation selected.
- `*_walk.fbx`, `*_run.fbx`, ... — animation-only FBXs. Download
  each "Without Skin" — Godot retargets onto the character skeleton.

## Import settings (CRITICAL — set these the first time)

Mixamo FBXs are exported at 100× scale (centimetres → metres) and
Godot's default FBX import will leave the character 100× too big in
the level. Fix in the import dock:

1. Select the `.fbx` in the FileSystem dock.
2. Switch to the **Import** tab on the right.
3. Find the **Scale Mesh** field (or **Pre-Apply / Scale Factor**
   depending on Godot version) and set it to **0.01**.
4. Click **Reimport**.

For the BoneMap auto-mapping (so animations retarget):

1. Still in the Import tab, expand the **Retarget** section.
2. Create a new **BoneMap** resource.
3. Set its **Skeleton Profile** to `SkeletonProfileHumanoid`.
4. Click the **auto-map** button (the small wand icon). Most bones
   will map automatically because Mixamo's `mixamorig:*` names
   match the profile reasonably well.
5. Eyeball the result for any unmapped bones (fingers often miss);
   manually pair them by clicking the bone name in the profile and
   selecting the matching mixamorig bone from the dropdown.
6. **Save** the BoneMap as `res://assets/characters/x_bot/x_bot_bonemap.tres`
   so the same map can be reused for animation FBXs.
7. **Reimport**.

Repeat steps 1–4 + 6 (load existing BoneMap) for each animation FBX
so they all retarget to the same skeleton profile. Godot will then
let you cross-play any animation on any character that uses the
same profile.

## Why scale 0.01 vs. 1.0

Mixamo authors characters at human scale measured in centimetres, so
the FBX records a 1.78m-tall character as 178 units tall. The Godot
project (and our wall heights, etc.) are in metres — so 178 reads as
a 178-metre giant. The 0.01 scale factor brings the character to ~1.78m,
matching the wall_height of 3m sensibly.

## Why "Without Skin" for animations

The animation-only FBX is ~10× smaller than the skinned one. Godot
loads the skeleton from the character FBX once, and each animation
FBX just provides the per-bone keyframes. No duplicated mesh data.

## Bone-name remap reference

For manual mapping, the most common pairs:

| SkeletonProfileHumanoid | Mixamo                  |
| ----------------------- | ----------------------- |
| Root                    | (model root)            |
| Hips                    | mixamorig:Hips          |
| Spine                   | mixamorig:Spine         |
| Chest                   | mixamorig:Spine1        |
| UpperChest              | mixamorig:Spine2        |
| Neck                    | mixamorig:Neck          |
| Head                    | mixamorig:Head          |
| LeftShoulder            | mixamorig:LeftShoulder  |
| LeftUpperArm            | mixamorig:LeftArm       |
| LeftLowerArm            | mixamorig:LeftForeArm   |
| LeftHand                | mixamorig:LeftHand      |
| LeftUpperLeg            | mixamorig:LeftUpLeg     |
| LeftLowerLeg            | mixamorig:LeftLeg       |
| LeftFoot                | mixamorig:LeftFoot      |
| LeftToes                | mixamorig:LeftToeBase   |
| (mirror Right.*)        | (mirror mixamorig:Right.*) |

Finger bones (`Left/RightThumb_Proximal/Intermediate/Distal`,
`Index_*`, `Middle_*`, `Ring_*`, `Little_*`) map to
`mixamorig:LeftHandThumb1/2/3`, `LeftHandIndex1/2/3`, etc.
