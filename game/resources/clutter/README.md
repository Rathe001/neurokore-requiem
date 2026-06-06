# Clutter Props

One `.tres` per procgen clutter item. Each defines a `ClutterPropDef`
(see `scripts/items/clutter_prop_def.gd`). ClutterBuilder picks from
these by weight when populating rooms.

## Adding a new Meshy-generated item

1. **Generate on Meshy AI.** Suggested prompt shape:
   `<item name>, low-poly, PBR textures, <wear adjective>`
   e.g. `coolant tank, low-poly, PBR textures, rusted steel, warning labels`

2. **Download the model package** (`.glb` + texture PNGs zip).

3. **Drop the assets** into `res://assets/models/clutter/<id>/`:
   - `<id>.glb`
   - All texture PNGs alongside (the `meshy_character_import.gd` post-import
     script auto-discovers `Meshy_AI_*_texture.png` for character meshes;
     clutter doesn't currently auto-bind textures but Godot's default GLB
     importer will pick up materials embedded in the .glb on most exports)

4. **Duplicate `_TEMPLATE.tres`** to `res://resources/clutter/<id>.tres`,
   open it in the inspector, and fill in:
   - `id` (matches filename)
   - `display_name` (player-facing)
   - `mesh_scene` (drag the .glb from FileSystem dock)
   - `mesh_scale` (Meshy exports are often 2-3× too large)
   - `category` + `footprint` + `hp` + the placement hints

5. **Verify visually**:
   - Set `DebugConfig.dump_interactable_collision_audit = true` to print
     the mesh AABB in the console
   - Compare against your authored `footprint` value
   - Tune `mesh_y_offset` if the model floats or sinks

6. **Add to the pool** in `ClutterBuilder.gd` (or — when the pool
   migration lands — a per-zone `clutter_pool.tres` resource).

## Current state of the migration

- `ClutterPropDef` resource shape: shipped
- `_TEMPLATE.tres`: shipped
- `ClutterBuilder` pool migration: **NOT YET DONE**. The builder still
  uses inline `Array[Dictionary]` defs with procedural meshes and
  textures. When you have a small starter set of Meshy items (5-7),
  flip `ClutterBuilder` to read from `Array[ClutterPropDef]` pools
  loaded from this directory.
- Per-zone pools: future work. Theme/zone-specific clutter (lab room
  pulls specimen tanks + operating tables; industrial corridor pulls
  pipes + transformers) lives in `RoomDef` or a sibling resource.

## Recommended starter set

From the suggested item list (2026-06-05 conversation):

1. `coolant_tank.tres` — STATIC_BLOCKER, prefer_corner
2. `junction_box.tres` — DESTRUCTIBLE_SOFT, prefer_wall, low credits
3. `hazard_barrel.tres` — DESTRUCTIBLE_SOFT, explodes (future flag)
4. `filing_cabinet.tres` — DESTRUCTIBLE_SOFT, drops_loot
5. `office_chair.tres` — DECOR, no collision needed
6. `specimen_tank.tres` — STATIC_BLOCKER (tone hit, rare weight)
7. `pipe_bundle.tres` — STATIC_BLOCKER, low silhouette

That covers 80% of typical room compositions and gives a stable
starting pool to wire into the builder.
