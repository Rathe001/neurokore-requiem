extends LevelGenerator
class_name GridGenerator
## 2D-grid layout — fills every cell in a `grid_width × grid_height` grid
## with a room and connects every adjacent pair. Picks templates by
## opening-set match (`LevelGenerator.pick_by_openings`) so designers can
## supply multiple variants per shape for variety. Produces non-tree
## topologies — multiple paths between any two rooms — which exercises
## the GraphSolver's cycle handling (BFS verifies that a room reached
## from two paths agrees on its position).
##
## Coordinate convention:
##   - cell (0, 0) is the NW corner (north = -Z, west = -X)
##   - cell.x increases going east, cell.y increases going south
##   - anchor is placed at cell (0, 0); player_spawn slot is added to
##     that RoomNode via additional_slots
##
## Required template shapes (an exact opening match is required per cell):
##   corners   — NE, NW, SE, SW (2 openings)
##   T-junctions — NSE, NSW, NEW, SEW (3 openings)
##   cross     — NSEW (4 openings, interior cells)
## Designer-authored templates with weights determine variety within
## each shape. v1 keeps grids dense (every cell filled); sparse grids
## with 1-opening terminators and 2-opening straights are a follow-up.

const _PLAYER_SPAWN_SCENE: PackedScene = preload("res://scenes/prototype/prototype_player_spawn.tscn")
const _BOSS_SPAWN_SCENE: PackedScene = preload("res://scenes/prototype/prototype_boss_spawn.tscn")
const _EXIT_SCENE: PackedScene = preload("res://scenes/prototype/prototype_exit.tscn")
const _SWITCH_SCENE: PackedScene = preload("res://scenes/prototype/prototype_switch.tscn")

const _UNSET_CELL := Vector2i(-1, -1)

@export var templates: Array[RoomTemplate] = []
@export var corridor_pool: Array[CorridorDef] = []
@export_range(1, 16) var grid_width: int = 3
@export_range(1, 16) var grid_height: int = 3
@export var anchor_position: Vector3 = Vector3.ZERO

@export_group("Boss + Exit")
## Cell that gets a boss spawn marker via additional_slots. (-1,-1) = unset.
@export var boss_cell: Vector2i = _UNSET_CELL
## Cell that gets an exit pad. Auto-unlocks on boss death (PrototypeExit
## joins the &"boss_listeners" group). (-1,-1) = unset.
@export var exit_cell: Vector2i = _UNSET_CELL
## When set, the boss cell uses this enemy level band instead of (0,0).
## Lets the boss arena spawn a stiffer fight independent of grid depth.
@export var boss_level_range: Vector2i = Vector2i(3, 4)

@export_group("Procedural Puzzle")
## When true, lock the first connection out of the boss cell behind a
## SwitchDoorPuzzle whose switches sit in random non-special cells.
## Skipped when boss_cell is unset (nothing to lock).
@export var emit_switch_puzzle: bool = false
## Number of switch slots to scatter when emit_switch_puzzle is true.
## Cells are picked randomly from non-spawn / non-boss / non-exit cells.
@export_range(1, 16) var switch_count: int = 2


func generate() -> LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else int(Time.get_unix_time_from_system())

	if templates.is_empty():
		push_error("[GridGenerator] templates is empty.")
		return null
	if corridor_pool.is_empty():
		push_error("[GridGenerator] corridor_pool is empty.")
		return null
	if grid_width < 1 or grid_height < 1:
		push_error("[GridGenerator] grid_width/grid_height must be >= 1.")
		return null

	var graph := LevelGraph.new()
	graph.anchor_id = _cell_id(0, 0)

	# v1: every cell occupied.
	var occupied: Dictionary = {}
	for x in grid_width:
		for y in grid_height:
			occupied[Vector2i(x, y)] = true

	# Pass 1 — pick a template per cell based on neighbor occupancy.
	var cell_to_node: Dictionary = {}  # Vector2i → RoomNode (we keep the ref
	                                    # so puzzle emission can mutate it later)
	for cell: Vector2i in occupied.keys():
		var ops := _openings_for(cell, occupied)
		var t := LevelGenerator.pick_by_openings(templates, ops, rng)
		if t == null:
			push_error("[GridGenerator] no template matches openings %s for cell %s — author a RoomDef with that exact opening set." % [ops, cell])
			return null

		var node := RoomNode.new()
		node.id = _cell_id(cell.x, cell.y)
		node.room = t.room
		if cell == Vector2i(0, 0):
			node.position = anchor_position
			# Anchor cell needs a player spawn marker. Added per-instance so the
			# template stays reusable elsewhere without baking it in.
			var spawn := InteractableSlot.new()
			spawn.id = &"player_spawn"
			spawn.scene = _PLAYER_SPAWN_SCENE
			node.additional_slots.append(spawn)
		if cell == boss_cell:
			node.enemy_level_range = boss_level_range
			var boss_slot := InteractableSlot.new()
			boss_slot.id = &"boss"
			boss_slot.scene = _BOSS_SPAWN_SCENE
			node.additional_slots.append(boss_slot)
		if cell == exit_cell:
			var exit_slot := InteractableSlot.new()
			exit_slot.id = &"exit"
			exit_slot.scene = _EXIT_SCENE
			# Offset so boss + exit don't overlap when assigned to the same cell.
			exit_slot.offset = Vector3(2.5, 0, 0) if cell == boss_cell else Vector3.ZERO
			node.additional_slots.append(exit_slot)
		graph.rooms.append(node)
		cell_to_node[cell] = node

	# Pick ONE corridor per axis up front. Cycles in a grid mean a room is
	# reached from two directions — its computed position must agree both
	# ways, which requires all east-going edges to share a length and all
	# south-going edges to share a length. (Per-edge random picks would
	# break this and trigger GraphSolver's position-mismatch warnings.)
	# Different lengths per axis are fine — they just stretch the grid
	# rectangularly.
	var east_corridor: CorridorDef = corridor_pool[rng.randi() % corridor_pool.size()]
	var south_corridor: CorridorDef = corridor_pool[rng.randi() % corridor_pool.size()]

	# Pass 2 — connections. Walk each cell, emit edges to its EAST and SOUTH
	# neighbors only (avoids duplicate edges since each pair is reached from
	# both sides). The solver handles the resulting cycles.
	var conn_idx := 0
	for cell: Vector2i in occupied.keys():
		var east := Vector2i(cell.x + 1, cell.y)
		if occupied.has(east):
			conn_idx += 1
			graph.connections.append(_make_connection(
				conn_idx, cell_to_node[cell].id, cell_to_node[east].id,
				RoomDef.Wall.EAST, RoomDef.Wall.WEST, east_corridor))
		var south := Vector2i(cell.x, cell.y + 1)
		if occupied.has(south):
			conn_idx += 1
			graph.connections.append(_make_connection(
				conn_idx, cell_to_node[cell].id, cell_to_node[south].id,
				RoomDef.Wall.SOUTH, RoomDef.Wall.NORTH, south_corridor))

	# Pass 3 — optional puzzle. Lock the first available connection out of
	# the boss cell behind a SwitchDoorPuzzle. Switches are placed via
	# additional_slots in random non-special cells.
	if emit_switch_puzzle and boss_cell != _UNSET_CELL and occupied.has(boss_cell):
		_emit_switch_puzzle(graph, occupied, cell_to_node, rng)

	return graph


