---
name: object-blood-splatter-on-props-interactables
description: "Receiver opt-in pipeline that paints blood decals on props, interactables, pillars near a kill — group + layer-8 + side-projected decal. NOTE 2026-06-01: still on the old Decal system; migration to [[project_liquid_layer]] is task #111."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**2026-06-01:** This pipeline is unchanged by the floor → LiquidLayer
migration. Props/interactables/pillars are still painted via Decal3D
on cull_mask = 8. Task #111 will migrate this alongside character
splats. Until then everything below remains current.


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

**Resolved (2026-05-21): short flat props now get a second top-down
decal.** Each receiver inside the spawn radius now gets BOTH a
side-projected decal (existing behavior, paints the kill-facing
vertical face — reads on tall pillars) AND a top-down decal that
projects from just above the AABB top-face center downward. Top
decal's projection depth = the AABB height clamped to [0.4, 1.5] so a
tall pillar's stamp doesn't reach into the floor and a short crate's
still covers top-to-bottom. `_spawn_object_blood_decal` now takes an
optional `projection_depth` param (default 1.8 for side-paint). The
two-call site is `spawn_blood_on_receivers` after the visibility ray
clears. `OBJECT_BLOOD_MAX_PER_KILL` still counts RECEIVERS (4),
producing up to 8 decals/kill — well under the BLOOD_DECAL_MAX
ring-buffer cap. Diagnostic `print()` calls in the visibility-ray
path also removed in the same pass since the layers/raycast question
is settled.

**Opacity dials:** Two separate constants now —
- `BLOOD_DECAL_ALBEDO_MIX = 0.92` for floor pool, character splat,
  wall splatter, droplet, and footprint decals. 0.82 was too
  washed-out, 1.0 reads as flat paint, 0.92 was the landing point.
- `OBJECT_BLOOD_ALBEDO_MIX = 0.96` for the prop side + top decals.

**Object decals are NOT in the global blood ring buffer.** They self-free via tween after `OBJECT_BLOOD_FADE_DURATION = 14s` and are capped per-kill at `OBJECT_BLOOD_MAX_PER_KILL = 4` receivers (so worst case 8 decals/kill once side+top doubled up). The priority-eviction system documented in [[blood-decal-ring]] governs floor / wall / footprint decals only — props are separate so a busy fight doesn't push prop blood out via FIFO before its fade naturally completes.
  Props are typically lit brighter than floor (direct fluorescent
  overhead, no shadowing from ceiling), so the project-wide 0.92 read
  as nearly-invisible against bright prop materials. Bumped 0.92 →
  0.99 → 0.96 on 2026-05-21; 0.99 read as flat paint, 0.96 lets the
  surface barely peek through which preserves the "just-spilled"
  texture feel without bleaching out.

**Why:** Blood/gore is intentionally a major aesthetic — receiver
opt-in pattern was chosen so adding new paintable object classes
later is a one-line change rather than per-class decal authoring.
