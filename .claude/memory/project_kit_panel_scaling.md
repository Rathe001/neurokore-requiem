---
name: kit-panel-scaling
description: "Kit panel scaling uses raw mesh AABB (for MMI scaling) + baked visual AABB (for tile-spacing decisions) — they're different when the .glb has a root scale"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`WallBuilder._get_kit_mesh` caches TWO AABBs on `BuildContext` per kit:

- `wall_kit_aabb` / `floor_kit_aabb` — RAW vertex bounds from
  `mesh.get_aabb()`. This is what `MultiMeshInstance3D` actually sees when
  rendering (MMI ignores the `.glb`'s node-chain transforms; only the
  per-instance Transform3D is applied to the raw mesh).
- `wall_kit_aabb_visual` / `floor_kit_aabb_visual` — BAKED visual bounds,
  computed as `node_xform * mesh.get_aabb()` where `node_xform` is the
  cumulative transform from scene root down to the MeshInstance3D. This is
  what the model "looks like" when instantiated normally.

**Why:** The `.glb`s Blenderkit exports usually have a non-identity root
scale (or intermediate scale). The raw vertex AABB can be very different
from the on-screen visual size. Using the wrong one breaks scaling:

- Scaling math is `scale = target_size / raw.size` — must use RAW since
  MMI applies that scale to raw vertices.
- Tile-spacing decisions (how wide a "native" panel is) want VISUAL —
  matches the kit's authored design rhythm.

**How to apply:** When wiring a new kit, populate both AABBs in
`_get_kit_mesh`. Use `ctx.*_kit_aabb` for the basis scale, use
`ctx.*_kit_aabb_visual.size.x` (or z) for `tile_w` / `tile_d` in the
builders.

Related: [[blenderkit-import]] for the import pipeline that drops the
`.glb` and assigns it to a theme.
