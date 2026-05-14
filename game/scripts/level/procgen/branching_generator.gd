extends LevelGenerator
class_name BranchingGenerator
## East-going chain with optional 1-N room branches off junction rooms.
## Builds on LinearGenerator's structure: walks east, but at each interior
## step there's `branch_chance` probability of swapping the linear template
## for a junction (T pointing N or S) and dangling a multi-room branch off
## the junction's perpendicular opening.
##
## Required template roles:
##   start            — single EAST opening (anchor room)
##   linear           — WEST + EAST openings (through-traffic)
##   end              — single WEST opening (terminus)
##   junction_t_south — WEST + EAST + SOUTH (T pointing south)
##   junction_t_north — WEST + EAST + NORTH (T pointing north)
##   branch_linear_ns — NORTH + SOUTH openings (through-traffic in branches)
##   branch_north     — single NORTH opening (terminator south of t_south junction)
##   branch_south     — single SOUTH opening (terminator north of t_north junction)
## If a junction or matching branch isn't available, the step degrades to
## a plain linear template — the level still builds.
##
## RoomNode ids: r0..r{length-1} for the main chain, b1..bN for branch rooms
## across all branches. Connection ids: c0..c{length-2} for the chain,
## bc1..bcN for branch connections. One switch slot is added per branch
## *terminator* (deepest room in a branch), not per branch room — so deeper
## branches mean more rooms to clear before reaching the same one switch.
##
## Optional puzzle emission: when emit_switch_puzzle is true and at least
## one branch was placed, the final connection (c{length-2} → end room)
## becomes a locked door, a switch slot is added to each branch *terminator*
## (additional_slots, not RoomDef.slots), and a SwitchDoorPuzzle linking
## them is appended to the graph.

const _SWITCH_SCENE: PackedScene = preload("res://scenes/prototype/prototype_switch.tscn")
const _LOOT_CRATE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_loot_crate.tscn")

@export var templates: Array[RoomTemplate] = []
## Pool of corridors used for chain (and, when branch_corridor_pool is
## empty, branch) connections. Each connection picks one uniformly at
## random — populate the pool with several variants for visual variety.
@export var corridor_pool: Array[CorridorDef] = []
## Optional separate pool for branch connections. Empty = use corridor_pool.
@export var branch_corridor_pool: Array[CorridorDef] = []
@export_range(2, 64) var min_length: int = 5
@export_range(2, 64) var max_length: int = 8
## Probability per interior step of becoming a junction with a branch.
@export_range(0.0, 1.0) var branch_chance: float = 0.4
## Branch depth = total rooms in a branch (terminator counts; depth=1 is a
## single-room dead-end, depth=3 is two through-rooms + a terminator).
@export_range(1, 16) var min_branch_depth: int = 1
@export_range(1, 16) var max_branch_depth: int = 3
@export var anchor_position: Vector3 = Vector3.ZERO
## When true, emit a SwitchDoorPuzzle locking the final connection with one
## switch per branch *terminator*. Skipped when no branches were placed
## (would leave a locked door with no way to unlock it).
@export var emit_switch_puzzle: bool = true
## When true, drop a loot crate at every branch terminator — exploration
## reward for clearing the deep dive.
@export var place_loot_at_branches: bool = true
## Extra enemies spawned in the boss arena alongside the boss itself.
## 0 = boss alone (template default). 2-3 gives the boss minions and a
## chunkier climactic fight.
@export_range(0, 8) var boss_arena_minions: int = 0
## Per chain interior room, probability of becoming a "lair" room with
## extra enemies. 0 = never (current behaviour); 0.2-0.3 sprinkles
## occasional encounter spikes.
@export_range(0.0, 1.0) var packed_room_chance: float = 0.0
## Per-connection probability of placing a door. Rolled after the connection
## is created; skipped when has_door is already true (puzzle-locked doors).
## 0 = no random doors; 0.85 = most rooms get doors.
@export_range(0.0, 1.0) var door_chance: float = 0.0
## Number of additional enemies added to a packed lair room on top of
## the template's default enemy_count.
@export_range(1, 8) var packed_room_extra_enemies: int = 2
## Per-branch probability of locking the branch's entrance behind a
## ClearRoomPuzzle on the junction room. Player has to clear the chain
## enemies in the junction before they can explore the branch for switches
## and loot. 0 = never lock; 1 = always.
@export_range(0.0, 1.0) var lock_branch_with_clear_chance: float = 0.5

