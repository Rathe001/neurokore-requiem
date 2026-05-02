extends Resource
class_name LevelGraph
## Declarative level layout. Replaces hand-placed LevelPiece arrays for
## levels that want their geometry derived from a connection graph instead
## of manually positioned. The solver (GraphSolver.solve) walks the graph
## from `anchor_id`, places each room such that its opening lines up across
## the connecting corridor, and emits the LevelPieces that LevelBuilder
## consumes. The same LevelLayout can carry a graph OR a pieces array;
## graph wins when both are present.

## The room placed first. Its RoomNode.position is honoured; every other
## room's position is computed by the solver.
@export var anchor_id: StringName = &""
@export var rooms: Array[RoomNode] = []
@export var connections: Array[Connection] = []
## Polymorphic puzzle definitions. Each entry is a PuzzleDef subclass —
## either a built-in template (SwitchDoorPuzzle, BossKillDoorPuzzle) or a
## designer-authored one-off. PuzzleBuilder dispatches each one's apply()
## after all geometry, doors, and slots have been built.
@export var puzzles: Array[PuzzleDef] = []
