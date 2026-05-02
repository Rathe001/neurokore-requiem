extends LevelGenerator
class_name LinearGenerator
## Straight east-going chain of rooms picked from a template pool. v1 scope:
##   start template (must have an EAST opening) → N linear templates (must
##   have WEST + EAST openings) → end template (must have a WEST opening).
## Connection corridors are uniform (one shared CorridorDef). No branches,
## no rotation, no procedural puzzles — those are future generators.
##
## Per-instance RoomNode ids are r0, r1, ... r{length-1}; connection ids
## are c0, c1, ... c{length-2}. Generated puzzles (when added) reference
## these ids the same way authored puzzles do.

@export var templates: Array[RoomTemplate] = []
@export var corridor: CorridorDef
@export_range(1, 64) var min_length: int = 4   ## total rooms incl. start + end
@export_range(1, 64) var max_length: int = 6
@export var anchor_position: Vector3 = Vector3.ZERO


func generate() -> LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(Time.get_unix_time_from_system())

	var length := rng.randi_range(min_length, max_length)
	if length < 2:
		push_error("[LinearGenerator] length must be >= 2 (need start + end).")
		return null
	if corridor == null:
		push_error("[LinearGenerator] corridor not set.")
		return null

	var start_t := LevelGenerator.pick_by_role(templates, &"start", rng)
	var end_t := LevelGenerator.pick_by_role(templates, &"end", rng)
	if start_t == null or end_t == null:
		push_error("[LinearGenerator] template pool needs role='start' and role='end'.")
		return null

	var graph := LevelGraph.new()
	graph.anchor_id = &"r0"

	# Start
	var start_node := RoomNode.new()
	start_node.id = &"r0"
	start_node.room = start_t.room
	start_node.position = anchor_position
	graph.rooms.append(start_node)

	# Linear interior
	for i in range(1, length - 1):
		var t := LevelGenerator.pick_by_role(templates, &"linear", rng)
		if t == null:
			push_error("[LinearGenerator] template pool needs role='linear'.")
			return null
		var n := RoomNode.new()
		n.id = StringName("r%d" % i)
		n.room = t.room
		graph.rooms.append(n)

	# End
	var end_node := RoomNode.new()
	end_node.id = StringName("r%d" % (length - 1))
	end_node.room = end_t.room
	graph.rooms.append(end_node)

	# Connections — straight east-going chain.
	for i in length - 1:
		var c := Connection.new()
		c.id = StringName("c%d" % i)
		c.from_room = StringName("r%d" % i)
		c.from_wall = RoomDef.Wall.EAST
		c.to_room = StringName("r%d" % (i + 1))
		c.to_wall = RoomDef.Wall.WEST
		c.corridor = corridor
		graph.connections.append(c)

	return graph


