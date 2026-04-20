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

@export_group("Doors")
@export var door_openings: Array[Wall] = []
@export var locked_doors: Array[Wall] = []
