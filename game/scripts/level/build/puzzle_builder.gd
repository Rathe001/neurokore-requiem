extends RefCounted
class_name PuzzleBuilder
## Dispatches each PuzzleDef.apply() once all geometry, doors, and slots are
## built. Also constructs the connection-id → door map that puzzles need to
## reference doors by name (the DoorBuilder keys doors by "{room_id}_{wall}",
## which puzzles shouldn't have to know about).

static func apply_all(ctx: LevelBuildContext, _layout: LevelLayout) -> void:
	# Read graph from ctx, NOT from layout — for generator-driven levels the
	# graph is the transient generator output stored on the context, not
	# layout.graph (which is null in that case).
	if ctx.graph == null or ctx.graph.puzzles.is_empty():
		return

	var doors_by_connection_id := _build_door_map(ctx, ctx.graph)
	for puzzle: PuzzleDef in ctx.graph.puzzles:
		if puzzle == null:
			continue
		puzzle.apply(ctx, ctx.slots, doors_by_connection_id)


# Maps Connection.id → PrototypeDoor at the from-room side. Connections
# without an id, or where the door wasn't built, are silently skipped — the
# door may simply not be a door opening (no door declared on the wall).
static func _build_door_map(ctx: LevelBuildContext, graph: LevelGraph) -> Dictionary:
	var out: Dictionary = {}
	for c: Connection in graph.connections:
		if c == null or c.id == &"":
			continue
		var key := StringName("%s_%s" % [c.from_room, ctx.wall_keys[c.from_wall]])
		var door: Node = ctx.doors.get(key)
		if door != null:
			out[c.id] = door
	return out