@export_group("Theming")
## Optional theme applied to the boss arena (end room). Null = use the
## layout default. Lets the climactic room read as a distinct zone.
@export var end_theme: LevelTheme
## Optional theme applied to every branch room (linear interiors and
## terminators). Null = use the layout default. Lets side branches read
## as a distinct zone.
@export var branch_theme: LevelTheme
## Optional themes distributed across chain "acts". When non-empty, chain
## interior rooms (r1..r{length-2}) are evenly split into N sections (N =
## chain_themes.size()) and each room takes its section's theme. Empty
## means the whole chain uses layout default. Boss arena still uses
## end_theme; branches still use branch_theme.
@export var chain_themes: Array[LevelTheme] = []

# Counter for branch room ids across all branches in this generation pass.
var _branch_counter: int = 0
# Branch terminator ids collected during generation; used by the puzzle
# emitter to know where switches go.
var _branch_terminator_ids: Array[StringName] = []


func generate() -> LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else int(Time.get_unix_time_from_system())

	var length := rng.randi_range(min_length, max_length)
	if length < 2:
		push_error("[BranchingGenerator] length must be >= 2.")
		return null
	if corridor_pool.is_empty():
		push_error("[BranchingGenerator] corridor_pool is empty.")
		return null

	var start_t := LevelGenerator.pick_by_role(templates, &"start", rng)
	var end_t := LevelGenerator.pick_by_role(templates, &"end", rng)
	if start_t == null or end_t == null:
		push_error("[BranchingGenerator] template pool needs role='start' and role='end'.")
		return null

	# Reset per-generation state — Resources can be invoked multiple times.
	_branch_counter = 0
	_branch_terminator_ids.clear()

	var graph := LevelGraph.new()
	graph.anchor_id = &"r0"

	# Anchor
	var start_node := RoomNode.new()
	start_node.id = &"r0"
	start_node.room = start_t.room
	start_node.position = anchor_position
	graph.rooms.append(start_node)

	# Interior chain
	for i in range(1, length - 1):
		var current_id := StringName("r%d" % i)
		var prev_id := StringName("r%d" % (i - 1))

		var t: RoomTemplate
		var junction_dir: StringName = &""
		if rng.randf() < branch_chance:
			junction_dir = &"t_south" if rng.randi() % 2 == 0 else &"t_north"
			t = LevelGenerator.pick_by_role(templates, StringName("junction_%s" % junction_dir), rng)
			if t == null:
				junction_dir = &""
		if t == null:
			t = LevelGenerator.pick_by_role(templates, &"linear", rng)
		if t == null:
			push_error("[BranchingGenerator] no template available for interior step %d." % i)
			return null

		var node := RoomNode.new()
		node.id = current_id
		node.room = t.room
		# Difficulty: linear scale by chain index + NG+ zone offset. Lobby
		# (r0) carries no enemies (start template defines none), so r1 is the
		# first combat room. NG+0 starts at (1,2); each NG+ shifts +2.
		var zoff := PlayerState.zone_level_offset()
		node.enemy_level_range = Vector2i(i + zoff, i + 1 + zoff)
		# Occasional "lair" rooms — bumps enemy density on the chosen
		# template without authoring a separate dense template variant.
		if rng.randf() < packed_room_chance:
			node.enemy_count_override = t.room.enemy_count + packed_room_extra_enemies
		# Per-section theming: distribute interior chain rooms across
		# chain_themes. Interior count = length - 2 (excluding r0 + end);
		# index inside that range = i - 1.
		if not chain_themes.is_empty():
			var interior_count := length - 2
			@warning_ignore("integer_division")
			var section_idx := (i - 1) * chain_themes.size() / maxi(interior_count, 1)
			section_idx = clampi(section_idx, 0, chain_themes.size() - 1)
			node.theme_override = chain_themes[section_idx]
		graph.rooms.append(node)

		# Main east-going connection
		var c := Connection.new()
		c.id = StringName("c%d" % (i - 1))
		c.from_room = prev_id
		c.from_wall = RoomDef.Wall.EAST
		c.to_room = current_id
		c.to_wall = RoomDef.Wall.WEST
		c.corridor = _pick_corridor(rng, false)
		# c0 is the start-room → r1 connection; lock it behind the spawn-
		# room loot chest. The room template carries the chest slot, so
		# we just need a door here + a puzzle wiring the two.
		if i == 1:
			c.has_door = true
		if not c.has_door and rng.randf() < door_chance:
			c.has_door = true
		graph.connections.append(c)
		if i == 1:
			_emit_starter_chest_puzzle(graph, c)

		if junction_dir != &"":
			var junction_wall: RoomDef.Wall
			var terminator_role: StringName
			var terminator_wall: RoomDef.Wall
			if junction_dir == &"t_south":
				junction_wall = RoomDef.Wall.SOUTH
				terminator_role = &"branch_north"
				terminator_wall = RoomDef.Wall.NORTH
			else:
				junction_wall = RoomDef.Wall.NORTH
				terminator_role = &"branch_south"
				terminator_wall = RoomDef.Wall.SOUTH
			var depth := rng.randi_range(min_branch_depth, max_branch_depth)
			# Branches sit one chain step "off-axis"; difficulty scales from
			# the junction's depth + 1 (a small bonus for the side dive).
			_add_branch(graph, current_id, junction_wall, terminator_role, terminator_wall, depth, rng, i + 1)

	# End room + final connection
	var end_id := StringName("r%d" % (length - 1))
	var end_node := RoomNode.new()
	end_node.id = end_id
	end_node.room = end_t.room
	# Boss arena tops out the difficulty band — slightly above the last
	# linear chain room so the climactic fight feels appropriately stiff.
	var zoff_end := PlayerState.zone_level_offset()
	end_node.enemy_level_range = Vector2i(length + zoff_end, length + 1 + zoff_end)
	end_node.theme_override = end_theme  # null is fine — falls through to layout default
	if boss_arena_minions > 0:
		end_node.enemy_count_override = boss_arena_minions
	graph.rooms.append(end_node)

	var final_c := Connection.new()
	final_c.id = StringName("c%d" % (length - 2))
	final_c.from_room = StringName("r%d" % (length - 2))
	final_c.from_wall = RoomDef.Wall.EAST
	final_c.to_room = end_id
	final_c.to_wall = RoomDef.Wall.WEST
	final_c.corridor = _pick_corridor(rng, false)
	if not final_c.has_door and rng.randf() < door_chance:
		final_c.has_door = true
	graph.connections.append(final_c)

	if emit_switch_puzzle and not _branch_terminator_ids.is_empty():
		_emit_switch_puzzle(graph, final_c)

	return graph


