# 2D iso sprite pipeline

**Status:** Production-ready (shipped 2026-05-28). For the architectural
write-up — what worked, what didn't, the decisions baked in along the
way — read [`PILOT_RESULTS.md`](./PILOT_RESULTS.md). This file is the
how-to for the live pipeline.

## What this does

Turns a Midjourney character reference into a Godot-ready 8-direction
sprite sheet, with full character identity locked across every frame
and facing.

```
Midjourney ref
    ↓ image-to-3D
Meshy.ai (.glb / .fbx mesh + textures)
    ↓ upload + auto-rig + download anims
Mixamo (with-skin Idle.fbx + N anim-only FBXs)
    ↓ merge_mixamo_anims.py
build/<character>.glb            (mesh + Mixamo rig + retargeted NLA actions)
    ↓ 01_render_sprite_sheet.py
output/raw/<character>/<anim>/<dir>_<frame>.png   (256² RGBA, transparent bg)
    ↓ build_viewer.py
output/viewer.html               (browser preview, 3×3 grid or single big)
    ↓ copy_sprites_to_godot.py
godot_test/sprites/...           (Godot-importable mirror)
    ↓ sprite_test.tscn
AnimatedSprite2D playback        (validated in Godot 4.6)
```

## Adding a character (~15 min)

### 1. Generate a 3D mesh

In Meshy.ai (Pro plan recommended for T-Pose + commercial export):

1. Upload your Midjourney character reference.
2. Generate textured 3D model.
3. Apply T-Pose if Meshy supports it for your model.
4. Download as FBX (texture, biped). Keep the ZIP too — useful if you
   need to re-rig later.

### 2. Rig + download anims in Mixamo

1. Go to mixamo.com, click "Upload Character", drop in your FBX.
2. Place the 6 joint markers (chin / wrists / elbows / knees / groin).
   For body-horror characters with non-standard silhouettes, drag the
   shoulder + wrist markers slightly _outside_ the visible mesh where
   you imagine the joint should be — keeps the auto-rigger from
   merging arms into the torso.
3. Once auto-rig succeeds, your character is selected in the
   Animations tab.
4. Browse animations. For each one you want:
   - Click it.
   - Click **Download**.
   - Format: **FBX Binary (.fbx)**, FPS: **30**, Keyframe Reduction:
     **none**.
   - **Skin:** _With Skin_ for one base anim (this is the textured
     mesh you'll render). _Without Skin_ for every other anim (the
     anim FBXs are tiny — just keyframes).
   - **In Place:** _ON_ for locomotion (Walking, Running, Dodge,
     Sprint). _OFF_ for one-shots (Idle, Cast, Hit, Dying).
5. Naming convention: drop the "With Skin" file into
   `source/player/{sex}/{class}/Idle.fbx` (any anim works as the base
   — Idle is just convention). Drop the "Without Skin" anim FBXs into
   the parent sex folder so other classes can reuse them. See
   [`source/README.md`](./source/README.md) for the full layout.

### 3. Merge + render

Edit `merge_mixamo_anims.py` — copy one of the commented config blocks
at the top and point it at your new character. Then:

```pwsh
blender -b -P tools/pilot/merge_mixamo_anims.py
```

This writes `build/<character>.glb` (~25 MB) — base mesh + all anim
keyframes retargeted to the character's bind pose, glued into one
file the renderer can chew on.

Edit `01_render_sprite_sheet.py` to point `CHARACTER` at the new GLB
(uncomment one of the reference configs). Then:

```pwsh
blender -b -P tools/pilot/01_render_sprite_sheet.py
```

Render time: ~6–8 min for a 1344-frame player set, ~1–2 min for a
500-frame enemy. Output: `output/raw/<character>/<anim>/<dir>_<frame>.png`.

### 4. Preview

```pwsh
python tools/pilot/build_viewer.py
```

Opens `output/viewer.html` in your browser. Pick character / animation
from dropdowns, watch all 8 directions play in sync, or switch to
single-big mode for a 512×512 detail view.

