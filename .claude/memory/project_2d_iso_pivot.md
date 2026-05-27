---
name: project_2d_iso_pivot
description: Project pivot 2026-05-26 — moving from 3D iso to 2D iso sprite ARPG. Bible at docs/art-reference/, pilot at tools/pilot/, branches 2d-iso-rework + 2d-iso-pilot.
metadata:
  type: project
---

On 2026-05-26 the project pivoted from fixed-camera 3D to 2D iso sprite
ARPG. The 1990s D2/Sanitarium/Crusader: No Remorse painted look is the
target. 3D work is preserved on `main`; the rework lives on
`2d-iso-rework` (visual bible) and `2d-iso-pilot` (production pipeline).

**Why:** Josh's original game-design vision was 1990s painted ARPG, but
he'd assumed 3D would be easier for AI workflows. The reverse is true —
2D iso sprite production is dramatically easier to scope, iterate, and
automate via the AI render pipeline.

**Visual bible** at `docs/art-reference/` (48 painted-style MJ
references across env / chars / monsters / UI / icons / VFX). Every
asset class has a locked `--sref` anchor. Reference document for both
hand-painting and AI img2img stylization.

**Production pipeline (Path B chosen):**
```
3D model -> Mixamo anim -> Blender render orbit -> ComfyUI img2img -> Godot SpriteFrames
```
3D models, rig, anim library, weapon glbs, X Bot mesh are all REUSED
from the 3D-era project — that work isn't wasted, it just feeds a
different output pipeline.

**Pilot** at `tools/pilot/` (branch `2d-iso-pilot`). One enemy
(X Bot + hammer + walk anim) all the way through both stylization
paths to validate before full commit:
- Path A: stylized shader at Blender render time (fast, deterministic)
- Path B: img2img post-pass via ComfyUI with SDXL + ControlNet + IP-Adapter

Step 0 of pilot shipped: `01_render_sprite_sheet.py` renders 64 frames
(8 dirs × 8 frames) at 256² RGBA transparent in ~30 sec.

**Pending pilot steps:**
- Step 1: ComfyUI workflow JSON for img2img stylization
- Step 2: Godot test scene to display Path A vs Path B side-by-side

**Setup confirmed (2026-05-26):** Josh has Blender 4.x + local
ComfyUI with 12GB+ VRAM GPU.

**Slowness clarification (Path B):** all build-time, zero runtime cost.
Once sprite sheets are baked they're static PNG textures in Godot.
Runtime perf identical to any 2D ARPG.

Related: [[project_xbot_character]], [[project_xbot_ragdoll]],
[[project_weapon_attachment]] — all 3D-era infra that feeds the
2D sprite production pipeline.