# Walks a branch from `junction_id` outward, placing `depth-1` linear
# branch rooms followed by a terminator. Updates _branch_counter and
# appends the final terminator id to _branch_terminator_ids. If no
# linear branch template is available, falls back to a single-room
# branch (terminator only). If no terminator template is available,
# the entire branch is dropped — leaves the junction's perpendicular
# opening as a doorway to nowhere (acceptable; designer can iterate).
func _add_branch(graph: LevelGraph, junction_id: StringName, junction_wall: RoomDef.Wall,
		terminator_role: StringName, terminator_wall: RoomDef.Wall,
		depth: int, rng: RandomNumberGenerator,
		base_level: int) -> void:
	var current_id := junction_id
	var current_outgoing_wall := junction_wall
	# First connection off the junction — captured so we can optionally lock
	# it behind a ClearRoomPuzzle on the junction.
	var entrance_conn: Connection = null

	# Linear interior — depth-1 rooms with through-N+S openings.
	for d in depth - 1:
		var t := LevelGenerator.pick_by_role(templates, &"branch_linear_ns", rng)
		if t == null:
			break
		_branch_counter += 1
		var b_id := StringName("b%d" % _branch_counter)
		var b_node := RoomNode.new()
		b_node.id = b_id
		b_node.room = t.room
		var zoff_b := PlayerState.zone_level_offset()
		b_node.enemy_level_range = Vector2i(base_level + zoff_b, base_level + 1 + zoff_b)
		b_node.theme_override = branch_theme
		graph.rooms.append(b_node)

		var bc := Connection.new()
		bc.id = StringName("bc%d" % _branch_counter)
		bc.from_room = current_id
		bc.from_wall = current_outgoing_wall
		bc.to_room = b_id
		bc.to_wall = _opposite_wall(current_outgoing_wall)
		bc.corridor = _pick_corridor(rng, true)
		if not bc.has_door and rng.randf() < door_chance:
			bc.has_door = true
		graph.connections.append(bc)
		if entrance_conn == null:
			entrance_conn = bc

		current_id = b_id
		# `current_outgoing_wall` unchanged — branch keeps going same direction.

	# Terminator
	var term_t := LevelGenerator.pick_by_role(templates, terminator_role, rng)
	if term_t == null:
		# No terminator template — drop the whole branch.
		return
	_branch_counter += 1
	var term_id := StringName("b%d" % _branch_counter)
	var term_node := RoomNode.new()
	term_node.id = term_id
	term_node.room = term_t.room
	# Terminator slightly stiffer than the rest of the branch — payoff fight.
	var zoff_t := PlayerState.zone_level_offset()
	term_node.enemy_level_range = Vector2i(base_level + 1 + zoff_t, base_level + 2 + zoff_t)
	term_node.theme_override = branch_theme
	if place_loot_at_branches:
		var loot_slot := InteractableSlot.new()
		loot_slot.id = &"loot"
		loot_slot.scene = _LOOT_CRATE_SCENE
		loot_slot.offset = Vector3(1, 0.3, 0)
		term_node.additional_slots.append(loot_slot)
	graph.rooms.append(term_node)

	var tc := Connection.new()
	tc.id = StringName("bc%d" % _branch_counter)
	tc.from_room = current_id
	tc.from_wall = current_outgoing_wall
	tc.to_room = term_id
	tc.to_wall = terminator_wall
	tc.corridor = _pick_corridor(rng, true)
	if not tc.has_door and rng.randf() < door_chance:
		tc.has_door = true
	graph.connections.append(tc)
	if entrance_conn == null:
		entrance_conn = tc

	_branch_terminator_ids.append(term_id)

	# Optional: lock the branch entrance behind clearing the junction. The
	# junction sits in the chain so the player will encounter its enemies
	# anyway — this just gates branch exploration on finishing that fight.
	if entrance_conn != null and rng.randf() < lock_branch_with_clear_chance:
		entrance_conn.has_door = true
		var puzzle := ClearRoomPuzzle.new()
		puzzle.room_id = junction_id
		puzzle.door_connection_id = entrance_conn.id
		graph.puzzles.append(puzzle)