# Locks EVERY connection touching the boss cell — corners have 2 entries
# and edge cells have 3, so locking just one would leave bypass routes.
# Each door gets its own switch puzzle with `switch_count` switches drawn
# from the shared pool of non-special cells. Each cell hosts at most one
# switch (slot id "sw_main"); cells consumed by one puzzle aren't reused
# by the next.
func _emit_switch_puzzle(graph: LevelGraph, occupied: Dictionary,
		cell_to_node: Dictionary, rng: RandomNumberGenerator) -> void:
	var boss_node_id: StringName = cell_to_node[boss_cell].id

	var boss_conns: Array[Connection] = []
	for c: Connection in graph.connections:
		if c.from_room == boss_node_id or c.to_room == boss_node_id:
			boss_conns.append(c)
	if boss_conns.is_empty():
		push_warning("[GridGenerator] boss cell has no connections — skipping switch puzzle.")
		return

	# Switch host pool: every non-special occupied cell. Shuffled with our
	# seeded rng (Array.shuffle would use Godot's global rng) so puzzle
	# placement is deterministic per seed.
	var pool: Array[Vector2i] = []
	for cell: Vector2i in occupied.keys():
		if cell == Vector2i(0, 0) or cell == boss_cell or cell == exit_cell:
			continue
		pool.append(cell)
	_shuffle_in_place(pool, rng)

	var pool_idx := 0
	for door_conn: Connection in boss_conns:
		var n: int = mini(switch_count, pool.size() - pool_idx)
		if n <= 0:
			push_warning("[GridGenerator] ran out of switch host cells; remaining boss connections stay unlocked.")
			return
		door_conn.has_door = true
		var switch_ids: Array[StringName] = []
		for i in n:
			var cell: Vector2i = pool[pool_idx]
			pool_idx += 1
			var node: RoomNode = cell_to_node[cell]
			var slot := InteractableSlot.new()
			slot.id = &"sw_main"
			slot.scene = _SWITCH_SCENE
			slot.offset = Vector3(0, 0.7, 0)
			node.additional_slots.append(slot)
			switch_ids.append(StringName("%s.sw_main" % node.id))

		var puzzle := SwitchDoorPuzzle.new()
		puzzle.switch_slot_ids = switch_ids
		puzzle.door_connection_id = door_conn.id
		puzzle.required_count = 0  # all
		graph.puzzles.append(puzzle)


# Fisher-Yates shuffle using the supplied rng so puzzle placement is
# fully deterministic per seed (Array.shuffle uses Godot's global rng).
static func _shuffle_in_place(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# Returns the canonical opening list for a cell based on which neighbors
# are occupied. Order = enum order (N=0, S=1, E=2, W=3), which is what
# the matching _opening_set_equals expects (set semantics — order
# doesn't matter, but consistency keeps iteration cheap).
static func _openings_for(cell: Vector2i, occupied: Dictionary) -> Array[RoomDef.Wall]:
	var ops: Array[RoomDef.Wall] = []
	if occupied.has(Vector2i(cell.x, cell.y - 1)):
		ops.append(RoomDef.Wall.NORTH)
	if occupied.has(Vector2i(cell.x, cell.y + 1)):
		ops.append(RoomDef.Wall.SOUTH)
	if occupied.has(Vector2i(cell.x + 1, cell.y)):
		ops.append(RoomDef.Wall.EAST)
	if occupied.has(Vector2i(cell.x - 1, cell.y)):
		ops.append(RoomDef.Wall.WEST)
	return ops


static func _cell_id(x: int, y: int) -> StringName:
	return StringName("r_%d_%d" % [x, y])


static func _make_connection(idx: int, from_id: StringName, to_id: StringName,
		from_wall: RoomDef.Wall, to_wall: RoomDef.Wall,
		corridor: CorridorDef) -> Connection:
	var c := Connection.new()
	c.id = StringName("c%d" % idx)
	c.from_room = from_id
	c.from_wall = from_wall
	c.to_room = to_id
	c.to_wall = to_wall
	c.corridor = corridor
	return c
