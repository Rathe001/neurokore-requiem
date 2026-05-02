extends Resource
class_name LevelLayout

@export var theme: LevelTheme
@export var ground_size: Vector2 = Vector2(60, 100)
## Hand-authored piece array. Each LevelPiece carries an absolute Vector3
## position. Used for legacy levels and the prototype; new levels should
## prefer `graph` instead.
@export var pieces: Array[LevelPiece] = []
## Declarative graph layout. When set, GraphSolver resolves it into pieces
## at build time, overriding the `pieces` array. Lets levels be authored
## by connection ("lobby east → corridor → lab west") instead of by
## absolute coordinates.
@export var graph: LevelGraph
## Procedural generator. When set, generator.generate() produces a fresh
## LevelGraph at build time which then flows through the same solver path.
## Wins over both `graph` and `pieces` when present.
@export var generator: LevelGenerator
