---
name: Tech-shader specular shimmer
description: Procedural normal maps in tech_wall/tech_floor shaders + iso camera + camera motion = specular aliasing; tune metallic/roughness/bump, not the shader logic
type: project
---

The four procedural surface shaders (`tech_wall.gdshader`, `tech_wall_riveted.gdshader`, `tech_floor.gdshader`, `tech_floor_grate.gdshader`) generate normals from `dFdx`/`dFdy` on a sharp height field (seams + rivets). When the camera moves sub-pixel amounts, those derivatives shift slightly per-pixel each frame → specular highlights flicker → "shimmer" or "boiling" effect.

**Trigger conditions:** any camera motion (cursor lookahead, shake, walking) + glancing angle (iso view at the floor especially) + high `metallic_val` + low `roughness_base` + high `bump_strength`. Walking past a riveted floor was the worst case.

**Fix applied this session (in commit `Fix specular shimmer`):**
- `metallic_val` cut roughly in half (e.g. tech_floor_grate 0.55→0.22)
- `roughness_base` raised into the 0.72-0.80 range
- `bump_strength` halved
- `screen_space_aa` (FXAA) disabled in `project.godot` — was layered on top of TAA and amplifying noise
- SSAO tuned down (`intensity` 1.8→1.0, `sharpness` 0.98→0.85) in `prototype_3d.tscn` environment

**Visual tradeoff:** surfaces read as less polished/metallic, more matte concrete. Stable but less "wet shiny tech." Accept this until we have a proper specular-AA technique (geometric SpecAA: bump roughness up where normal gradient is large).

**Why:** The user noticed shimmer specifically on walls + riveted floors. Investigation confirmed it was the shader's procedural normal map producing specular aliasing under camera motion, not a procedural texture (the user's first guess).

**How to apply:** If a new procedural surface shader is added, keep `metallic_val ≤ 0.25`, `roughness_base ≥ 0.7`, `bump_strength ≤ 0.7` by default. Specular response is the amplification factor for shimmer; minimize it on default values.
