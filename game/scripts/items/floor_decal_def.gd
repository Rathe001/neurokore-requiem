class_name FloorDecalDef
extends Resource

## Authored definition for a flat floor-litter decal. One .tres per decal
## texture under res://resources/decals/floor/. FloorDecalBuilder pools
## these and scatters them as a single MultiMesh of flat quads per texture
## — no collision, no per-frame cost. See docs/floor-decal-scatter-spec.md.
##
## Decals are for things that are genuinely FLAT: scattered papers, debris,
## medical waste, scorch marks. Anything with real height (a bucket, a
## cable coil) is a prop — author a ClutterPropDef instead.
##
## Workflow for adding a Meshy/Midjourney-generated decal:
##   1. Generate a top-down image, cut the background to alpha → PNG
##   2. Drop the PNG into res://assets/textures/decals/floor/<id>.png
##      (import flags: mipmaps on, filter on, Fix Alpha Border on)
##   3. Duplicate _TEMPLATE.tres → res://resources/decals/floor/<id>.tres
##   4. Drag the texture into albedo_texture, set size_range + weight
##   5. Add the .tres path to FloorDecalBuilder.POOL_PATHS
##
## When albedo_texture is null, FloorDecalBuilder generates a procedural
## placeholder keyed by id so the scatter system works before art exists.


## ── Identity ────────────────────────────────────────────────────────────

## Unique identifier — match the .tres filename without extension. Used as
## the MMI node name (FloorDecals_<id>) and the placeholder-texture key.
@export var id: StringName = &""


## ── Visual ─────────────────────────────────────────────────────────────

## The decal art. Top-down image with an alpha background. Leave null to
## use a procedural placeholder (keyed by id) until real art is dropped in.
@export var albedo_texture: Texture2D

## Optional normal map. Null = flat normal (fine for most litter).
@export var normal_texture: Texture2D


## ── Placement / sizing ─────────────────────────────────────────────────

## World size band (metres). Each instance rolls a square size in this
## range; aspect_jitter then stretches it slightly off-square.
@export var size_range: Vector2 = Vector2(0.8, 1.4)

## Per-instance non-uniform stretch. 0 = always square; 0.15 = up to ±15%
## difference between the two axes. Keeps the scatter from looking stamped.
@export_range(0.0, 0.6) var aspect_jitter: float = 0.15

## Per-spawn random Y-axis rotation cap (radians). PI = full 360°.
@export var random_yaw_range: float = PI

## Drop weight in the pool. Relative — normalised at roll time.
@export var weight: int = 2

## Minimum distance to other placed decals of ANY type (metres). Litter can
## overlap more freely than props, so this is small by default. Stops the
## exact-same sprite from stacking on itself.
@export var min_spacing: float = 0.4

## v2 placement hint: prefer positions adjacent to a wall. Read by the
## wall-bias placement pass when it lands; ignored in P1.
@export var prefer_wall: bool = false

## Render layer (used by FloorDecalBuilder to assign a base Y offset so
## logically-stacked decals don't z-fight). Lower = closer to the floor,
## higher = on top. Convention:
##   0 = PAINTED  (stencils, painted facility markings — part of the
##                 floor itself, always at the bottom)
##   1 = STAIN    (dried blood, oil_dry, scorch — embedded in the
##                 floor surface, on top of paint)
##   2 = LITTER   (paper, debris, medwaste, glass — scattered items
##                 sitting on top of the floor)
##   3 = PILE     (multi-tile pile variants — drifts on top of litter)
## Runtime LiquidLayer (live blood pools) is at Y≈0.015, always above
## all four floor-decal layers.
@export_range(0, 3) var layer: int = 2
