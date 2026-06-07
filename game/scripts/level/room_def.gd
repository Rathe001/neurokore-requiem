extends Resource
class_name RoomDef

enum Wall { NORTH, SOUTH, EAST, WEST }

@export var id: StringName = &""
@export var size: Vector2 = Vector2(6, 6)
@export var openings: Array[Wall] = []
@export var opening_width: float = 4.0

@export_group("Lighting")
@export var light_color: LightColor

@export_group("Theming")
## Optional theme override for this room. When set, the LevelBuilder swaps
## ctx.theme to this for the duration of the room's build pass. Materials
## are cached per-theme so repeated overrides are cheap. Constraint:
## override themes should share wall_height / wall_thickness / opening_width
## with the layout theme — the wall mesh cache keys on size only and
## mismatched geometry would carry over to the next piece.
@export var theme_override: LevelTheme

@export_group("Enemies")
@export var enemy_count: int = 0
@export var enemy_scene: PackedScene
## Class pool for enemies spawned in this room. When non-empty, the
## spawner picks one EnemyClass per spawn (solo or pack member) so the
## room reads as a mixed unit composition — melee + ranged + support
## within the same pack — instead of a single homogenous archetype
## inherited from the scene template. Empty falls back to whatever
## class is set on enemy_scene.
@export var enemy_classes: Array[EnemyClass] = []

@export_group("Audio")
@export var acoustic_profile: AcousticProfile

@export_group("Decals")
# Number of randomly-placed reflective puddles on the room floor. Picked from
# a deterministic randomization so re-entering the room doesn't shuffle them.
@export_range(0, 8) var puddle_count: int = 0
# Radius range (metres) for the irregular blob. Each puddle rolls a size in
# this band; the actual silhouette is noise-distorted around it.
@export var puddle_size: Vector2 = Vector2(0.9, 1.6)

@export_group("Doors")
@export var door_openings: Array[Wall] = []
@export var locked_doors: Array[Wall] = []
# Per-wall unlock-count gating. e.g. {Wall.EAST: 3} means the east-wall door
# needs three unlock() calls before it opens — one per switch in a multi-switch
# puzzle. Wall must also appear in locked_doors.
@export var unlock_required_doors: Dictionary = {}
# Walls whose doors should auto-unlock when the boss dies. Each listed door
# joins the "boss_listeners" group on _ready.
@export var boss_unlock_doors: Array[Wall] = []

@export_group("Interactables")
## Spawn points for world interactables (switches, loot crates, exits, etc.).
## Each slot is materialised by InteractableBuilder when the room is built and
## registered in BuildContext.slots under the key "{room_id}.{slot_id}" so
## puzzles and other systems can look it up by level-global name.
@export var slots: Array[InteractableSlot] = []

@export_group("Pit")
## When true, the room floor is replaced with a pit (kill drop). Pillars are
## required for traversal. A solid floor strip of width pit_margin is retained
## at each wall edge so openings have a landing pad.
@export var pit_floor: bool = false
@export var pit_margin: float = 1.5
## Spike-pit visual treatment: dark stone floor with menacing spike geometry
## instead of the default glowing ooze. Kill mechanic is unchanged. Lit by a
## dim warm light from below for visibility.
@export var spike_pit: bool = false
## Bottomless variant — no pit floor at all, deeper shaft (10m vs the
## theme's pit_depth). Reads as a true abyss: dark void below the rim.
## Wins over spike_pit when both are set. Kill mechanic unchanged
## (GroundBuilder's kill zone at y = -10 catches the fall).
@export var bottomless_pit: bool = false
## Pillar XZ centres in room-local coords (relative to room centre). Each
## pillar is a square column standing in the pit with its top flush at floor
## level — a stepping stone the player can land on after a jump.
@export var pillars: Array[Vector2] = []
## Uniform XZ extent of every pillar (width, depth).
@export var pillar_size: Vector2 = Vector2(1.5, 1.5)

@export_group("Decorative Pillars")
## Pillar XZ centres in room-local coords (relative to room centre). Each
## becomes a full-height static box from floor to ceiling. Independent
## from `pillars` above — those are pit-specific jump platforms; these
## are just architectural columns the player walks around.
@export var decorative_pillars: Array[Vector2] = []
## Uniform XZ extent of every decorative pillar (width, depth).
@export var decorative_pillar_size: Vector2 = Vector2(1.0, 1.0)

@export_group("Clutter")
## Density of scattered props. 0 = none, 1 = sparse (2 destructible + 1
## indestructible), 2 = moderate (4 + 2), 3 = dense (6 + 3).
@export_range(0, 3) var clutter_density: int = 0

@export_group("Floor Decals")
## Density of flat floor litter (scattered papers, debris, medical waste).
## 0 = none. Each unit is ~6 placement attempts. Collision-free, batched
## into one MMI per texture. See docs/floor-decal-scatter-spec.md.
@export_range(0, 4) var decal_density: int = 0
