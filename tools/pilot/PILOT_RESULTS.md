# 2D iso pilot — results

**Status:** SHIPPED — production-ready pipeline.
**Branch:** `2d-iso-pilot` (off `2d-iso-rework`, off `main`)
**Shipped:** 2026-05-28
**Originally wrapped:** 2026-05-27 (deferred — see [history](#history))

## TL;DR

End-to-end pipeline: Midjourney ref → Meshy.ai (3D mesh + textures) →
Mixamo (rig + animations) → Blender headless render → Godot 4.6 sprite
playback. Identity-locked across every frame and facing, no
stylization step needed. Validated on 5 characters (4 player base
classes + 1 enemy), 6080 total sprites rendered cleanly.

Per-character cost: **5 min Mixamo clicking + 6–8 min render
+ ~45 MB disk** at 256² RGBA, then they're in the Godot picker.

## Pipeline

```
Midjourney character ref
    ↓
Meshy.ai image-to-3D Pro plan ($10/mo, T-Pose option, commercial-safe)
    ↓ <meshy-export>.zip or .glb
Mixamo auto-rig (place 6 markers) → Idle.fbx With Skin + anim FBXs Without Skin
    ↓ FBXs
merge_mixamo_anims.py
    ↓ Reads base + anim FBXs, retargets each anim to base bind pose,
      pushes to NLA strips, exports glTF
  build/<character>.glb
    ↓
01_render_sprite_sheet.py
    ↓ Headless Blender 5.1, ortho dimetric (30° pitch / 45° yaw),
      auto-fit ortho_scale across all frames, per-frame hip recenter
      + camera-Z tracking
  output/raw/<character>/<anim>/<dir>_<frame>.png  (256² RGBA)
    ↓
copy_sprites_to_godot.py
    ↓
  godot_test/sprites/...   →   sprite_test.tscn (Godot 4.6, AnimatedSprite2D)
```

`build_viewer.py` writes a self-contained `output/viewer.html` with
8-direction grid + single-big playback modes for browser preview.

## What ships

Five characters fully rendered:

| Character | Class | Anims | Frames | Disk |
|---|---|---|---|---|
| analog_male | Analog | 9 | 1344 | 44 MB |
| analog_female | Analog | 9 | 1344 | 45 MB |
| cyborg_male | Cyborg | 9 | 1344 | 45 MB |
| cyborg_female | Cyborg | 9 | 1344 | 46 MB |
| crimson_vein_titan | Spellcaster enemy | 5 | 736 | 26 MB |

Player anim set: `idle, walk, run, attack, attack2, dodge, jump, hit,
death`. Enemy anim set: `idle, walk, cast, hit, death`. Frame counts
per anim are tuned for 24 FPS smooth playback (12–24 frames each).

Validated in Godot 4.6 — 6112 PNGs imported clean, all five
characters playable in the test scene, looping vs one-shot semantics
working, direction switching working.

## What got solved along the way

The hard problems (and where each is solved):

| Problem | Solution | Where |
|---|---|---|
| Character identity drift across facings | Direct mesh render — same geometry, same textures every frame | `01_render_sprite_sheet.py` |
| Wide poses clipping the sprite frame | Auto-compute ortho_scale from worst-case extent across all (anim, frame) pairs | `compute_required_ortho_scale()` |
| Crouched / dying poses sliding to frame edge | Per-frame camera target Z = bbox midZ of evaluated mesh | `get_mesh_world_z_extent()` |
| Mixamo "Without Skin" bind pose ≠ character bind pose | Per-bone rotation delta baked into keyframes at merge time | `retarget_action_bind_pose()` |
| Locomotion clips with root motion sliding character offscreen | Hip bone re-anchored to world XY=0 each frame | `recenter_hip_to_origin()` |
| Multiple character bone naming conventions (Meshy auto-rig vs Mixamo) | Bone lookup helper accepts both `Hips` and `mixamorig:Hips` | `find_hip_bone()` |
| Blender 5.x layered actions API broke FCurve walking | Helper that iterates both legacy and `layers[].strips[].channelbags[]` | `iter_action_fcurves()` |
| Browser caching stale sprites in viewer | `?v=<mtime>` query string per image URL | `build_viewer.py` |

## Architecture decisions worth keeping

1. **One shared anim library per sex** (`source/player/male/` and
   `source/player/female/`), referenced by every class. Adding a new
   class is just `source/player/{sex}/{class}/Idle.fbx`
   (with skin) + config block swap. No per-class anim downloads.
2. **Bind-pose retargeting in code, not in source content.** Lets
   Meshy generate characters in whatever pose its image-to-3D
   pipeline picks (A-pose, T-pose, slight stoop) without breaking the
   shared anim library.
3. **Output structure mirrors Godot's expectations**:
   `<character>/<anim>/<dir>_<frame>.png`. The Godot loader scans the
   tree at runtime and builds `SpriteFrames` on the fly — no
   per-character `.tres` to author.
4. **Per-frame mesh-bbox camera Z, not fixed.** Without this, every
   crouched/lying pose slides to the bottom of the tile. Standing
   anims still look identical because the bbox center stays at chest
   height.
5. **Source FBXs and build GLBs live in the repo, gitignored.** No
   `~/Desktop/` paths in the pipeline — checkout works on any machine.

## Files in this directory

```
tools/pilot/
├── 01_render_sprite_sheet.py        Blender headless render (8 dirs × N anims × M frames)
├── merge_mixamo_anims.py            Mixamo base + anim FBXs → one rigged GLB w/ all actions
├── inspect_glb.py                   Diagnostic: list meshes/armatures/actions in a .glb or .fbx
├── glb_to_mixamo_fbx.py             Strip armature from a .glb → mesh-only FBX for Mixamo upload
├── build_viewer.py                  Generate self-contained output/viewer.html
├── copy_sprites_to_godot.py         Mirror PNGs into godot_test/sprites/
├── PILOT_RESULTS.md                 This file
├── README.md                        Original pipeline overview (predates current state)
│
├── source/                          (gitignored — raw FBX downloads)
│   ├── player/{male,female}/        shared anim FBXs per sex
│   │   └── <class>/Idle.fbx         per-class with-skin base
│   └── enemies/<name>/              per-enemy bases + anims
├── build/                           (gitignored — merged GLBs)
│   └── <character>.glb
├── output/                          (gitignored — render output)
│   ├── raw/<character>/<anim>/<dir>_<frame>.png
│   └── viewer.html
└── godot_test/                      minimal Godot 4.6 project
    ├── project.godot
    ├── scenes/sprite_test.tscn
    ├── scripts/sprite_test.gd
    └── sprites/                     (gitignored — populated by copy_sprites_to_godot.py)
```

## What's NOT here yet (open production questions)

These were intentionally out of scope for the pilot and need
decisions before the main game project absorbs the pipeline:

- **Item visualization.** Currently characters render without held
  weapons or swappable armor. Two paths:
  - **Path 3:** no visible gear (Hades / Hyper Light Drifter style) —
    weapons exist as stat sheets + projectile/VFX only. MVP-friendly.
  - **Path 2:** weapon-only overlay — render each weapon as a separate
    8-direction sprite, dump hand-bone screen offsets to JSON,
    composite at runtime. Higher cost but real gear visuals.
- **Environment / tile / prop sprite pipeline.** The character
  pipeline doesn't cover backgrounds. Probably MJ → flat PNG for tiles
  (no need for 8 directions on a wall).
- **Stylization pass.** Renders look like Blender renders, not painted
  bible references. A shader pass (cel-shaded outlines, palette
  posterize) in Godot might bridge the gap cheaper than re-introducing
  SDXL stylization.
- **When to merge into the main game project.** Pilot lives in
  `tools/pilot/godot_test/`. At some point the sprite content moves
  to `game/assets/sprites/` and the AnimatedSprite2D plumbing moves
  to the real player / enemy scenes. Probably after item viz decision.

## Setup checklist (for a fresh machine)

- Blender 5.1 (Windows path:
  `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`)
- Godot 4.6 — any install, `--path tools/pilot/godot_test` to open
- Python 3.11+ in PATH for `build_viewer.py` and
  `copy_sprites_to_godot.py`
- Meshy.ai Pro plan ($10/mo) for the T-Pose feature + commercial-safe
  exports
- Mixamo (adobe.com Creative Cloud account)
- ~5 GB free disk per 5 characters (source FBXs + render output +
  Godot copy)

GPU is not load-bearing — the whole pipeline runs Blender Eevee on
CPU at acceptable speed. The earlier SDXL attempt needed an RTX GPU.

## History

- **2026-05-26:** Project pivoted to 2D iso. Visual bible shipped
  (48 painted MJ refs at `docs/art-reference/`).
- **2026-05-27:** First pilot wrapped after the SDXL+IPAdapter
  stylization path hit a wall — pure parameter tuning couldn't lock
  character identity across the 8 facings. Decision deferred. This
  document originally documented that failure.
- **2026-05-28:** Pipeline rebuilt around direct mesh rendering (no
  AI stylization). Identity locking solved mathematically. Meshy →
  Mixamo → Blender → Godot end-to-end validated on 5 characters.
  SDXL stack deleted; pipeline declared production-ready.

The SDXL attempt is worth remembering as a learning, not a dead end:
the painted-bible look is still reachable if Path C (post-process
stylization) gets revisited later, and the bible refs at
`docs/art-reference/` still anchor the visual target.

## Honest assessment

The pilot answered its original question — _is 2D iso sprite
production feasible for a solo dev?_ — and answered yes, **without
needing per-character LoRA training**. The fix was lower in the stack:
swap the stylization-via-AI step for a direct mesh render with baked
textures. Identity drift disappears because it's the same mesh.

Per-character production is now a 15-minute operation
(Mixamo clicking + automated render). The full eight-class roster
(2 origins + 6 specs from `docs/classes.md`) is ~2 hours of work
when the designs are settled. The main game project absorbs the
pipeline whenever the open decisions above (item viz, stylization
pass) are nailed down.
