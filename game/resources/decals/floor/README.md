# Floor Decals

One `.tres` per flat floor-litter texture. Each defines a `FloorDecalDef`
(see `scripts/items/floor_decal_def.gd`). `FloorDecalBuilder` scatters them
as a single MultiMesh of flat quads per texture — no collision, no per-frame
cost, one draw call per texture for the whole level.

Full design: `docs/floor-decal-scatter-spec.md`.

## Decal vs prop

- **Flat** thing (papers, debris, medical waste, scorch marks) → decal here.
- Thing with **real height** (bucket, cable coil, stool) → `ClutterPropDef`
  under `resources/clutter/`.

## Adding a decal

1. Generate a **top-down** image, cut the background to alpha → PNG.
2. Drop into `res://assets/textures/decals/floor/<id>.png`.
   Import flags: **mipmaps on**, filter on, **Fix Alpha Border on**
   (kills the dark halo on cut edges).
3. Duplicate `_TEMPLATE.tres` → `<id>.tres`, drag the texture into
   `albedo_texture`, set `size_range` + `weight`.
4. Add the `.tres` path to `FloorDecalBuilder.POOL_PATHS`.
5. Append an asset row to `docs/assets.md`.

## Placeholders

Until real art is dropped in, leave `albedo_texture = null`. The builder
generates a procedural placeholder keyed by `id`:

- `paper_scatter` → cream sheets with text lines
- `debris_scatter` → grey angular shards
- `medwaste_scatter` → thin off-white + red bits
- anything else → magenta checker ("fix me")

So the scatter system is fully wired and visible in-engine before any
texture exists.

## Tuning density

Per room via `RoomDef.decal_density` (0–4), in the "Floor Decals" group.
Each unit ≈ 6 placement attempts. Set on individual room `.tres` files
under `resources/level/rooms/`.

## Current pool

- `paper_scatter.tres` — weight 3, the default abandonment cue
- `debris_scatter.tres` — weight 2, broken-environment scatter
- `medwaste_scatter.tres` — weight 1, lab-horror tone hook (rarer)
