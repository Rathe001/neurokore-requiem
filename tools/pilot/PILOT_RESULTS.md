# 2D iso pilot — results

**Date:** 2026-05-27
**Branch:** `2d-iso-pilot` (off `2d-iso-rework`, off `main`)
**Status:** Wrapped. Conclusive findings below.

## TL;DR

**The 3D-to-2D-sprite pipeline works for rendering, lighting, pose preservation,
and stylization** but hits a hard limit on character identity locking using
pure IP-Adapter. Pure-parameter approaches cannot solve identity consistency
across an 8-direction sprite sheet. Producing usable sprite sheets requires
adding LoRA training to the pipeline — that's a ~half-day-per-character
investment before any sprite work starts.

Three concrete next-step paths laid out in the [Decision](#decision) section.

## What was tested

The pilot processed one asset (X Bot mesh + hammer weapon, T-pose) end-to-end:

```
Blender (renders 8 iso directions, RGBA, transparent bg, 256x256)
    ↓
ComfyUI (SDXL + IP-Adapter + ControlNet canny, upscales to 1024)
    ↓
Python (re-applies raw alpha channel to strip painted backgrounds)
    ↓
Painted RGBA sprite sheets, 1024x1024, ready for Godot import
```

Iteration log:

| Iteration | What we tested | Result |
|---|---|---|
| 1 | Blender FBX import + Mixamo anim retargeting | ❌ Anim retargeting broke without Rokoko/Auto Rig Pro; pivoted to T-pose only |
| 2 | Render pipeline at iso angle | ✅ 8-direction T-pose RGBA renders in ~30 sec total |
| 3 | SDXL img2img minimal (no ControlNet/IPAdapter) at 256² | ❌ Chromatic noise — SDXL needs 1024² inputs |
| 4 | + 1024² upscale before VAE encode | ✅ Output renders; denoise 0.4 too low (no style shift) |
| 5 | Denoise 0.65 minimal | ✅ Painted aesthetic emerged but pose drifted (no silhouette lock) |
| 6 | Full pipeline (IPAdapter + ControlNet on bible-soldier ref) | ✅ Painted style + pose locked; backgrounds painted |
| 7 | Alpha restoration post-pass | ✅ Painted character on transparent bg |
| 8 | 8-direction batch on bible-soldier anchor | ❌ Character identity drifts across frames (3 distinct characters) |
| 9 | Tuned weights (prompt-dominant, lower IPAdapter, tighter ControlNet) | ❌ Same identity drift |
| 10 | Canonical character anchor (user-provided armored soldier ref) | ❌ Output kept X Bot silhouette with paint job, ignored canonical's armor |
| 11 | Looser ControlNet (0.5) + max IPAdapter (1.0) | ❌ Better palette match but identity still drifts; canonical's specific features (spikes, bandolier, knee orbs) not transferred |

## What worked ✅

| Capability | Status | Evidence |
|---|---|---|
| Blender headless render | ✅ Works | `01_render_sprite_sheet.py` — 8 dirs / ~30 sec |
| Iso camera framing | ✅ Works | 30° pitch / 45° yaw, ortho 2.5, character fills frame |
| 3-point lighting | ✅ Works | Warm key / cool fill / teal rim reads painterly |
| Transparent BG render | ✅ Works | `film_transparent = True` gives clean alpha |
| ComfyUI HTTP API | ✅ Works | `02_stylize.py` submits + polls + downloads cleanly |
| SDXL img2img stylization | ✅ Works | Painted aesthetic reachable @ denoise 0.65 |
| ControlNet pose lock | ✅ Works | T-pose preserved across all frames |
| IP-Adapter style transfer | ✅ Works | Painted palette + atmospheric tone transfer |
| Alpha restoration | ✅ Works | `03_restore_alpha.py` strips painted bg via raw alpha mask |
| 8-direction batch | ✅ Works | ~60 sec/frame, ~8 min total on RTX 4070 Laptop |

## What didn't work ❌

| Goal | Status | Evidence |
|---|---|---|
| Mixamo anim retargeting in Blender | ❌ Needs addon (Rokoko/Auto Rig Pro) | Cross-FBX retargeting produces contorted poses |
| Character identity consistency across 8 facings | ❌ Cannot solve via IP-Adapter parameters | Confirmed across 2 anchors × multiple param combos |
| Specific feature transfer from canonical (armor design, distinct gear) | ❌ IP-Adapter is style-only, not identity | Canonical's spikes / bandolier / orbs not reproduced |
| Weapon grip on character hand bone | ❌ Bone parented but local offset on floor | Defer to F9+T tuner port |

## Key learnings (worth keeping)

1. **SDXL inputs must be ≥ 1024².** Smaller inputs produce chromatic noise. Always upscale before VAE encode.
2. **Alpha restoration is essential** for sprite use. SDXL VAE strips alpha; re-apply raw render's alpha as a mask post-decode.
3. **ControlNet at 0.7-0.8 locks pose** without crushing creativity. Below 0.5, pose drifts. Above 0.85, the source mannequin's silhouette dominates over any style ref.
4. **IP-Adapter "weight_type" matters more than weight.** "style transfer" pulls atmospheric vibe; "prompt is more important" pulls less; identity-specific features rarely transfer regardless.
5. **`COMFYUI_URL` differs by install.** Desktop = port 8000, source repo = port 8188. Make it env-var configurable.
6. **Setup cost is real:** SDXL Base 1.0 + ControlNet SDXL + IP-Adapter Plus SDXL + CLIP-ViT-H-14 + IPAdapter custom node = ~13 GB download and ~30 min of one-time install.

## Decision

Three production paths, with honest cost estimates:

### Path A — invest in LoRA training, ship 2D iso

For every distinct character (player class, enemy archetype, NPC):

1. Generate or hand-paint **20-25 training images** (different angles, poses, lighting). The pilot can produce these candidates at scale; pick the best 20.
2. Train a **character-specific LoRA** (~2 hours on the RTX 4070 Laptop using `kohya_ss` or ComfyUI's training nodes).
3. Add the LoRA to the workflow's KSampler model input.
4. Re-batch → tightly identity-locked sprite sheets.

**Cost:** ~half day per character. The project has ~10 character archetypes total (8 classes + named enemies). That's ~5 days of identity-locking setup work BEFORE any sprite generation work starts.

**Benefit:** True production-quality 2D iso ARPG sprites. Full painted-bible aesthetic. The original creative vision.

### Path B — return to 3D on `main`

The 3D project on `main` already worked. Character identity is automatic (same mesh renders every frame). The bible-painted look isn't reachable directly, but a **stylized toon shader** + **post-process painterly compositor** can approximate it. The shipped 3D project already had a Steam playtest live.

**Cost:** Zero new setup. Just `git checkout main` and resume.

**Tradeoff:** 1996 D2 painted-brush look is approximate rather than literal. Body-horror cyberpunk tone preserved.

### Path C — hybrid: 2D for static assets, 3D for characters

Use 2D iso art **only** for assets where identity doesn't drift between frames:

- ✅ **UI / HUD** — single static designs (covered by the bible's UI section)
- ✅ **Inventory icons** — single static designs (covered by the bible's icon section)
- ✅ **Environment art** — paintings as backdrop / loading screens
- ✅ **Portraits** — single static designs per character/NPC
- ❌ **In-game characters** — keep these in 3D

**Cost:** Modest. Use the pilot pipeline for static asset categories only. Skip the LoRA work entirely.

**Tradeoff:** Best of both — D2-style painted UI/icons/portraits with 3D characters underneath.

## Files in this directory

```
tools/pilot/
├── 01_render_sprite_sheet.py   Blender render script (T-pose 8 directions)
├── 02_stylize.py               ComfyUI img2img stylization via HTTP API
├── 03_restore_alpha.py         Re-apply alpha channel post-stylization
├── canonical_character.png     Canonical anchor (replace with new char to switch)
├── README.md                   Pipeline overview + setup instructions
├── PILOT_RESULTS.md            This file
└── output/                     Gitignored render outputs
    ├── raw/                    Blender renders
    └── painted/                ComfyUI outputs (alpha-restored)
```

## What's preserved if we revisit

- All three scripts are functional and committed.
- `canonical_character.png` is a real asset that can be swapped per character.
- The README documents every model download URL, install path, and tuning knob.
- Git history captures every iteration — easy to inspect what was tried.

## What's NOT here (intentionally)

- Animation pipeline (Mixamo retarget unsolved — needs Rokoko addon or custom Python retargeter, both are real engineering jobs)
- Weapon grip tuning (script attaches to hand bone but local offset lands on floor)
- LoRA training rig
- Multi-character pipeline (`canonical_character.png` is single-file; production needs per-character refs)
- Godot import / SpriteFrames generation (step 2 of the original pilot plan, deferred until step 1 produces sprite-sheet-quality output)

## Honest assessment

The pilot answered its question. **2D iso sprite production is feasible via AI**, but the per-character identity-locking step requires LoRA training that wasn't in the original pilot scope. The "drop a 3D model in, get painted sprites out" workflow doesn't exist without it.

The 3D project on `main` ships today. The 2D iso path is reachable but is a multi-week effort, not a multi-day one. That's the deliberate decision to make outside the iteration loop.
