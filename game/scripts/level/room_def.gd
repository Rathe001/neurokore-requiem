extends Resource
class_name RoomDef

enum Wall { NORTH, SOUTH, EAST, WEST }

@export var id: StringName = &""
@export var size: Vector2 = Vector2(6, 6)
@export var openings: Array[Wall] = []
@export var opening_width: float = 4.0

@export_group("Lighting")
@export var light_color: LightColor

@export_group("Enemies")
@export var enemy_count: int = 0
@export var enemy_scene: PackedScene

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
