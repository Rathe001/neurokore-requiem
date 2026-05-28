# tools/pilot/source/

Source FBX assets for the sprite-generation pipeline. **Gitignored**
because raw FBXs are large binaries; download them again from Meshy /
Mixamo if you need them on a fresh machine.

Layout (canonical):

```
source/
  player/
    male/
      Walking.fbx, Running.fbx, ...     <- shared player anims (without skin)
      analog/
        Idle.fbx                        <- "with skin" base (~21 MB)
        <Meshy zip>                     <- original Meshy export (optional)
      cyborg/
        Idle.fbx
        <Meshy zip>
    female/
      (mirror of male/ once female anims are downloaded)
  enemies/
    <enemy_name>/
      <Mixamo "with skin" base>.fbx
      <other anim>.fbx ...
```

The "shared" anim FBXs sit at `player/male/` and `player/female/` so
every class in that sex reuses the same library. The merger
(`tools/pilot/merge_mixamo_anims.py`) handles per-character bind-pose
retargeting so even characters rigged in different rest poses can use
the same anim set.

To download fresh anims:

1. Upload your character `.fbx` (or its mesh `.zip`) to mixamo.com
2. Place 6 joint markers (auto-rigger). Drag wrist/ankle/elbow/knee
   markers slightly outside the silhouette where the joint should be.
3. Download `Idle.fbx` (or any anim) **With Skin** — this is the
   character base. Drop in `source/player/{sex}/{class}/`.
4. Browse Animations, download each anim **Without Skin**, FBX Binary,
   30 FPS, no keyframe reduction. **In Place: ON** for locomotion
   (Walking, Running, Dodge, Sprint). Drop into the parent sex folder.
