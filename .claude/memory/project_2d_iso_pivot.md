---
name: project_2d_iso_pivot
description: 2D iso sprite ARPG pivot 2026-05-26. Production pipeline shipped 2026-05-28 — Meshy→Mixamo→Blender→Godot, identity-locked, validated end-to-end on 5 characters.
metadata:
  type: project
---

On 2026-05-26 the project pivoted from fixed-camera 3D to 2D iso sprite
ARPG. The 1990s D2/Sanitarium/Crusader: No Remorse painted look is the
target. 3D work is preserved on `main`; the rework lives on
`2d-iso-rework` (visual bible) and `2d-iso-pilot` (production pipeline).

**Why pivoted:** Josh's original game-design vision was 1990s painted
ARPG, but he'd assumed 3D would be easier for AI workflows. The
reverse is true — 2D iso sprite production is dramatically easier to
scope, iterate, and automate.

## Visual bible (shipped 2026-05-26)

48 painted-style MJ references at `docs/art-reference/` across env /
chars / monsters / UI / icons / VFX. Every asset class has a locked
`--sref` anchor.

## Production pipeline (shipped 2026-05-28)

Full end-to-end Midjourney → Godot playback. All scripts in
`tools/pilot/`, full how-to in `tools/pilot/README.md`,
architectural write-up in `tools/pilot/PILOT_RESULTS.md`.

```
Midjourney ref → Meshy.ai (3D mesh + textures)
              → Mixamo (auto-rig + anim downloads)
              → merge_mixamo_anims.py (one .glb with retargeted NLA actions)
              → 01_render_sprite_sheet.py (Blender headless, 8 dirs × N anims × M frames)
              → output/raw/<character>/<anim>/<dir>_<frame>.png (256² RGBA)
              → build_viewer.py → output/viewer.html (browser preview)
              → copy_sprites_to_godot.py → godot_test/sprites/
              → sprite_test.tscn (Godot 4.6 AnimatedSprite2D playback)
```

**Shipped on 5 characters** (~15 min Mixamo clicking + ~6-8 min render
per character):
- analog_male, analog_female, cyborg_male, cyborg_female (each 9 anims
  × 8 dirs × 12-24 frames = 1344 sprites, ~45 MB)
- crimson_vein_titan enemy (5 anims × 8 dirs × 6-24 frames = 736
  sprites, ~26 MB)
- 6080 total sprites validated in Godot 4.6

**Key technical solves** (each one bit us before it got fixed):
- Identity locking: direct mesh render with baked textures (no AI
  stylization — abandoned the SDXL stack 2026-05-28)
- Bind-pose mismatch: per-bone rotation delta baked into keyframes
  in `retarget_action_bind_pose()` — lets the shared anim library
  work across characters with different rest poses (Meshy generates
  A-pose, Mixamo's "Without Skin" anims assume T-pose)
- Per-frame camera Z tracking + dynamic ortho_scale: crouched/dying
  poses stay centered, wide poses don't clip
- Hip recentering: locomotion clips with root motion stay in-frame
- Blender 5.x layered action API: `iter_action_fcurves()` walks
  `action.layers[].strips[].channelbags[].fcurves` (legacy
  `action.fcurves` was removed)
- Browser cache: `?v=<mtime>` query string per image in
  build_viewer.py — was a major time sink before

## Architecture decisions worth keeping

1. **Shared anim library per sex** (`source/player/{male,female}/`).
   New class = drop a with-skin `Idle.fbx` in
   `{sex}/{class}/Idle.fbx`, copy a config block in merger + renderer,
   run. No per-class anim downloads.
2. **Bind-pose retargeting in code**, not in source content. Meshy
   can generate characters in whatever pose (A, T, stoop); the
   merger handles the delta.
3. **Output structure mirrors Godot's expectations**:
   `<character>/<anim>/<dir>_<frame>.png`. Godot loader scans the
   tree at runtime — no per-character `.tres` to author.
4. **Source FBXs and build GLBs in-repo, gitignored.** No
   `~/Desktop/` paths in the pipeline; works on any machine.

## Open production decisions

These gate moving the pilot into the main game project:

- **Item visualization** — Path 3 (no visible gear, Hades/HLD style,
  MVP-friendly) vs Path 2 (weapon-only overlay with per-direction
  hand-bone screen offsets dumped to JSON). Not yet decided.
- **Environment/tile/prop sprite pipeline** — character pipeline
  doesn't cover backgrounds. Probably MJ → flat PNG for tiles, no
  need for 8 directions on a wall.
- **Stylization pass** — renders look like Blender renders, not
  painted bible refs. A Godot shader (cel + posterize) might bridge
  cheaper than re-introducing SDXL.
- **When to merge into the main game project** (`2d-iso-rework` →
  `main` eventually). Pilot currently isolated at
  `tools/pilot/godot_test/`.

## Setup preserved across machines

- Blender 5.1 (Windows: `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`)
- Godot 4.6 (Josh has `C:\Users\josh\Tools\Godot\godot.cmd` shim on PATH)
- Meshy.ai Pro plan ($10/mo — T-Pose + commercial-safe exports)
- Mixamo (adobe.com account)
- ~5 GB disk per 5 characters in tools/pilot/

GPU not load-bearing — pipeline is CPU-bound Blender Eevee. The
earlier SDXL stylization attempt (deleted) needed a GPU.

Related: [[project_xbot_character]], [[project_xbot_ragdoll]] —
3D-era infra still relevant if returning to a hybrid path.
