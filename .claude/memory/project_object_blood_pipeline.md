---
name: Object blood (splatter on props/interactables)
description: Receiver opt-in pipeline that paints blood decals on props, interactables, pillars near a kill — group + layer-8 + side-projected decal
type: project
---

When an enemy dies, `PrototypeAttackIndicator.spawn_blood_on_receivers`
iterates the `&"blood_receiver"` group, raycasts kill→prop for
visibility, and spawns a side-projected Decal3D per receiver inside
`OBJECT_BLOOD_RADIUS` (5m), capped at `OBJECT_BLOOD_MAX_PER_KILL` (4).

**Wiring a new paintable class** — single line in `_ready`:
```gdscript
PrototypeAttackIndicator.register_as_blood_receiver(self)
```
Adds to the group AND recursively ORs `OBJECT_BLOOD_LAYER` (bit 3,
value 8) into every VisualInstance3D descendant's `layers`. Decals
carry `cull_mask = 8` so they paint only opt-in geometry, never
floors/walls (those use the floor-pool pipeline on layer 1).
Currently wired: `DestructibleProp`, `HoverableInteractable`,
`WallBuilder` decorative pillars.

**Visibility-ray gotchas already burned:**
- *Receiver self-block:* CollisionObject3D receivers on the WORLD
  layer (pillars are 1|128) blocked their OWN visibility ray. Fix:
  `query.exclude = [receiver.get_rid()]`.
- *Low-ceiling block:* origin Y=1.0 hit crouch-tunnel ceiling
  collision. Lowered to Y=0.4 — walls still block, ceilings don't.
- *INTERACTABLE in mask:* ray mask = WORLD|INTERACTABLE|PILLAR
  (`1|64|128`), without 64 the ray passes through chests/switches.
- *SpatialGrid single-category limit:* receivers are already
  registered under their primary identity ("enemies",
  "interactables") so the second registration silently no-ops.
  Workaround: group iteration via `get_nodes_in_group`, not
  `SpatialGrid.query_radius`.

**Known unfixed: visibility on short flat props.** Side projection
(decal +Y = horizontal toward kill) paints the kill-facing vertical
face. Tall pillars read great because the side IS what the iso camera
sees. Short flat props (loot crates, security barriers, exam tables)
read mostly TOP from the iso angle, so the side paint is on a face
the camera barely sees. The diagnostic confirmed layers/visibility/
spawn all work — pure projection-angle issue. Likely fix when the
user comes back: add a SECOND top-down decal per receiver
(`proj_normal = Vector3.UP`) so the visible top face also gets paint.

**Opacity dial:** `BLOOD_DECAL_ALBEDO_MIX` constant (currently 0.92)
threads through all 6 decal spawn sites (floor pool, character splat,
wall splatter, droplet, prop side-paint, footprint). Lower = more
surface peek-through. 0.82 was too washed-out, 1.0 reads as flat
paint, 0.92 was the landing point.

**Why:** Blood/gore is intentionally a major aesthetic — receiver
opt-in pattern was chosen so adding new paintable object classes
later is a one-line change rather than per-class decal authoring.