# Lock the final connection's door behind one switch per branch terminator.
# Switches go on the deepest room of each branch via additional_slots so
# the player has to traverse the full branch depth to grab them.
func _emit_switch_puzzle(graph: LevelGraph, final_c: Connection) -> void:
	final_c.has_door = true

	var switch_slot_ids: Array[StringName] = []
	for term_id in _branch_terminator_ids:
		for node: RoomNode in graph.rooms:
			if node.id != term_id:
				continue
			var slot := InteractableSlot.new()
			slot.id = &"sw_main"
			slot.scene = _SWITCH_SCENE
			# West-of-centre so it doesn't overlap a loot crate placed at +1.
			slot.offset = Vector3(-1, 0.7, 0)
			node.additional_slots.append(slot)
			switch_slot_ids.append(StringName("%s.sw_main" % term_id))
			break

	if switch_slot_ids.is_empty():
		return

	var puzzle := SwitchDoorPuzzle.new()
	puzzle.switch_slot_ids = switch_slot_ids
	puzzle.door_connection_id = final_c.id
	puzzle.required_count = 0  # all
	graph.puzzles.append(puzzle)


# Lock the spawn-room exit behind opening the starter_chest. The chest
# slot is baked into the start-room template (proto_start_room.tres);
# the puzzle just wires it to the door + forces the starter weapon kit.
func _emit_starter_chest_puzzle(graph: LevelGraph, first_c: Connection) -> void:
	var puzzle := LootCrateDoorPuzzle.new()
	puzzle.crate_slot_id = StringName("%s.starter_chest" % graph.anchor_id)
	puzzle.door_connection_id = first_c.id
	puzzle.force_starter_kit = true
	graph.puzzles.append(puzzle)


# Uniform random pick from corridor_pool (or branch_corridor_pool when
# prefer_branch and that pool is non-empty). Chain pool was validated
# non-empty at the start of generate(); branch pool may legitimately be
# empty (means "share the chain pool"), so we fall back here.
func _pick_corridor(rng: RandomNumberGenerator, prefer_branch: bool) -> CorridorDef:
	var pool: Array[CorridorDef] = corridor_pool
	if prefer_branch and not branch_corridor_pool.is_empty():
		pool = branch_corridor_pool
	return pool[rng.randi() % pool.size()]


static func _opposite_wall(wall: RoomDef.Wall) -> RoomDef.Wall:
	if wall == RoomDef.Wall.NORTH: return RoomDef.Wall.SOUTH
	if wall == RoomDef.Wall.SOUTH: return RoomDef.Wall.NORTH
	if wall == RoomDef.Wall.EAST:  return RoomDef.Wall.WEST
	return RoomDef.Wall.EAST
