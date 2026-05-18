extends RefCounted
class_name GraphSolver
## Resolves a LevelGraph into the flat Array[LevelPiece] that LevelBuilder
## consumes. The solver:
##   1. Places the anchor room at its declared position.
##   2. BFS through connections, deriving each next room's position from
##      `current_pos + outward(wall) * (currentSize/2 + corridorLen + nextSize/2)`.
##   3. Emits one room piece per placed RoomNode and one corridor piece per
##      Connection (with corridor.axis overridden by the wall pairing).
##   4. Warns on unreachable rooms, position mismatches between paths, and
##      overlapping room AABBs.
##
## Constraints (enforced; violations skip the connection):
##   - Both walls in a connection must be opposites (NORTH↔SOUTH or EAST↔WEST).
##   - Connection.corridor must be set.
##   - Both referenced rooms must exist in graph.rooms.


## `grid_size > 0` snaps every room size, corridor length, and opening width
## to the kit's grid BEFORE positions are computed. Without this, the builder
## quantized after placement, which made corridors over-shoot their connecting
## rooms when grid-up rounding bumped a corridor's length past the gap.
static func solve(graph: LevelGraph, grid_size: float = 0.0) -> Array[LevelPiece]:
	var pieces: Array[LevelPiece] = []
	if graph == null:
		return pieces

	var nodes: Dictionary = {}
	for n: RoomNode in graph.rooms:
		if n == null or n.id == &"":
			push_warning("[GraphSolver] Room node missing id; skipping.")
			continue
		if nodes.has(n.id):
			push_warning("[GraphSolver] Duplicate room id '%s'; later definition wins." % n.id)
		nodes[n.id] = n

	if not nodes.has(graph.anchor_id):
		push_error("[GraphSolver] Anchor id '%s' not found in graph.rooms." % graph.anchor_id)
		return pieces

	# Pre-quantize each room's size / opening_width so position math and the
	# emitted geometry stay in lockstep. Stored per-id so BFS and the room/
	# corridor emit passes all read the same values.
	var quantized_size: Dictionary = {}      # id -> Vector2
	var quantized_opening: Dictionary = {}   # id -> float
	for id_key: StringName in nodes.keys():
		var rm: RoomDef = (nodes[id_key] as RoomNode).room
		quantized_size[id_key] = _snap_vec2(rm.size, grid_size)
		quantized_opening[id_key] = _snap_scalar(rm.opening_width, grid_size)

	var positions: Dictionary = {}
	var anchor: RoomNode = nodes[graph.anchor_id]
	positions[anchor.id] = anchor.position

	var queue: Array = [anchor.id]
	while queue.size() > 0:
		var current_id: StringName = queue.pop_front()

		for c: Connection in graph.connections:
			if c == null:
				continue
			# Connections are undirected — match either end against the popped room.
			var next_id: StringName
			var current_wall: RoomDef.Wall
			var next_wall: RoomDef.Wall
			if c.from_room == current_id:
				next_id = c.to_room
				current_wall = c.from_wall
				next_wall = c.to_wall
			elif c.to_room == current_id:
				next_id = c.from_room
				current_wall = c.to_wall
				next_wall = c.from_wall
			else:
				continue

			if not _are_opposite(current_wall, next_wall):
				push_error("[GraphSolver] Connection %s↔%s walls are not opposites; skipping." % [c.from_room, c.to_room])
				continue
			if not nodes.has(next_id):
				push_error("[GraphSolver] Connection references unknown room '%s'." % next_id)
				continue
			if c.corridor == null:
				push_error("[GraphSolver] Connection %s↔%s has no corridor; skipping." % [c.from_room, c.to_room])
				continue

			var dir := _outward_dir(current_wall)
			var current_along := _size_along(quantized_size[current_id], current_wall)
			var next_along := _size_along(quantized_size[next_id], next_wall)
			var corridor_len := _snap_scalar(c.corridor.length, grid_size)
			var computed: Vector3 = positions[current_id] + dir * (current_along * 0.5 + corridor_len + next_along * 0.5)

			if positions.has(next_id):
				# Cycle in the graph or two paths to the same room — verify they
				# agree on placement; warn but don't crash if they don't (designer
				# can iterate; first-place wins so geometry is deterministic).
				var existing: Vector3 = positions[next_id]
				if existing.distance_to(computed) > 0.01:
					push_warning("[GraphSolver] Room '%s' position mismatch between paths (%s vs %s); keeping first." % [next_id, existing, computed])
			else:
				positions[next_id] = computed
				queue.push_back(next_id)

	# Emit room pieces. Duplicate the RoomDef so the per-piece quantized size
	# doesn't leak into the shared template (which would mutate state across
	# rebuilds and break level previews that reuse the same RoomDef).
	for id: StringName in positions.keys():
		var node: RoomNode = nodes[id]
		var piece := LevelPiece.new()
		piece.position = positions[id]
		var room_for_piece: RoomDef = node.room
		if grid_size > 0.0:
			room_for_piece = node.room.duplicate()
			room_for_piece.size = quantized_size[id]
			room_for_piece.opening_width = quantized_opening[id]
		piece.room = room_for_piece
		piece.enemy_positions = node.enemy_positions
		# Per-instance id from the graph node, NOT the RoomDef. Lets a generator
		# reuse one RoomDef template across many distinct pieces without
		# colliding on slot/door registration keys.
		piece.room_id = node.id
		piece.additional_slots = node.additional_slots
		piece.enemy_level_range = node.enemy_level_range
		piece.theme_override = node.theme_override
		piece.enemy_count_override = node.enemy_count_override
		piece.pack_chance_override = node.pack_chance_override
		pieces.append(piece)

	# Emit corridor pieces (one per valid connection between two placed rooms).
	# CorridorDef is duplicated so the solver-set axis doesn't leak back into a
	# resource shared with other connections.
	for c: Connection in graph.connections:
		if c == null or c.corridor == null:
			continue
		if not (positions.has(c.from_room) and positions.has(c.to_room)):
			continue
		if not _are_opposite(c.from_wall, c.to_wall):
			continue

		var dir := _outward_dir(c.from_wall)
		var from_along := _size_along(quantized_size[c.from_room], c.from_wall)
		var corridor_len := _snap_scalar(c.corridor.length, grid_size)
		var corridor_center: Vector3 = positions[c.from_room] + dir * (from_along * 0.5 + corridor_len * 0.5)

		var corridor_copy: CorridorDef = c.corridor.duplicate()
		corridor_copy.axis = _axis_for_wall(c.from_wall)
		corridor_copy.length = corridor_len
		# Sync corridor.width to the connecting rooms' opening_width so the
		# corridor walls extend the door jamb lines exactly — eliminates the
		# perpendicular-offset class of misalignment at door/corridor joins.
		# If the two rooms disagree on opening_width, take the smaller so we
		# don't punch past either door's jamb.
		corridor_copy.width = minf(quantized_opening[c.from_room], quantized_opening[c.to_room])

		var piece := LevelPiece.new()
		piece.position = corridor_center
		piece.corridor = corridor_copy
		piece.enemy_count_override = c.enemy_count_override
		pieces.append(piece)

	# Unreachable rooms — declared in graph.rooms but no path from anchor.
	for id: StringName in nodes.keys():
		if not positions.has(id):
			push_warning("[GraphSolver] Room '%s' is not reachable from anchor '%s'." % [id, graph.anchor_id])

	_warn_on_overlaps(positions, quantized_size)

	return pieces


