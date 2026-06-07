# Floor Decal Scatter — Spec

Status: **proposed** (not yet implemented). Author target: pre-release
backlog #4 (clutter), flat-litter half.

## Goal

Scatter flat, collision-free litter across procgen room floors — scattered
papers, debris, medical waste — to sell "this place was abandoned/ransacked"
and reinforce the lab-horror tone, at near-zero runtime cost.

This is the **decal** half of clutter. The **prop** half (3D meshy items
with footprints + collision) stays in `ClutterBuilder` / `ClutterPropDef`.
The split is deliberate: a thing that is genuinely *flat* should never be a
`StaticBody3D` with a collision shape — it's wasted nodes, wasted physics,
and a snag hazard for the player. See the dropped-weapon walk-through fix
for the same principle.

## What counts as a floor decal

Flat, lies on the ground, no silhouette to shoot over or path around:
- scattered papers / documents
- debris (glass + rubble + litter)
- medical waste (syringes, gauze, gloves)
- (future) scorch marks, oil streaks, drag marks not covered by LiquidLayer

If an item has real height (cable coil, bucket, stool) it's a **prop**, not a
decal — it goes through `ClutterPropDef`.

## Approach decision

Three candidates were considered:

1. **Decal3D projector nodes** — Godot's real decals. Project correctly, no
   z-fighting, but each is rendered per-frame and they share a global decal
   budget. Hundreds across a 25–40 room level blows that budget. Rejected.

2. **SubViewport bake** (like `LiquidLayer`) — bake all decals into one
   floor-spanning texture, sample via a shader. Zero per-frame cost after
   bake, but costs a 16–64 MB render target and a second floor-mesh draw,
   and the art is authored cut-out sprites, not procedural blobs — the
   SubViewport accumulation buys us nothing because placement is static at
   build time. Over-engineered for static litter. Rejected.

3. **MultiMesh flat quads** ✅ — one `MultiMeshInstance3D` per decal texture
   for the whole level; each instance is a unit `PlaneMesh` with its own
   transform (position, yaw, scale). One draw call per texture type, no
   collision, no per-frame logic, arbitrary density. This is the same
   batching the level builder already uses for corridor walls
   (`ctx.corridor_wall_visuals` → `commit_batched_mmi`). **Chosen.**

## Architecture

### New builder: `FloorDecalBuilder` (static, RefCounted)

`game/scripts/level/build/floor_decal_builder.gd`. Mirrors `DecalBuilder`
and `ClutterBuilder` exactly — stateless static methods, deterministic RNG
seeded by room id, wall margin, opening avoidance.

```
static func scatter_decals(ctx, center, hx, hz, rd, room_id := &"") -> void
```

Called from `level_builder.gd` right after `ClutterBuilder.scatter_clutter`
(around line 447), so litter lands after props are placed and can be told to
avoid their footprints in a later pass (v2; v1 ignores props — papers under a
filing cabinet edge is fine).

Per room:
1. Gate on `rd.decal_density <= 0` (new RoomDef field — see below).
2. Seed an RNG from `room_id` (reuse the `_hash_id` string-hash from
   ClutterBuilder so re-entering a room is stable).
3. `decal_density * N` placement attempts. For each:
   - pick a position via the `_pick_position` margin/opening logic (litter
     can sit closer to walls than props — use a smaller margin, ~0.6m).
   - weighted-pick a `FloorDecalDef` from the pool.
   - build a `Transform3D`: translate to `center + (px, y, pz)`, rotate
     `random_yaw_range` around Y, uniform-scale from `size_range`.
   - the Y is `FLOOR_DECAL_Y + small per-instance epsilon` (see z-fighting).
   - **append the transform to a per-def accumulator on `ctx`** —
     `ctx.floor_decal_visuals` keyed by `FloorDecalDef` → `Array[Transform3D]`.

Unlike puddles, decals do NOT commit per-room. They accumulate across the
whole level and commit once, exactly like `corridor_wall_visuals`.

### Commit: one MMI per decal texture

A new `FloorDecalBuilder.commit_floor_decals(ctx)` — called alongside
`WallBuilder.commit_batched_mmi(_ctx)` at `level_builder.gd:252` — walks
`ctx.floor_decal_visuals` and, per def, builds:
- a `MultiMesh` (transform_format = TRANSFORM_3D, mesh = shared unit
  `PlaneMesh` 1×1 in XZ facing +Y, instance_count = transforms.size()).
- a `MultiMeshInstance3D` with `material_override` = the def's material.
- `cast_shadow = OFF`, `gi_mode = DISABLED`.
- add to `ctx.root`, groups `structures` + `clutter` so the level-reset /
  rebuild loop tears them down with everything else.

One draw call per decal texture for the entire level. With the 3-item
minimum set that's **3 extra draw calls, full stop**, regardless of how
dense the litter is.

### Data model: `FloorDecalDef` Resource

`game/scripts/items/floor_decal_def.gd`, `class_name FloorDecalDef`.
One `.tres` per decal texture under `res://resources/decals/floor/`.

```
@export var id: StringName
@export var albedo_texture: Texture2D     # MJ cutout PNG, alpha background
@export var normal_texture: Texture2D     # optional; null = flat normal
@export var size_range: Vector2 = Vector2(0.8, 1.4)   # world metres, min/max
@export var aspect_jitter: float = 0.15   # per-instance non-uniform stretch
@export var random_yaw_range: float = PI  # full 360 by default
@export var weight: int = 2
@export var min_spacing: float = 0.4      # avoid stacking identical sprites
@export var prefer_wall: bool = false     # v2 placement hint
```