### 5. Test in Godot

```pwsh
python tools/pilot/copy_sprites_to_godot.py             # all chars
python tools/pilot/copy_sprites_to_godot.py <name> ...  # subset
godot --path tools/pilot/godot_test
```

Run the project. Pick character / anim / direction / FPS in the
panel. Looping anims (idle / walk / run) loop; one-shots play once
and freeze on the last frame — re-pick to replay.

## Adding an animation

If you want to add (say) a Spell Cast 2 to every player class:

1. In Mixamo, with any one player character selected, download the
   new anim as **Without Skin**.
2. Drop the FBX into `source/player/{sex}/`.
3. In `merge_mixamo_anims.py`, add the filename to
   `SHARED_MALE_ANIMS` / `SHARED_FEMALE_ANIMS` with a clean output
   slug (e.g. `"cast2"`).
4. In `01_render_sprite_sheet.py`, add the slug to `PLAYER_ANIMS`
   with a frame-count sample (e.g. `("cast2", "cast2", 20)`).
5. Re-merge + re-render every player character.

The bind-pose retargeter handles the per-character delta automatically
— you don't need to re-download the same anim per character.

## Knobs (top of `01_render_sprite_sheet.py`)

| Constant | Default | Effect |
|---|---|---|
| `RESOLUTION` | 256 | Render dimensions. Bump to 512 for hero shots; cost scales quadratically. |
| `RECENTER_PER_FRAME` | True | Hip anchored to world XY=0 each frame. Disable if you want raw root motion. |
| `CAMERA_PITCH_DEG / CAMERA_YAW_DEG` | 30 / 45 | Iso angle. D2 used ~26.5°/45°. |
| `CAMERA_ORTHO_SCALE` | 2.2 | Fallback if dynamic fit fails. Otherwise overridden per character. |
| `ORTHO_SCALE_MARGIN` | 1.10 | Headroom around the worst-case pose. |
| `TARGET_CHARACTER_HEIGHT` | 1.8 m | Auto-scale target. |

For animation timing knobs (sample counts per anim), edit
`CHARACTER["animations"]` directly. Frame counts assume 24 FPS playback
in-engine; halve for D2-retro 12 FPS feel.

## Setup checklist (fresh machine)

- Blender 5.1 — Windows default install path works:
  `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`
- Godot 4.6 — any install on PATH
- Python 3.11+ on PATH (for `build_viewer.py` /
  `copy_sprites_to_godot.py`)
- Meshy.ai Pro ($10/mo) — T-Pose + commercial-safe exports
- Mixamo (adobe.com account)
- ~5 GB disk per 5 characters (source FBXs + GLBs + renders + Godot copies)

GPU isn't load-bearing — the pipeline runs CPU-bound Blender Eevee.
The earlier SDXL stylization attempt did need a GPU; that path was
abandoned in favor of direct mesh rendering.

## Files in this directory

```
tools/pilot/
├── 01_render_sprite_sheet.py        Blender headless render
├── merge_mixamo_anims.py            Mixamo FBXs → one rigged GLB
├── inspect_glb.py                   Diagnostic for .glb / .fbx contents
├── glb_to_mixamo_fbx.py             Strip an existing rig → mesh-only FBX for Mixamo
├── build_viewer.py                  Generate output/viewer.html
├── copy_sprites_to_godot.py         Mirror renders to godot_test/sprites/
├── PILOT_RESULTS.md                 Architectural write-up
├── README.md                        This file
│
├── source/   (gitignored)           Raw FBX downloads
├── build/    (gitignored)           Merged GLBs
├── output/   (gitignored)           Render PNGs + viewer.html
├── godot_test/                      Godot 4.6 sprite playback test
│
└── 02_stylize.py, 03_restore_alpha.py, canonical_character.png
    Retired: relics from the abandoned SDXL stylization path. See
    PILOT_RESULTS.md → History for context. Not part of the live
    pipeline; kept in tree for traceability.
```