static func _snap_scalar(v: float, grid: float) -> float:
	if grid <= 0.0:
		return v
	return maxf(grid, round(v / grid) * grid)


static func _snap_vec2(v: Vector2, grid: float) -> Vector2:
	if grid <= 0.0:
		return v
	return Vector2(_snap_scalar(v.x, grid), _snap_scalar(v.y, grid))


# ── Helpers ──────────────────────────────────────────────────────────────

static func _are_opposite(a: RoomDef.Wall, b: RoomDef.Wall) -> bool:
	return (a == RoomDef.Wall.NORTH and b == RoomDef.Wall.SOUTH) \
		or (a == RoomDef.Wall.SOUTH and b == RoomDef.Wall.NORTH) \
		or (a == RoomDef.Wall.EAST  and b == RoomDef.Wall.WEST) \
		or (a == RoomDef.Wall.WEST  and b == RoomDef.Wall.EAST)


# Outward unit vector from room centre to the named wall. Matches the
# coordinate convention used by LevelBuilder/WallBuilder:
#   NORTH = -Z, SOUTH = +Z, EAST = +X, WEST = -X.
static func _outward_dir(wall: RoomDef.Wall) -> Vector3:
	if wall == RoomDef.Wall.NORTH: return Vector3(0, 0, -1)
	if wall == RoomDef.Wall.SOUTH: return Vector3(0, 0,  1)
	if wall == RoomDef.Wall.EAST:  return Vector3( 1, 0,  0)
	if wall == RoomDef.Wall.WEST:  return Vector3(-1, 0,  0)
	return Vector3.ZERO


# Room dimension perpendicular to the named wall. NORTH/SOUTH walls span X,
# so the perpendicular is size.y (Z-depth); EAST/WEST walls span Z, so the
# perpendicular is size.x (X-width).
static func _size_along(size: Vector2, wall: RoomDef.Wall) -> float:
	if wall == RoomDef.Wall.NORTH or wall == RoomDef.Wall.SOUTH:
		return size.y
	return size.x


static func _axis_for_wall(wall: RoomDef.Wall) -> CorridorDef.Axis:
	if wall == RoomDef.Wall.NORTH or wall == RoomDef.Wall.SOUTH:
		return CorridorDef.Axis.Z
	return CorridorDef.Axis.X


# O(n²) AABB overlap check using the post-quantization sizes (so the check
# reflects what the builder will actually emit, not the authored sizes).
# Acceptable for n in the dozens; if a level grows to hundreds of rooms,
# switch to a spatial bucket.
static func _warn_on_overlaps(positions: Dictionary, quantized_size: Dictionary) -> void:
	var ids: Array = positions.keys()
	for i in ids.size():
		var a_id: StringName = ids[i]
		var a_pos: Vector3 = positions[a_id]
		var a_sz: Vector2 = quantized_size[a_id]
		var a_hx := a_sz.x * 0.5
		var a_hz := a_sz.y * 0.5
		for j in range(i + 1, ids.size()):
			var b_id: StringName = ids[j]
			var b_pos: Vector3 = positions[b_id]
			var b_sz: Vector2 = quantized_size[b_id]
			var b_hx := b_sz.x * 0.5
			var b_hz := b_sz.y * 0.5
			var dx := absf(a_pos.x - b_pos.x)
			var dz := absf(a_pos.z - b_pos.z)
			if dx < a_hx + b_hx and dz < a_hz + b_hz:
				push_warning("[GraphSolver] Rooms '%s' and '%s' overlap." % [a_id, b_id])
