---
name: kit-model-axis-conventions
description: "Blenderkit model imports vary in which local axis is \"height\" — kit wall builder has to be rotated per-model to compensate"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

Different Blenderkit `.glb` exports use different local-axis conventions
for "which axis is vertical." The kit wall builder's rotation chain
(`WallBuilder._add_tiled_wall_segment`) has to match:

- `Basis(Vector3.UP, y_rot) * Basis(Vector3.RIGHT, -PI * 0.5)` — for kits
  whose tall axis is local Z (Blender Z-up exports). Maps local Z→world Y,
  local X→world X (width), local Y→world -Z (thickness).
- `Basis(Vector3.UP, y_rot)` only — for kits whose tall axis is local Y
  (Godot Y-up convention). Local X→world X, Y→Y, Z→Z. Also need to swap
  the scale vector to `(step/w, wall_h/h, thick/t)`.

There's no metadata in the `.glb` that tells you which convention. Either
inspect the model in Blender / Godot scene tree, or just try both.

**Also watch for:** asset_base_ids that label assets misleadingly. e.g.
`515dacf4-...` is named "PX Concrete Wall" in Blenderkit metadata but
can work as a floor (used as `floor_panel_v2`). Don't trust user-stated
type categorization; check the actual metadata when importing.

**Designed-for-tiling check:** Before adopting a kit panel, verify it's
authored as a TILEABLE element, not a single-use scene-set. The "Square
Wall Tiles" asset (`906570d6...`/wall_panel_v3) turned out to include a
built-in doorway in the same mesh — when tiled across a corridor wall,
each tile dragged its doorway frame along, producing weird chevron seams
at mid-height. Single-mesh `.glb`s with multiple primitives + named like
"scene-set" objects are red flags.

Related: [[blenderkit-import]] for the conversion pipeline,
[[kit-panel-scaling]] for the AABB rendering math.
