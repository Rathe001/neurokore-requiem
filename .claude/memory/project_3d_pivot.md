---
name: Pivot from 2D pixel art to low-poly 3D
description: The game's visual direction changed from isometric pixel art to fixed-camera low-poly 3D with PBR materials, high-res textures, and realistic lighting. Use Godot's Forward+ renderer.
type: project
originSessionId: 22dbe090-8006-4f89-8d5b-a0309affea09
---
Decision made 2026-04-19. The game is no longer isometric pixel art — it is now **fixed-camera low-poly 3D**. The camera angle stays locked (same feel as the previous 2D iso view) but the world is authored in 3D.

**Aesthetic:** low-poly meshes (clean silhouettes read well at the locked camera angle) + high-resolution PBR textures + realistic dynamic lighting. Reference mood: Cloudpunk, Ghostrunner's cleaner moments, The Ascent (denser but same lane). Not AAA fidelity — stylized low-poly carries the identity.

**Why:** the prior 2D pixel-art direction felt too "old-school D2 clone" or too "survivor.io". Higher-fidelity 3D with a locked camera lands in a more differentiated space (Last Epoch / PoE2 / Diablo 4 territory, but stylized rather than photo-real).

**How to apply:**
- Renderer: Godot 4 Forward+ on PC (PBR, SDFGI, volumetrics all in play). Mobile target will need a lighter renderer path (baked lighting, fewer dynamic lights, no volumetrics) — treat mobile as "same game, lower fidelity," not a different art pass.
- Horde-density pillar + many dynamic lights is the danger combo. Be disciplined about light culling from the start.
- Code port: most gameplay systems (Skill, ResourcePool, cooldowns, HUD, morality, rep) are dimension-neutral — they port cheaply. CharacterBody2D/Vector2/Sprite2D/Camera2D/Polygon2D etc. are the 2D-specific pieces that need replacing.
- Asset pipeline: Blender for custom modeling/animation is the long-term tool. Curated asset packs may bridge the early prototype phase.
- Build a **minimal 3D prototype scene** (ground + camera + placeholder character + lighting) to validate the look **before** porting any gameplay code. Systems port last.
