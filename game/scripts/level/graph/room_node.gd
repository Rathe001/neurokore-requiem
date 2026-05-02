extends Resource
class_name RoomNode
## A graph node wrapping a reusable RoomDef with a level-local id. The id
## is what Connections refer to. `position` is only consulted when this
## node is the anchor of its LevelGraph; for every other node, the solver
## computes the position from incoming connections.

@export var id: StringName = &""
@export var room: RoomDef
## Anchor position (used only on the LevelGraph's anchor room). Other
## rooms have their position derived by the solver.
@export var position: Vector3 = Vector3.ZERO
## Per-piece overrides for enemy spawn locations (relative to room centre).
## Empty = random placement inside the room bounds via RoomDef.enemy_count.
@export var enemy_positions: Array[Vector3] = []
## Extra interactable slots layered on top of the RoomDef's slots — lets a
## generator (or designer) attach per-instance interactables to a room
## without mutating the shared RoomDef template. Spawned by the same
## InteractableBuilder pass; ids are local to this RoomNode.
@export var additional_slots: Array[InteractableSlot] = []
## Per-piece enemy level band; (0, 0) = use scene defaults. Procgen sets
## this to scale enemy difficulty with depth.
@export var enemy_level_range: Vector2i = Vector2i.ZERO
## Per-instance theme override. Wins over RoomDef.theme_override so a
## generator can theme a region without mutating the shared template.
## Null = inherit RoomDef's override (or layout default).
@export var theme_override: LevelTheme
## Per-instance enemy count override. -1 = inherit RoomDef.enemy_count.
## Generators use this to scale density (boss minions, lair rooms) without
## authoring another template variant.
@export var enemy_count_override: int = -1
