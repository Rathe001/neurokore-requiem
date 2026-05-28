---
name: project_2d_iso_pivot
description: Project pivot 2026-05-26 to 2D iso sprite ARPG. SDXL stylization abandoned 2026-05-27; Meshy→Mixamo→Blender pipeline shipped 2026-05-28 with identity-locked 736-sprite output per character.
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
`--sref` anchor.

## Production pipeline (shipped 2026-05-28)

End-to-end sprite generation pipeline. All scripts in `tools/pilot/`:

```
Midjourney (character ref)
    ↓
Meshy.ai image-to-3D (mesh + textures + Mixamo rig)
    ↓
Mixamo (base FBX with skin + N anim-only FBXs)
    ↓
merge_mixamo_anims.py (one .glb with all actions as NLA strips)
    ↓
01_render_sprite_sheet.py (Blender headless render — 8 dirs × N anims × M frames)
    ↓
build_viewer.py → output/viewer.html for interactive review
    ↓
Godot SpriteFrames import (not yet wired)
```

**Validated on Crimson Vein Titan** (ranged spellcaster enemy):
- 5 anims (idle/walk/cast/hit/death) × 8 directions × 12-24 frames
  = 736 sprites in 83 sec render, ~26 MB at 256² PNG
- Identity locked across every frame (mesh, no AI stylization)
- Per-frame camera Z tracking centers crouched + dying poses
- Dynamic ortho_scale auto-fits the worst-case pose

**Why SDXL/IP-Adapter was abandoned:** earlier iteration tried
img2img stylization (Blender render → ComfyUI). Worked end-to-end but
character identity drifted across the 8 facings — IP-Adapter is a
style encoder, not an identity encoder. Direct .glb rendering with
baked textures solves identity locking mathematically. ComfyUI stack
deleted; relevant scripts removed from the pipeline.

## Why Mixamo over Meshy's built-in anims

Meshy's auto-baked animations for body-horror characters are
off-label — "Walking" is a wide-legged creature crouch-stalk,
"Running" is a hunched crouch, "Dead" doesn't actually fall to the
ground. Mixamo's anim library uses correct naming + clean motion
(Walking is an upright walk, Dying lands the character flat). For
production, every character goes through Meshy → Mixamo (one-time
per-character upload + manual joint markers + download anims) →
merge_mixamo_anims.py.

## Open production decisions

- Item visualization: Path 3 (no visible gear, MVP-friendly) vs
  Path 2 (weapon-only overlay) — not yet decided. Path 3 unblocks
  player-character pipeline; Path 2 adds weapon sprite layer at
  render time with per-direction hand-bone offsets dumped to JSON.
- Godot SpriteFrames import: not yet wired. Each char's output
  directory layout (`raw/<character>/<anim>/<dir>_<frame>.png`)
  is already SpriteFrames-friendly.

## Setup preserved across machines

Josh has:
- Blender 5.1 installed (path: `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`)
- Meshy.ai Pro plan (commercial-safe exports, T-Pose option for Mixamo)
- Mixamo (adobe.com/cc account)
- GPU: RTX 4070 Laptop (12 GB+ VRAM, not actually needed for
  Blender Eevee renders — pipeline runs CPU-bound)

ComfyUI / SDXL stack from the earlier attempt was deleted.

Related: [[project_xbot_character]], [[project_xbot_ragdoll]] —
3D-era infra still relevant if returning to Path 2 (3D characters
with 2D UI).
