---
name: scale-to-player
description: "Standing reference for all in-world object sizes. Player capsule is 1.6m standing / 0.9m crouched (prototype_player.gd:153). Decal textures, prop meshes, weapons, and any new visible object must be sized relative to this baseline — measure twice when authoring."
type: feedback
---

Josh flagged 2026-06-09: medwaste decal syringes were appearing roughly
half the player's height. Player is 1.6m, so syringes (~15-20cm in
reality) were rendering at ~80cm — about 5× oversize.

**Why:** Each Midjourney decal texture depicts ~1m² of content, but the
decal's `size_range` was set to "how much floor we want to cover" (3-6m
on the large variants) rather than "how big the depicted items are". A
1m of items stretched across 5.5m means every item is rendered at 5.5×
real size.

**How to apply going forward:**
- Player standing reference: 1.6m (`STAND_HEIGHT` in
  `prototype_player.gd:153`)
- Player crouched: 0.9m (`CROUCH_HEIGHT`)
- Common real-world references:
  - A4 paper sheet: ~21 × 30 cm
  - Syringe: 15-20 cm
  - Glass shard: 5-15 cm
  - Concrete chunk: fist (10 cm) to head (20 cm)
  - Loot crate: ~0.8 m tall
  - Standard door: ~2 m tall
- Floor decals: `size_range` should match the depicted item scale,
  NOT the desired coverage area. If you want denser coverage, raise
  `decal_density` on the room instead of stretching the texture.
- 3D props: model in Blender with real-world units (1 Blender m = 1
  Godot m). Sanity-check the .glb in Godot against a reference cube
  matching player height (1.6 × 0.6 × 0.6 m) before committing.
- Mixamo / X Bot rig is already 1.6m tall — use it as the on-screen
  ruler.

**Things to actively watch for in future work:**
- New decal art: did the source image's content already match the
  size_range you set? Eyeball at iso camera distance.
- New props / clutter: are they readable next to the player avatar?
- New weapons: hold-in-hand pose looks proportional to the X Bot mesh?
- Boss-tier enemies: scaled up from the X Bot baseline, not overscaled
  to where they break navmesh.

Initial scale-pass shipped 2026-06-09: paper, medwaste, debris, broken
glass `size_range` dropped 2-3× to match depicted item scale. Stains
(dried_blood, oil, scorch) and stencils kept at original size — no
fixed item-scale reference. See commit alongside this memory landing
for the exact tuning.
