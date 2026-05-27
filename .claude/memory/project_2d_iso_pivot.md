---
name: project_2d_iso_pivot
description: Project pivot 2026-05-26 to 2D iso sprite ARPG. Pilot wrapped 2026-05-27 — rendering pipeline works, character identity locking requires LoRA per character. Three production paths in tools/pilot/PILOT_RESULTS.md.
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
scope, iterate, and automate via the AI render pipeline.

## Visual bible (shipped 2026-05-26)

48 painted-style MJ references at `docs/art-reference/` across env /
chars / monsters / UI / icons / VFX. Every asset class has a locked
`--sref` anchor. Reference document for both hand-painting and AI
img2img stylization. The bible is complete and reusable regardless of
which production path the project takes.

## Pilot (wrapped 2026-05-27 — see tools/pilot/PILOT_RESULTS.md)

Tested Path B (3D-to-2D AI render pipeline): Blender renders the X Bot
mesh at iso angle → ComfyUI img2img with SDXL + IP-Adapter + ControlNet
→ Python alpha-restoration → painted sprite output.

**What works:**
- Pipeline runs end-to-end: ~8 min for 8 directions on RTX 4070 Laptop
- Painted aesthetic reachable
- Pose locked by ControlNet
- Transparent backgrounds via alpha mask
- All scripts committed and reusable

**What doesn't (the blocker):**
- Character identity drifts across the 8 facings — pure IP-Adapter is a
  style encoder, not an identity encoder. Confirmed across 2 canonical
  references × multiple parameter combos. Cannot be solved by tuning.

**Production paths forward:**
1. **Add LoRA training** (~half day per character × ~10 characters =
   ~5 days setup before sprite production starts). True 2D iso ARPG.
2. **Return to 3D on `main`** (project shipped Steam playtest in 3D
   already). Stylized shader approximates painted look.
3. **Hybrid: 2D for UI/icons/portraits, 3D for in-game characters**.
   Best of both, low marginal cost — uses pilot pipeline only for
   identity-stable static assets.

**Decision deferred to a non-fatigued session.**

## Setup that was done (preserved across machines)

Josh has:
- Blender 5.1 installed
- ComfyUI Desktop installed at `~/Documents/ComfyUI` (port 8000)
- SDXL Base 1.0 in `models/checkpoints/`
- `controlnet-canny-sdxl-1.0.safetensors` in `models/controlnet/`
- `ip-adapter-plus_sdxl_vit-h.safetensors` in `models/ipadapter/`
- `CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` in `models/clip_vision/`
- `ComfyUI_IPAdapter_plus` custom node installed
- GPU: RTX 4070 Laptop GPU (12GB+ VRAM)

**Slowness clarification:** Path B is all build-time, zero runtime cost.
Once sprite sheets are baked they're static PNG textures in Godot.
Runtime perf identical to any 2D ARPG.

Related: [[project_xbot_character]], [[project_xbot_ragdoll]],
[[project_weapon_attachment]] — all 3D-era infra that feeds the
2D sprite production pipeline (if path 1 or 3 is chosen).
