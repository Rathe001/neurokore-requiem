extends Resource
class_name LevelPiece

@export var position: Vector3 = Vector3.ZERO
@export var room: RoomDef
@export var corridor: CorridorDef
@export var enemy_positions: Array[Vector3] = []
