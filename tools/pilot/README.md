# 2D iso pilot — AI render pipeline test

**Goal:** prove the 3D-model-to-2D-sprite-sheet pipeline end-to-end on a
single asset (X Bot + hammer + walk cycle) before committing to a full
rebuild of the project's visual layer.

The pilot tests two stylization paths:

- **Path A — stylized shader at render time.** Blender Eevee + cel/toon
  shader + painterly post-processing. Deterministic, fast, free.
- **Path B — img2img AI post-pass.** Render flat-shaded → run each frame
  through ComfyUI with Stable Diffusion + ControlNet (depth/lineart) +
  IP-Adapter (painted bible refs as style anchor). Painted look, slower,
  per-frame stylization variance.

If Path A looks "good enough" we ship it. If only Path B reproduces the
painted bible look, we eat the slower iteration.

## Steps

```
0a. tools/pilot/01_render_sprite_sheet.py   →  T-pose 8-direction renders (8 frames)  ✅ shipped
0b. (deferred) animation retargeting        →  walk-cycle frames (64 frames)
0c. (deferred) weapon grip tuning           →  hammer in hand, not on floor
1.  tools/pilot/02_comfyui_workflow.json    →  painted img2img output
2.  tools/pilot/03_test_scene.tscn          →  Godot side-by-side comparison
```

Each step is a separate commit so the work can be evaluated incrementally.

### Why T-pose first (step 0a only)

Mixamo's cross-FBX animation pipeline relies on bone-axis-correction
retargeting. Godot does this via `SkeletonProfileHumanoid` + a BoneMap
resource (see `game/assets/characters/x_bot/README.md`). Blender has no
built-in equivalent — animations from one Mixamo FBX applied to the
rest pose of another Mixamo FBX produce a contorted result (character
renders horizontal instead of upright).

Three paths forward for animation:

1. **Use a Blender addon** — Rokoko Studio Live (free) has Mixamo
   retargeting. ~5-10 min addon install + per-character setup.
2. **Custom Python retargeter** — port the project's BoneMap logic to
   Blender. ~1-2 hours of focused work but matches the runtime exactly.
3. **Download X Bot WITH animation baked in from Mixamo.** Single FBX
   that doesn't need retargeting. Limits us to whatever animations
   we re-download but avoids the problem entirely for the pilot.

Pilot picks #3 for the next iteration unless the user picks otherwise.

T-pose is enough to validate the ComfyUI stylization pipeline. Once
img2img is proven to produce painted output, we layer animation back in.

## Running step 0 (the Blender render)

Run from project root (Windows):

```pwsh
& "C:\Program Files\Blender Foundation\Blender 4.x\blender.exe" -b -P tools/pilot/01_render_sprite_sheet.py
```

Or if Blender is on PATH:

```pwsh
blender -b -P tools/pilot/01_render_sprite_sheet.py
```

Time estimate: ~30 sec on a modern GPU. Outputs 64 PNGs to
`tools/pilot/output/raw/`.

### What the script does

1. Loads `game/assets/characters/x_bot/X Bot.fbx` (the canonical player + enemy mesh)
2. Attaches `game/assets/models/weapons/hammer/hammer.glb` to the right hand bone
3. Loads `game/assets/animations/core/Jog Forward.fbx` and applies its action
4. Sets up an orthographic dimetric camera (30° pitch, 45° yaw)
5. Sets up 3-point complementary-color lighting (warm key, cool fill, teal rim)
6. Renders 8 directions × 8 walk frames = 64 RGBA PNGs with transparent
   background

### Tweak knobs

All in `01_render_sprite_sheet.py` — top of file:

| Constant | Purpose |
|---|---|
| `RESOLUTION` | 256 default. Bump to 512 once pipeline is validated. |
| `FRAMES_PER_DIRECTION` | 8 default. 12-16 for smoother walks. |
| `DIRECTIONS` | The 8-direction sprite-sheet axes. |
| `CAMERA_PITCH_DEG` / `CAMERA_YAW_DEG` | Iso camera angle. 30/45 ≈ D2. |
| `CAMERA_ORTHO_SCALE` | Zoom level. Decrease to zoom in, increase to fit. |

## Outputs (gitignored)

```
tools/pilot/output/
  raw/        Color RGBA renders (Path A baseline + Path B input)
  depth/      Depth maps for ControlNet conditioning (step 1)
  edges/      Canny lineart for ControlNet conditioning (step 1)
  toon/       Path A toon-shader renders (step 1)
  painted/    Path B img2img stylized renders (step 1)
  godot/      Sprite atlases packaged for Godot SpriteFrames import
```

Output is gitignored (`output/.gitignore`). Sprite frames don't belong in
git — they're regenerable from the .glb + animation + script.

## Decision criteria

After running the pilot, we judge against this checklist:

- [ ] Character silhouette is readable at the chosen iso angle
- [ ] 8 directions are visually distinct (animator can tell which way the
      character is facing)
- [ ] Walk cycle reads as walking (not awkward, no foot-skate, frames flow)
- [ ] Weapon attaches cleanly to right hand across all directions/frames
- [ ] Output is "painted enough" — sits next to the bible refs without
      looking out of place (Path A vs Path B)
- [ ] Iteration time per change is acceptable (<5 min from "change the
      shader" to "see new output")

If Path A passes the painted-enough test, we ship it. If only Path B
passes, we commit to the slower pipeline.
