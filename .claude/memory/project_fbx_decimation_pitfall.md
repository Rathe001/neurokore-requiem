---
name: project_fbx_decimation_pitfall
description: "Don't decimate Mixamo character FBXs via Blender round-trip — breaks the X Bot animation library's bone-path resolution. GLB decimation is fine; character FBX needs a different pipeline."
type: project
---

**Don't try to decimate `game/assets/characters/*/Idle.fbx` (or any
Mixamo-rigged FBX) by import-decimate-export through Blender 5.x.**
It looks like it works (file exports, tri count drops, file
re-imports), but the X Bot animation library can no longer play
animations on the resulting character — every clip in `xbot/*`
fails with errors like:

```
_update_caches: AnimationMixer (at: player_female_idle.fbx):
'xbot/cast', couldn't resolve track:
'%GeneralSkeleton:mixamorig_RightToeBase'
```

**Why.** The X Bot animation library is built once from the original
FBXs and cached as `AnimationLibrary` resources. Each animation track
references bones by path (e.g. `%GeneralSkeleton:mixamorig_*`). The
`%` is Godot's unique-node reference. After Blender 5.x's FBX
round-trip:
- The skeleton gets renamed (Blender may name it `Armature`,
  Godot's gltf/fbx importer normalizes to `GeneralSkeleton`, etc.)
- The unique-name reference no longer matches the new tree
- Animation tracks targeting `%GeneralSkeleton:...` fail to resolve
  even though equivalent bones exist under a different parent

This affects every clip in `xbot/idle`, `xbot/cast`, `xbot/jog`,
the death pool, etc. — i.e. every animation the character would
ever play. Result: character renders frozen in T-pose (or whatever
the Idle FBX's bake pose is), 1300+ "couldn't resolve track"
warnings per second.

**Diagnostic signature**: in Godot, errors look like
`_update_caches: AnimationMixer (at: <character>_idle.fbx):
'xbot/<anim>', couldn't resolve track '%GeneralSkeleton:mixamorig_*'`.
Appears the moment any character with the round-tripped FBX is
instantiated.

**What's safe.**
- **GLB decimation** through the same Blender pipeline (`tools/
  decimate_meshes.py`) is fine. Weapons / props / VFX / static
  meshes have no armature so no bone-path issue. The 2026-06-01
  pass got 16 GLBs from 1.17M → 286K tris (75% reduction) without
  problems. Memory: [project_xbot_character] explains the
  library setup the FBX path collides with.

**Reverting an FBX you've already decimated.** Backup tag
`pre-decimate-2026-06-01` preserves the originals. Restore via:
```
git checkout pre-decimate-2026-06-01 -- <path/to/the.fbx>
rm game/.godot/imported/<basename>.fbx-*.{scn,md5}
# then run Godot --headless --import to refresh the import cache
```

**Future paths if character tri reduction becomes necessary.**
1. **Rokoko / Auto Rig Pro Blender plugin** — proper Mixamo
   retargeting workflow preserves bone naming + hierarchy across
   round trips. Half a day of setup per character but the FBX
   round-trip becomes safe.
2. **Replace meshes with lower-poly Meshy variants** — the new
   character meshes on `2d-iso-rework` are already 10-20K tris
   each (vs the X Bot pipeline's 30-50K). Use those instead.
3. **Rely on Godot's auto-LOD.** Audit tri counts are LOD0; at
   iso distance the renderer probably draws LOD2 or LOD3 which is
   already a fraction of LOD0. Force higher `mesh_lod_threshold`
   per character to push lower LODs sooner — no source changes.

**Why the X Bot animation library is so brittle here.** The library
is class-level cached + shared across every character (every player
gender, every enemy variant). One broken FBX doesn't break that
character only — it breaks the library's playback on every
character that has the round-tripped skeleton. So a smoke test on
one character is sufficient signal to abort the whole batch.
