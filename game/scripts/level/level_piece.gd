extends Resource
class_name LevelPiece

@export var position: Vector3 = Vector3.ZERO
@export var room: RoomDef
@export var corridor: CorridorDef
@export var enemy_positions: Array[Vector3] = []
## Per-instance identifier — unique across the resolved level. Set by
## GraphSolver from RoomNode.id (so the same RoomDef template can be reused
## across many pieces); legacy hand-authored pieces leave this empty and
## fall back to RoomDef.id (which they author as unique-per-room anyway).
@export var room_id: StringName = &""
## Per-instance interactable slots layered on top of RoomDef.slots. Set by
## GraphSolver from RoomNode.additional_slots; lets a generator attach
## per-instance switches/markers without mutating shared templates.
@export var additional_slots: Array[InteractableSlot] = []
## Per-piece enemy level band, used by EnemySpawner when spawning. (0, 0)
## means "use scene defaults" — what hand-authored pieces want. Generators
## set this to scale difficulty by depth-from-spawn.
@export var enemy_level_range: Vector2i = Vector2i.ZERO
## Per-instance theme override propagated from RoomNode.theme_override by
## GraphSolver. Wins over RoomDef.theme_override / CorridorDef.theme_override
## in LevelBuilder. Null = fall through to those.
@export var theme_override: LevelTheme
## Per-instance enemy count override. -1 = use RoomDef.enemy_count (the
## template default). Lets a generator scale density without authoring
## another template variant — e.g. boss minions, "lair" chain rooms.
@export var enemy_count_override: int = -1
