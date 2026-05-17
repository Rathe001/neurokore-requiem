---
name: level-debug-viz
description: LevelBuilder.USE_DEBUG_LEVEL_VIZ toggles a debug visualization mode that replaces kit-bash models with procedural geometry + emissive border shader
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`game/scripts/level/level_builder.gd` has a `const USE_DEBUG_LEVEL_VIZ: bool`
toggle near the top. When `true`:

- `theme.wall_model` and `theme.floor_model` (kit-bash .glb refs) are
  ignored — procedural SurfaceTool/PlaneMesh path runs instead
- `theme.wall_material` / `floor_material` (and the `_alt` variants) drive
  the procedural materials. Themes have these pointing to debug shaders
  under `resources/level/debug/`:
    - `wall_debug.tres` (cyan border)
    - `wall_alt_debug.tres` (green border, used by corridor walls)
    - `floor_debug.tres` (orange border)
    - `floor_alt_debug.tres` (yellow border)
- `theme.wall_thickness` is overridden at build time to
  `DEBUG_WALL_THICKNESS = 1.0` so the trapezoidal wall geometry reads
  clearly at iso scale (production thickness 0.4 makes the wall top
  invisible at iso)
- Strict-grid quantization is skipped so rooms keep their authored sizes
- The debug shader (`debug_block.gdshader`) renders with
  `render_mode unshaded, cull_disabled` so all wall faces are visible
  regardless of camera direction — important because room walls only have
  3 face types (outer, inner, top) and backface culling normally hides one
  of them per camera angle, making rooms look "planar"

**Why:** The kit-bash level system is hard to visually verify alignment
on (panels mask corner overlaps, textured surfaces obscure seams). Debug
viz turns every wall into a labelled wireframe-ish solid so misalignments
are obvious. Used in May 2026 to verify the mitred-corner + corridor-jamb
alignment work.

**How to apply:** Set `USE_DEBUG_LEVEL_VIZ = true`, reload Godot, run the
game. To return to production, set back to `false` and reload. Both states
work with the same theme files — no .tres edits needed to toggle.

Related: [[mitred-wall-geometry]] for the procedural wall geometry that
debug viz exposes.
