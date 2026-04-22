extends Resource
class_name CorridorDef

enum Axis { X, Z }

@export var width: float = 4.0
@export var length: float = 8.0
@export var axis: Axis = Axis.Z

@export_group("Lighting")
@export var light_color: LightColor
@export var light_interval: float = 0.0

@export_group("Enemies")
@export var enemy_count: int = 0
@export var enemy_scene: PackedScene

@export_group("Platformer")
@export var ceiling_height: float = 0.0  ## 0 = theme default; forces a low ceiling when > 0
@export var pit_width: float = 0.0       ## 0 = solid floor; creates a gap of this width at centre
