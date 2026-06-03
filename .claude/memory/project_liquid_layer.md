---
name: liquid-layer-architecture
description: "SubViewport-rasterized floor fluid system that replaced the per-decal floor-pool pipeline. One LiquidLayer per fluid_type, shader does multiply-stain + PBR wet sheen in a single pass. Per-hit droplets and corpse settle pools both stamp into it."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

The new floor-blood system. **Visual only — gameplay slip-zones are
standalone Area3Ds** (see slip-zone note below). Replaces the legacy
per-decal floor-pool system that had attach-or-grow, modulate-darken
tweens, and visible inter-pool silhouette seams.

## Layout

- **`game/scripts/systems/liquid_layer.gd`** — LiquidLayer class. One
  per fluid type, found via `LiquidLayer.find_for(tree, fluid_id)`
  (which wraps the `liquid_layer:<fluid_id>` group lookup and emits a
  one-time warning if it falls back to "any liquid layer"). The
  fluid_id is a single-token key matching `PrototypeEnemy.blood_type`:
  `&"human"`, `&"cyborg"`, `&"machine"`, future `&"oil"`, `&"water"`.
  Never prefix with `"blood_"` — those keys are shared between blood
  and non-blood fluids.
- **`game/scenes/world/liquid_layer.tscn`** — Thin scene wrapper.
  Instanced in `game/scenes/world/level_shell.tscn` as `BloodLayer`
  with `fluid_id = &"human"`. Other fluids will instance their own
  copy here.
- **`game/shaders/liquid_surface.gdshader`** — Single shader that
  samples a coverage mask + the floor underneath (via
  `hint_screen_texture`) and outputs a multiplied-stain ALBEDO with
  low-roughness PBR for the wet sheen.

## How it works

Each LiquidLayer owns a SubViewport (2048², `CLEAR_MODE_NEVER`,
transparent BG, `disable_3d = true`) holding a Camera2D at center and
a `StampRoot` Node2D. `stamp(world_pos, tex, world_radius, intensity)`
spawns a Sprite2D under StampRoot with `BLEND_MODE_ADD`, positioned in
viewport pixel space via explicit world→pixel math, then queue_frees
the sprite after one process_frame. The mask retains the rasterized
pixels across frames because of CLEAR_MODE_NEVER.

A floor MeshInstance3D (40m × 40m plane) sits at `y = 0.015` and uses
the shader to sample the mask. Stamps blend additively in the mask so
overlapping ones merge seamlessly — no per-stamp silhouette no matter
how many land in the same spot.

## Non-obvious things that already burned us

- **Camera2D.zoom MUST be 1.0.** Anything else interacts with sprite
  pixel positions in surprising ways. World→pixel conversion is done
  manually in `_world_to_viewport_px()`: `world_xz * PIXELS_PER_METER + half_size`.
- **PIXELS_PER_METER = 51.2** (= 2048px / 40m world extent). Stamps
  smaller than ~5 world cm get fewer than a handful of pixels and
  most of their alpha gets eaten by `coverage_threshold` — the
  shader's discard cutoff.
- **`coverage_threshold = 0.015`.** Was 0.04 originally and tiny
  per-hit droplet stamps were invisible (only the center pixel
  survived). Lower threshold + bigger droplets (8-14cm radius) was
  the fix.
- **Surface noise normal is STATIC** (no TIME drift). Animated drift
  made pools look like they were rippling. Spilled blood doesn't
  move; the wet shimmer comes from camera/light angle changes
  hitting the static perturbed normal.
- **`stain_brightness = 2.0` lifts the multiplied result.** Pure
  multiply (1.0×) crushed shadowed-room pools to near-black, so they
  read as holes in the floor. 2.0 keeps stains visibly red even in
  dim corridors.
- **fresh→dried gradient is narrow:** `fresh_color = (0.55, 0.10,
  0.10)`, `dried_color = (0.42, 0.12, 0.12)`. Wide gradients (e.g.
  `0.72 → 0.30`) read as a strong fresh→black swing that the user
  flagged as wrong.

## Stamp shapes

Both per-hit droplets and corpse settle pools use the same texture
generator: `PrototypeEnemy._get_settle_stamp_texture()` returns one
of 12 chaotic lobed splatters. Perimeter is two-octave 2D FastNoise
sampled along a polar ring (low octave 0.40 amplitude broad lobes +
high octave 0.15 jagged fingers) + per-pixel internal density noise
to break up the interior. **Never use sine-wave perimeters** — they
produce flower-petal silhouettes at large sizes.

The `_stamp_to_liquid_layer` helper in `prototype_attack_indicator.gd`
adds per-stamp aspect-ratio jitter (±20%) + random rotation in the
sprite math.

## Slip-zone gameplay hook

LiquidLayer is **visual only**. The Traction gameplay hook (slip /
stumble) needs an Area3D, so each corpse settle pool spawns a
standalone `&"blood_slip_zone"` group Area3D via
`PrototypeAttackIndicator.spawn_blood_slip_zone(parent, pos, radius)`.

**Per-hit droplets do NOT spawn slip zones** — would be dozens of
overlapping areas per fight, expensive and gameplay-meaningless. Only
corpse pools count for slip + footprints.

`PrototypeAttackIndicator.is_in_blood(world_pos)` scans the
slip-zone group with an XZ cylinder check. The footstep system
(`game/scripts/util/footsteps.gd`) polls it to decide when to
refresh the bloody-print counter.

## What's still on the old Decal system

Migration is partial as of 2026-06-01. See [[project_blood_migration_status]]:
- ✓ Floor pools (LiquidLayer)
- ✓ Per-hit droplets (LiquidLayer)
- Walls — still old Decal `spawn_blood_wall_splatter`
- Receivers (props/interactables/pillars) — still old Decal,
  see [[project_object_blood_pipeline]]
- Footprints — still old Decal
- Character splats — still old Decal
- Mist particle bursts — GPUParticles3D, not decals (stays as-is)

Once walls land on LiquidLayer (task #110), the old decal-ring
infrastructure can shrink significantly — it'd only need to cover
footprints + character splats.
