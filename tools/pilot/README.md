# 2D iso pilot — AI render pipeline test

> **STATUS: Wrapped 2026-05-27.** Conclusive findings in
> [`PILOT_RESULTS.md`](./PILOT_RESULTS.md). Read that first if you're
> deciding whether to resume this work — the pilot proved the rendering
> pipeline works, identified character identity locking as the
> production blocker, and lays out three concrete paths forward.

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
1.  tools/pilot/02_stylize.py               →  painted img2img output via ComfyUI API
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

## Running step 1 (ComfyUI img2img stylization)

Run from project root:

```pwsh
python tools/pilot/02_stylize.py
```

The script defaults to `SMOKE_TEST = True` — it processes one image
(`S_00.png`) so you can iterate quickly on prompts / strengths / model
choices before committing to a full 8-image batch.

### What it needs running

ComfyUI listening on `http://127.0.0.1:8188` (start with
`python main.py` from the ComfyUI dir, or use the
`run_nvidia_gpu.bat` shortcut on Windows).

### Models the script expects (edit names at top of file if yours differ)

| ComfyUI folder | File | Source |
|---|---|---|
| `models/checkpoints/` | `sd_xl_base_1.0.safetensors` | [stabilityai/stable-diffusion-xl-base-1.0](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0) |
| `models/controlnet/` | `controlnet-lora-sdxl-canny.safetensors` | [stabilityai/control-lora](https://huggingface.co/stabilityai/control-lora) |
| `models/ipadapter/` | `ip-adapter-plus_sdxl_vit-h.safetensors` | [h94/IP-Adapter](https://huggingface.co/h94/IP-Adapter) |
| `models/clip_vision/` | `CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` | [laion/CLIP-ViT-H-14-...](https://huggingface.co/laion/CLIP-ViT-H-14-laion2B-s32B-b79K) |

### Custom nodes the script expects

- **ComfyUI_IPAdapter_plus** — `git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus` into `ComfyUI/custom_nodes/`, or install via [ComfyUI Manager](https://github.com/ltdrdata/ComfyUI-Manager)

### What the script does (in order)

1. Verifies ComfyUI is reachable and prints what models / custom nodes are installed
2. Cross-checks the configured `CKPT_NAME` and `CONTROLNET_NAME` against installed models, warns if missing
3. Uploads the painted style anchor (`374b6a95...` soldier ref) to ComfyUI's input folder
4. Uploads the raw render to ComfyUI's input folder
5. Submits a workflow: SDXL → VAE encode → IP-Adapter (style anchor) → ControlNet (canny) → KSampler (denoise 0.6) → VAE decode → save
6. Polls until ComfyUI reports completion (~30-90s on a 12GB GPU)
7. Downloads the painted output to `tools/pilot/output/painted/S_00.png`

### Tuning knobs (top of `02_stylize.py`)

| Constant | Default | What it does |
|---|---|---|
| `DENOISE_STRENGTH` | 0.6 | How much the model can change input. Lower = more raw, higher = more painted. |
| `CONTROLNET_STRENGTH` | 0.75 | Silhouette preservation. Higher = tighter to the 3D render. |
| `IPADAPTER_WEIGHT` | 0.8 | How heavily the painted style ref biases output. |
| `POSITIVE_PROMPT` | (long) | Style description. Tweak to push toward different aesthetics. |
| `NEGATIVE_PROMPT` | (long) | Failure modes. Adds words to push away from. |
| `SEED` | 42 | Reproducibility. Change to randomize. |
| `SMOKE_TEST` | True | Set False to batch all 8 directions after smoke test passes. |

### Expected smoke-test output

After running, inspect `tools/pilot/output/painted/S_00.png`. Compare
against `tools/pilot/output/raw/S_00.png`:

- Painted version should look hand-painted, not 3D-rendered
- Character pose + silhouette should be recognizably the same
- Color palette should lean toward the painted bible (orange + teal)
- Lighting should feel baked rather than real-time

If the result drifts heavily from the input pose, raise
`CONTROLNET_STRENGTH`. If it doesn't look painted enough, raise
`DENOISE_STRENGTH` and/or `IPADAPTER_WEIGHT`. If it ignores the
character entirely and paints random scenes, lower `DENOISE_STRENGTH`.

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
