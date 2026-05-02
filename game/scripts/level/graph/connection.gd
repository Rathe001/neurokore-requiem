extends Resource
class_name Connection
## A straight corridor between two rooms. Walls must be opposites
## (NORTH↔SOUTH or EAST↔WEST) — bent connections aren't supported. The
## corridor's axis is set automatically by the solver from the wall pair;
## designer-set length, width, lighting, pit, and ceiling come from the
## referenced CorridorDef.

## Stable identifier used by puzzles to look up the door at this connection.
## The DoorBuilder creates a single door at the from-room side of the
## opening; PuzzleBuilder maps this id → that door for puzzle.apply().
@export var id: StringName = &""
@export var from_room: StringName = &""
@export var from_wall: RoomDef.Wall = RoomDef.Wall.EAST
@export var to_room: StringName = &""
@export var to_wall: RoomDef.Wall = RoomDef.Wall.WEST
@export var corridor: CorridorDef
## When true, the LevelBuilder instantiates a door at this connection's
## from-side. Lets generators add doors without mutating shared RoomDef
## templates (the legacy RoomDef.door_openings field still works for
## hand-authored levels). Doors are unlocked by default; pair with a
## SwitchDoorPuzzle to lock.
@export var has_door: bool = false
