---
name: procedural-surface-shader
description: Canonical wall/floor surface shader — single procedural_wall.gdshader, two ShaderMaterial instances (wall + floor) driving it with different uniforms
metadata:
  type: project
---

The walls and floors in this game render via a shared **procedural shader** rather than imported kit-bash panels. Lives at `res://scripts/level/build/procedural_wall.gdshader`. One shader handles both orientations — it detects in fragment whether the surface is a wall (normal along ±X or ±Z) or a floor (normal along ±Y) and maps `wall_uv` accordingly.

**Two `ShaderMaterial` instances** in `build_context.gd`:
- `_default_wall_material()` — 1m panels, modest bevels, small rivets, very reflective (metallic 0.75, roughness 0.32)
- `_default_floor_material()` — 2m panels, larger bevels + rivets, slightly less reflective, splotches enabled (~55% coverage)

Both wrap the same shader. They're returned from `_resolve_materials` when `theme.wall_material` / `theme.floor_material` are null — which all the kit-bash themes do, so this is the active path for tech/dim/amber themes.

**Visual stack the shader composes (all per-fragment, no extra geometry):**
1. World-aligned panel grid (seams at panel edges)
2. Raised bevel border lip just inside the seam (catches its own specular)
3. Rivet domes at 4 inset corners per panel
4. Per-panel albedo jitter (slab-to-slab variation via hash)
5. Surface wear noise (medium scale dirt/oxidation)
6. Sub-cm scratch noise on the normal (breaks specular)
7. Pixel-scale micro-albedo noise (masks debanding dither)
8. Meter-scale splotches (floors only — grime patches that darken albedo, drop metallic, raise roughness)

All visual tuning via uniforms — no need to recompile to iterate. ~14 uniforms per material.

**Why:** [[itemization-revamp]] was set up for a kit-bash pipeline (`wall_panel_v5/v6.glb`), but the assets fought back — kit panels were authored as floor tiles, didn't tile well as walls, had a long string of shader/serialization gotchas ([[godot4-shader-gotchas]]). Procedural shader gave us full control + zero asset pipeline issues.

**SSR is on** in `level_shell.tscn` (`ssr_enabled = true`) — required for the reflective metal to actually reflect ceiling lights and surrounding geometry. ~0.5ms/frame at `ssr_max_steps=64`.

**How to apply:** Themes leave `wall_model` / `floor_model` null. `level_builder.use_kit_walls` / `use_kit_floors` evaluate false → procedural path (`build_room_mesh` + `build_piece_floor`). Each gets `material_override = ctx.wall_material` / `ctx.floor_material` which resolves to the procedural ShaderMaterial. The kit-panel infrastructure (`kit_panel.gdshader`, `kit_panel_post_import.gd`) is still intact for future wall-authored kit assets but currently unused.