Authoring is inspector-only, same workflow as `ClutterPropDef` — duplicate a
`_TEMPLATE.tres`, drag the texture in, set the fields.

### Material per def

`StandardMaterial3D`:
- `albedo_texture` = def.albedo_texture
- `transparency = TRANSPARENCY_ALPHA_SCISSOR` (writes depth → sorts via the
  depth buffer, no transparency-sort artifacts when decals overlap; hard
  edge is fine for litter). Blend (`TRANSPARENCY_ALPHA`) is the alt if soft
  edges matter, but then overlapping decals need the Y-stagger to sort.
- `alpha_scissor_threshold ≈ 0.4`
- `shading_mode = PER_PIXEL` (stay lit — neon and room fluorescents should
  fall on the litter like everything else)
- `roughness ≈ 0.9`, `metallic = 0.0`
- `cull_mode = BACK` (camera is always above; single-sided up is fine)
- normal_texture wired if present.

Cache materials per def (build once, reuse) — same instinct as the texture
cache in ClutterBuilder.

### Pool loading — explicit file list, NOT directory enumeration

**Critical:** load the pool via an explicit array of paths +
`ResourceLoader.exists()`, never `DirAccess` enumeration over `res://`. That
silently returns nothing in exported Godot 4 builds and has bitten this
project four times. See `project_resource_loader_gotcha`. The pool list can
live as a `const` array of paths in `FloorDecalBuilder`, or as a per-theme
`floor_decal_pool: Array[FloorDecalDef]` on `LevelTheme` (preferred for
zone variation later — lab rooms pull medical waste, offices pull papers).

### RoomDef field

Add `@export var decal_density: int = 0` to `RoomDef`, in the same group as
`clutter_density` / `puddle_count`. Default 0 (opt-in) or a small default
like 2 once we trust it. Tuned per RoomDef template.

## Z-fighting

Two surfaces to not fight:
- **the floor** — lift decals to `FLOOR_DECAL_Y = 0.006` (just above the
  puddle layer's 0.005, below the LiquidLayer floor mesh at 0.015).
- **each other** — give each instance a tiny per-instance Y epsilon
  (`0.000 .. 0.004`, e.g. derived from the placement index) so two
  overlapping papers don't share an exact plane. With ALPHA_SCISSOR depth
  writes, even a sub-mm stagger resolves the sort.

## Interaction with the LiquidLayer (blood)

The LiquidLayer floor mesh sits at y=0.015 with `render_priority = -10`
(draws first, blend). Floor decals at y≈0.006 with default priority draw
*after* → litter would paint over blood pools. If blood-over-paper reads
better (it does — blood pools on top of scattered papers), set the decal
material `render_priority = -11` so it draws before the liquid. Flagged as a
tuning detail, not a blocker; pick whichever looks right in-engine.

## Multiplayer

Purely cosmetic and **deterministic** from the per-room seed → host and
every client build byte-identical litter with zero replication. Do NOT route
these through any `MultiplayerSpawner`. This sidesteps the
phantom-damage-style desync gap entirely (cf. the enemy-projectile
replication note) because there's no gameplay state to sync — it's set
dressing both sides compute independently.

## Asset pipeline (the 3 minimum decals)

MJ prompts already drafted (2026-06-06 conversation):
1. `paper_scatter` — scattered papers / redacted files
2. `debris_scatter` — glass + rubble + litter
3. `medwaste_scatter` — syringes, gauze, gloves

For each:
1. Generate top-down on MJ with the `flat lay, top-down orthographic,
   isolated on plain background` suffix.
2. Cut the background to alpha (the "isolated on plain background" makes this
   a clean key) → PNG with alpha.
3. Drop into `res://assets/textures/decals/floor/<id>.png`.
4. Import flags: mipmaps **on** (litter is viewed minified at iso distance),
   filter on, **Fix Alpha Border on** (kills the dark halo on cut edges).
5. Duplicate `resources/decals/floor/_TEMPLATE.tres` → `<id>.tres`, drag the
   texture in, set `size_range` (~0.8–1.4m for a paper cluster), `weight`.
6. Add the `.tres` to the pool (const list or theme pool).
7. Append a row to `docs/assets.md` per the asset-manifest convention.

## Phasing

- **P1 (MVP):** FloorDecalDef + FloorDecalBuilder + ctx accumulator + commit
  + RoomDef.decal_density + the 3 materials. Uniform random placement,
  ignores props. Const pool list. ~1 builder file + 1 resource class + small
  edits to RoomDef / level_builder / build_context.
- **P2:** per-theme `floor_decal_pool` on LevelTheme for zone variation;
  `prefer_wall` placement bias; avoid-prop-footprint pass.
- **P3 (optional):** runtime decals — drop a paper-scatter when a filing
  cabinet breaks (hook DestructibleProp death → spawn a one-off MMI-or-quad
  at the wreck). Reuses the same defs.

## Files touched (P1)

- NEW `game/scripts/items/floor_decal_def.gd`
- NEW `game/resources/decals/floor/_TEMPLATE.tres` (+ README)
- NEW `game/scripts/level/build/floor_decal_builder.gd`
- EDIT `game/scripts/level/build/build_context.gd` — add
  `floor_decal_visuals` dict + shared unit PlaneMesh + commit method
- EDIT `game/scripts/level/level_builder.gd` — call `scatter_decals` after
  clutter (~line 447); call `commit_floor_decals` alongside
  `WallBuilder.commit_batched_mmi` (line 252)
- EDIT `game/scripts/level/room_def.gd` — add `decal_density`
- EDIT `docs/assets.md` — asset rows for the 3 textures
```
