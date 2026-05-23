---
name: godot4-shader-gotchas
description: "Five Godot 4 shader/material gotchas that all manifested as \"garbled output, no error\" and burned hours"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

Five things Godot 4 fails on silently — each looks like "shader broken, falls back to default white" with no obvious error. All hit during the procedural-wall + kit-panel work. Future shader work should remember these.

**1. `set_shader_parameter` with `Vector3` on a `source_color`-hinted `vec3` uniform drops to `null` on `.scn` serialization.** Pass `Color` instead. Verified empirically: `inspect_kit_mesh.gd` showed `albedo_color=<null>` after Vector3 was set, then `albedo_color=(0.45, 0.45, 0.45, 1.0)` after switching to Color.

**Why:** Godot serializes `source_color` parameters expecting a Color type. Vector3 isn't a valid serialized form for that slot.

**How to apply:** any uniform declared as `vec3 X : source_color` — always set with `Color(r, g, b)`, never `Vector3(r, g, b)`. Plain `vec3` (no source_color) probably round-trips Vector3 fine, but use Color anyway for consistency.

**2. `hint_default_white` is mutually exclusive with `hint_normal` and `hint_roughness_gray`.** They're the same hint category in Godot 4 — combining produces `SHADER ERROR: Redefinition of hint`. `source_color, hint_default_white` works; `hint_normal, hint_default_*` does not.

**How to apply:** Bind fallback textures explicitly from code instead of relying on `hint_default_*` for normal/roughness samplers.

**3. `Image.create()` returns an uninitialized buffer.** `set_pixel()` only writes the pixel you specify; the rest of the buffer is GPU/RAM bytes from the previous allocation = effectively random noise. Sampling that texture as a normal map gives bogus normals, which manifest as a blob shading pattern.

**How to apply:** Always `img.fill(color)` after `Image.create()`. Never trust that the buffer is initialized.

**4. Sampling a *white* texture as a normal map decodes to an extreme bogus normal.** RGB(1,1,1) → normal (1, 1, undefined). A "flat normal" is RGB(0.5, 0.5, 1.0). For textureless assets that fall through to a default texture, the default for `normal_tex` must be flat-normal, NOT white.

**How to apply:** Maintain two static fallback textures — `_fallback_white()` for albedo/roughness, `_fallback_flat_normal()` for normal_tex. See `kit_panel_post_import.gd`.

**5. GLSL won't let you redeclare a variable in the same scope.** Doing so silently compiles the shader to a default white fallback — no error message in headless Godot, the shader just doesn't render anything. The procedural wall shader hit this when a refactor added `vec2 cell_uv = ...` in fragment without realizing `cell_uv` was already declared earlier in the same function.

**How to apply:** When extending an existing shader fragment, scan for variable names you're about to declare; reuse the existing one instead. If walls/floors render as flat pale grey with no panel features visible at all, suspect a redeclaration.

Common thread: Godot 4's shader pipeline fails silently. Trust nothing; verify by inspecting the bound parameters via a runtime probe (`tools/inspect_kit_mesh.gd` is the pattern — load the imported .scn and walk the surfaces printing what's actually bound on the ShaderMaterial).

**6. `depth_draw_disabled` is not a valid render_mode keyword.** The valid set is `depth_draw_opaque` / `depth_draw_always` / `depth_draw_never` / `depth_prepass_alpha`. Using `depth_draw_disabled` makes the whole shader silently fail to compile → engine falls back to the default white spatial material. Symptom seen on the blade-slash distortion rewrite: solid white quads instead of the expected refraction effect.

**7. Canvas_item fragment shaders disallow `return`.** `if (cond) { COLOR = vec4(0.0); return; }` produces "Using 'return' in the 'fragment' processor function is incorrect" and the shader silently falls back. Restructure as `if (cond) { ... } else { ... }` so all paths land at the same closing brace. Bit me on the neon-outline rewrite.

**8. `TAU` is a reserved builtin in canvas_item shaders.** Redeclaring it as `const float TAU = ...` produces a Redefinition error and the shader silently fails. Inline the literal (`6.28318530718`) or use a different name. Bit me on the neon-outline rewrite alongside the `return` issue.

**9. Reverse-Z depth math.** Godot 4 perspective uses `[0, 1]` NDC z (reverse-Z: 1 = near, 0 = far). The old GL convention `[-1, 1]` (and the `depth * 2.0 - 1.0` remap to reach it) gives wrong values under perspective and silently collapses depth-based screen-space effects (soft particles, depth-clip outlines). Pass `depth_texture.x` and `FRAGCOORD.z` straight through `INV_PROJECTION_MATRIX` without remapping. Fixed: explosion flipbook (was invisible under perspective) and tactical-overlay LoS clip (works now, finally).
