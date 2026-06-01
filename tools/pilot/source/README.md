# tools/pilot/source/

Source FBX/GLB/ZIP assets for the sprite generation pipeline. **Tracked
via Git LFS** (configured in the repo-root `.gitattributes`) so the
~1 GB of Meshy/Mixamo binaries don't bloat the main pack history.

Layout (matches the user's local `~/Desktop/models/` tree so they can
be synced 1:1 with robocopy):

```
source/
  player/
    male/, female/
      <shared anim FBXs>.fbx       <- without skin Mixamo downloads
      <class>/
        Idle.fbx                   <- with skin Mixamo download
        Meshy_AI_*.zip             <- original Meshy export (archival)
  enemies/
    <name>/
      <Mixamo with-skin .fbx>
      <Mixamo without-skin anim .fbx files>
      Meshy_AI_*.fbx               <- original Meshy export (archival)
  environment/
    floors/   <- MJ texture PNGs   (top-down, tileable)
    walls/    <- Meshy GLBs        (full 3D wall sections)
    doors/    <- Meshy GLBs        (full 3D door pieces)
  items/
    <type>/   <- Meshy zips        (props, consoles, chests, etc.)
```

## Sync from local Desktop

The canonical structure lives in the repo. To sync your local
Desktop into the repo:

```pwsh
robocopy "$env:USERPROFILE\Desktop\models" `
         "C:\Users\josh\Projects\neurokore-requiem\tools\pilot\source" `
         /MIR /XF *.tmp /XD *_extracted
```

`/MIR` makes the repo source/ exactly match Desktop — adds new files,
deletes any extras in the repo. Safe because everything is tracked
in git.

## Selecting which asset the renderer uses

`02_render_environment.py` has two constants near the top
(`FLOOR_TEXTURE_PATH` and `WALL_GLB_PATH`) that point at specific
files inside `source/environment/`. Change those to swap which variant
gets rendered.
