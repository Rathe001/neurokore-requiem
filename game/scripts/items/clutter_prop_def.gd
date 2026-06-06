class_name ClutterPropDef
extends Resource

## Authored definition for a procgen clutter prop. One .tres per item
## under res://resources/clutter/. ClutterBuilder pools these and picks
## by weight per room.
##
## Workflow for adding a Meshy-generated item:
##   1. Generate on Meshy AI, download the .glb + texture set
##   2. Drop the .glb + textures into res://assets/models/clutter/<id>/
##   3. Duplicate _TEMPLATE.tres → res://resources/clutter/<id>.tres
##   4. Open the new .tres in the inspector and fill in the fields below
##   5. Add the .tres to the pool array on ClutterBuilder (or a per-zone
##      clutter pool resource if zone variation lands)
##
## Design intent: one of these reads as a single concrete item the player
## sees in a room — a coolant tank, a filing cabinet, a hazard barrel.
## Don't author meta-categories ("crate") here; author specific items
## with their own silhouette. Variety lives at the pool layer.


## ── Identity ────────────────────────────────────────────────────────────

## Unique identifier — match the .tres filename without extension.
## Used as the node name prefix at spawn (Prop_<id>) and as the dedup
## key in the placement system.
@export var id: StringName = &""

## Player-facing name. Shown in debug overlays and (when applicable)
## tooltips. Title case. Example: "Coolant Tank", "Filing Cabinet".
@export var display_name: String = ""


## ── Visual ─────────────────────────────────────────────────────────────

## The .glb model. Mixamo-style root scale 1.0 imports are simplest;
## adjust scale via mesh_scale below rather than re-importing.
@export var mesh_scene: PackedScene

## Uniform scale applied to the spawned model. Use this to bring a
## Meshy export down to playable scale without re-importing (Meshy
## often exports at 2-3m for human-scale objects).
@export var mesh_scale: float = 1.0

## Vertical nudge added to the model's local Y. Use when the .glb pivot
## isn't at the model's base — positive lifts the model, negative
## lowers it. Same idea as EnemyClass.feet_y_adjust. Typical range
## ±0.5m for items whose pivot is at the geometric center.
@export var mesh_y_offset: float = 0.0

## Per-class Y-axis rotation (radians) applied to the spawned model.
## Use when the .glb is authored facing the wrong axis. Default 0.
@export var mesh_yaw_offset: float = 0.0

## Per-spawn random Y rotation cap (radians). 0 = always face the
## same direction. PI = full 360° randomness. Use ~0.5 for items
## that should mostly face a "front" but get slight variation.
@export var random_yaw_range: float = PI


## ── Gameplay shape ─────────────────────────────────────────────────────

## What kind of prop this is. Drives collision layer + damage behavior:
##   DESTRUCTIBLE_SOFT  — destructible, on PILLAR only. Enemies phase
##                        through; player projectiles + LOS hit. The
##                        default for breakable cover (barrels, crates,
##                        filing cabinets).
##   DESTRUCTIBLE_HARD  — destructible but ALSO blocks enemies. For
##                        large items that should obstruct AI pathing
##                        until destroyed (exam tables, gurneys).
##   STATIC_BLOCKER     — permanent solid cover (cell bars, security
##                        barriers). On WORLD + PILLAR. High implied HP.
##   DECOR              — no collision at all. Pure visual. Floor
##                        scatter (papers, cable bundles, debris).
@export var category: Category = Category.DESTRUCTIBLE_SOFT

enum Category {
	DESTRUCTIBLE_SOFT,
	DESTRUCTIBLE_HARD,
	STATIC_BLOCKER,
	DECOR,
}

## Footprint used for placement spacing + collision sizing. Should
## match the .glb's XYZ extents at the chosen mesh_scale. Y matters
## for tall items (cell bars 2.5m) — placement uses XZ only but
## ClutterBuilder uses Y for the collision shape's height.
##
## Tip: enable DebugConfig.dump_interactable_collision_audit to print
## the actual mesh AABB; copy those values here.
@export var footprint: Vector3 = Vector3(1.0, 1.0, 1.0)


## ── Combat ─────────────────────────────────────────────────────────────

## Hit points for destructibles. Ignored for STATIC_BLOCKER (uses
## an internal hard-cover HP cap) and DECOR.
@export var hp: int = 10

## True when this prop's silhouette blocks combat LOS (cover). Drives
## the WORLD layer bit on the collision body. Set false for low-slung
## items the player should shoot over (toolboxes, cable spools).
@export var provides_cover: bool = true


## ── Loot ───────────────────────────────────────────────────────────────

## When true, breaking this prop spawns an item drop using the level's
## standard loot table. Reserve for "valuable-looking" props
## (filing cabinets, medical carts, weapon racks).
@export var drops_loot: bool = false

## When true, breaking this prop drops credits in the range below.
## Independent from drops_loot; small props can drop credits without
## a full item roll.
@export var drops_credits: bool = false
@export var credit_range: Vector2i = Vector2i(1, 3)


## ── Placement hints ────────────────────────────────────────────────────

## Drop weight in the pool. Relative — pool entries are normalised at
## roll time. Common items 2-3, rare 1, common-rare 1.
@export var weight: int = 2

## Minimum clearance to other placed props (metres). Default 1.0m is
## the ClutterBuilder baseline. Tall narrow items (IV stands, pipes)
## can drop to 0.6m; large solid items (coolant tanks, generators)
## should bump to 1.5m so they don't cluster.
@export var min_clearance: float = 1.0

## Hint to the placement system: prefer positions adjacent to a wall.
## Useful for wall-mounted-looking items (server racks, junction boxes,
## monitors). Soft preference today; ClutterBuilder reads this when
## the wall-prefer placement pass lands.
@export var prefer_wall: bool = false

## Hint: prefer positions adjacent to a corner. Useful for tall solid
## items that visually anchor a room (coolant tanks, generators).
@export var prefer_corner: bool = false
