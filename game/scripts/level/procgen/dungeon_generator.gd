extends LevelGenerator
class_name DungeonGenerator
## D2-style sparse dungeon — carves a connected subset of a grid using a
## Growing Tree algorithm, producing maze-like topology with dead ends,
## winding corridors, and loops. The resulting LevelGraph flows through the
## existing GraphSolver → LevelBuilder pipeline unchanged.
##
## Growing Tree generalises DFS and Prim's via `newest_bias`:
##   1.0 = pure DFS (long snaking corridors)
##   0.0 = pure Prim's (branchy, open layouts)
##   0.6 = recommended for D2 feel (long corridors that branch unpredictably)
##
## Template matching uses opening-set match (`pick_by_openings`), same as
## GridGenerator. Required template shapes for a sparse grid:
##   dead ends   — N, S, E, W (1 opening)
##   straights   — NS, EW (2 openings, aligned)
##   corners     — NE, NW, SE, SW (2 openings, perpendicular)
##   T-junctions — 4 variants (3 openings)
##   cross       — NSEW (4 openings)
## That's 15 templates total covering every possible 1–4 opening combo.
##
## Per-axis corridor constraint holds (one corridor length for all east
## edges, one for all south edges) so cycles resolve cleanly in GraphSolver.

const _PLAYER_SPAWN_SCENE: PackedScene = preload("res://scenes/prototype/prototype_player_spawn.tscn")
const _BOSS_SPAWN_SCENE: PackedScene = preload("res://scenes/prototype/prototype_boss_spawn.tscn")
const _EXIT_SCENE: PackedScene = preload("res://scenes/prototype/prototype_exit.tscn")
const _SWITCH_SCENE: PackedScene = preload("res://scenes/prototype/prototype_switch.tscn")
const _LOOT_CRATE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_loot_crate.tscn")

const _DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]

@export var templates: Array[RoomTemplate] = []
@export var corridor_pool: Array[CorridorDef] = []
@export_range(3, 16) var grid_width: int = 7
@export_range(3, 16) var grid_height: int = 7
## Fill fraction range — the carve targets a random value between these.
## 0.40–0.55 on a 7×7 grid produces 20–27 rooms (D2 dungeon floor scale).
@export_range(0.2, 0.9) var fill_min: float = 0.40
@export_range(0.2, 0.9) var fill_max: float = 0.55
## Growing Tree selection bias. 1.0 = always pick newest (DFS — long snaking
## paths). 0.0 = always pick random (Prim's — branchy). 0.6 = D2 feel.
@export_range(0.0, 1.0) var newest_bias: float = 0.6
@export var anchor_position: Vector3 = Vector3.ZERO

@export_group("Boss + Exit")
## How to place the boss. "farthest" = BFS-farthest from spawn (default).
## "random_leaf" = random 1-opening dead end.
@export var boss_placement: StringName = &"farthest"
@export var emit_switch_puzzle: bool = true
@export_range(1, 16) var switch_count: int = 3

@export_group("Density")
## Per-opening-count enemy counts at full density. Actual counts are scaled
## down at low zone levels — see density_scale_min / density_full_at_zone_level.
@export_range(0, 16) var dead_end_enemies: int = 4
@export_range(0, 16) var passage_enemies: int = 4
@export_range(0, 16) var junction_enemies: int = 6
@export_range(0, 16) var hub_enemies: int = 8
## Per-piece pack chance at full density. -1.0 = use EnemySpawner.PACK_CHANCE.
## 0.18 = 3× default, giving ~40% chance per room of at least one pack.
@export var pack_chance: float = 0.18
## Density floor at zone_level_offset 0 (fresh L1 character, no NG+). Enemy
## counts and pack chance scale by this fraction at the start of the curve.
## 0.5 means a freshly-rolled character fights roughly half as many enemies
## per room as a deep-zone playthrough — first few floors should breathe.
@export_range(0.0, 1.0) var density_scale_min: float = 0.5
## Zone level offset at which density reaches full (1.0). Linear ramp from
## density_scale_min at offset 0 to 1.0 at this offset, then clamps. Default
## 9 = player level 10 (offset = player_level - 1) — by then the player has
## potions, gear, and DR to handle the mobs the layout was tuned around.
@export_range(1, 30) var density_full_at_zone_level: int = 9

@export_group("Theming")
@export var boss_theme: LevelTheme
@export var dead_end_theme: LevelTheme


func generate() -> LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed if rng_seed != 0 else int(Time.get_unix_time_from_system())

	if templates.is_empty():
		push_error("[DungeonGenerator] templates is empty.")
		return null
	if corridor_pool.is_empty():
		push_error("[DungeonGenerator] corridor_pool is empty.")
		return null

	var graph := LevelGraph.new()

	# ── Step 1: Growing Tree carve ─────────────────────────────────────────
	var total_cells := grid_width * grid_height
	var fill_frac := rng.randf_range(fill_min, fill_max)
	var target_count := clampi(int(round(total_cells * fill_frac)), 4, total_cells)

	var occupied: Dictionary = {}
	var frontier: Array[Vector2i] = []

	var start_cell := Vector2i(grid_width / 2, grid_height / 2)
	occupied[start_cell] = true
	frontier.append(start_cell)

	while frontier.size() > 0 and occupied.size() < target_count:
		var idx: int
		if rng.randf() < newest_bias:
			idx = frontier.size() - 1
		else:
			idx = rng.randi() % frontier.size()

		var cell := frontier[idx]
		var neighbors := _unoccupied_neighbors(cell, occupied)

		if neighbors.is_empty():
			frontier.remove_at(idx)
			continue

		var next: Vector2i = neighbors[rng.randi() % neighbors.size()]
		occupied[next] = true
		frontier.append(next)

	# ── Step 1b: Pick a dead-end leaf as spawn ────────────────────────────
	# The carve origin (grid center) typically has multiple exits, putting
	# the player at a busy intersection. Instead, pick a random 1-opening
	# leaf so the player spawns in a quiet cul-de-sac with a single door.
	var leaves: Array[Vector2i] = []
	for cell: Vector2i in occupied.keys():
		if GridGenerator._openings_for(cell, occupied).size() == 1:
			leaves.append(cell)
	if not leaves.is_empty():
		start_cell = leaves[rng.randi() % leaves.size()]

	# ── Step 2: BFS distances for difficulty scaling + boss placement ──────
	var distances := _bfs_distances(start_cell, occupied)
	var boss_cell := _pick_boss_cell(occupied, distances, rng)
	var exit_cell := boss_cell

	# Anchor = start cell.
	graph.anchor_id = GridGenerator._cell_id(start_cell.x, start_cell.y)

	# ── Step 3: Pick templates + build RoomNodes ───────────────────────────
	var zoff := PlayerState.zone_level_offset()
	# Density is gated by zone level — fresh L1 characters fight a fraction
	# of the full mob count so early floors are approachable, scaling up to
	# 1.0 around player level 10. See exports for the curve parameters.
	var density_scale := _compute_density_scale(zoff)
	var cell_to_node: Dictionary = {}

	for cell: Vector2i in occupied.keys():
		var ops := GridGenerator._openings_for(cell, occupied)
		var t := LevelGenerator.pick_by_openings(templates, ops, rng)
		if t == null:
			push_error("[DungeonGenerator] no template matches openings %s for cell %s." % [ops, cell])
			return null

		var node := RoomNode.new()
		node.id = GridGenerator._cell_id(cell.x, cell.y)
		node.room = t.room

		# Density override by opening count, scaled to zone level.
		var opening_count := ops.size()
		node.enemy_count_override = maxi(0, int(round(float(_enemies_for_openings(opening_count)) * density_scale)))

		# Pack chance override, scaled to zone level.
		if pack_chance >= 0.0:
			node.pack_chance_override = pack_chance * density_scale

		# Difficulty scales with BFS distance from spawn.
		var dist: int = distances.get(cell, 0)
		node.enemy_level_range = Vector2i(dist + zoff, dist + 1 + zoff)

		# Theme: dead ends get optional dead_end_theme.
		if opening_count == 1 and dead_end_theme != null:
			node.theme_override = dead_end_theme

		# Anchor (player spawn).
		if cell == start_cell:
			node.position = anchor_position
			node.enemy_count_override = 0  # safe room
			var spawn := InteractableSlot.new()
			spawn.id = &"player_spawn"
			spawn.scene = _PLAYER_SPAWN_SCENE
			node.additional_slots.append(spawn)
			# Starter chest — gives the player a weapon before they leave.
			# No door-gating (maze has multiple exits); NG+ skip is handled
			# by the crate itself (starter_weapon_kit only rolls on first run).
			if PlayerState.new_game_plus == 0:
				var chest := InteractableSlot.new()
				chest.id = &"starter_chest"
				chest.scene = _LOOT_CRATE_SCENE
				chest.offset = Vector3(-1.5, 0.3, 1.5)
				node.additional_slots.append(chest)

		# Boss cell.
		if cell == boss_cell:
			node.enemy_level_range = Vector2i(dist + 1 + zoff, dist + 2 + zoff)
			if boss_theme != null:
				node.theme_override = boss_theme
			var boss_slot := InteractableSlot.new()
			boss_slot.id = &"boss"
			boss_slot.scene = _BOSS_SPAWN_SCENE
			node.additional_slots.append(boss_slot)

		# Exit (co-located with boss).
		if cell == exit_cell:
			var exit_slot := InteractableSlot.new()
			exit_slot.id = &"exit"
			exit_slot.scene = _EXIT_SCENE
			exit_slot.offset = Vector3(2.5, 0, 0) if cell == boss_cell else Vector3.ZERO
			node.additional_slots.append(exit_slot)

		graph.rooms.append(node)
		cell_to_node[cell] = node

	# ── Step 4: Connections (per-axis corridor constraint) ─────────────────
	var east_corridor: CorridorDef = corridor_pool[rng.randi() % corridor_pool.size()]
	var south_corridor: CorridorDef = corridor_pool[rng.randi() % corridor_pool.size()]

	var conn_idx := 0
	for cell: Vector2i in occupied.keys():
		var east := Vector2i(cell.x + 1, cell.y)
		if occupied.has(east):
			conn_idx += 1
			var c_east := GridGenerator._make_connection(
				conn_idx, cell_to_node[cell].id, cell_to_node[east].id,
				RoomDef.Wall.EAST, RoomDef.Wall.WEST, east_corridor)
			if cell == start_cell or east == start_cell:
				c_east.enemy_count_override = 0
				c_east.has_door = true
			graph.connections.append(c_east)
		var south := Vector2i(cell.x, cell.y + 1)
		if occupied.has(south):
			conn_idx += 1
			var c_south := GridGenerator._make_connection(
				conn_idx, cell_to_node[cell].id, cell_to_node[south].id,
				RoomDef.Wall.SOUTH, RoomDef.Wall.NORTH, south_corridor)
			if cell == start_cell or south == start_cell:
				c_south.enemy_count_override = 0
				c_south.has_door = true
			graph.connections.append(c_south)

	# ── Step 5: Optional switch puzzle on boss connections ─────────────────
	if emit_switch_puzzle and boss_cell != Vector2i(-1, -1):
		_emit_switch_puzzle(graph, occupied, cell_to_node, start_cell, boss_cell, exit_cell, rng)

	# ── Step 6: Starter chest in spawn room ────────────────────────────────
	if PlayerState.new_game_plus == 0:
		var chest_puzzle := LootCrateDoorPuzzle.new()
		chest_puzzle.crate_slot_id = StringName("%s.starter_chest" % graph.anchor_id)
		chest_puzzle.force_starter_kit = true
		graph.puzzles.append(chest_puzzle)

	return graph


# ── Helpers ────────────────────────────────────────────────────────────────

func _unoccupied_neighbors(cell: Vector2i, occupied: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir: Vector2i in _DIRS:
		var n := cell + dir
		if n.x >= 0 and n.x < grid_width and n.y >= 0 and n.y < grid_height:
			if not occupied.has(n):
				result.append(n)
	return result


func _bfs_distances(start: Vector2i, occupied: Dictionary) -> Dictionary:
	var dist: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	dist[start] = 0
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for dir: Vector2i in _DIRS:
			var n := cell + dir
			if occupied.has(n) and not dist.has(n):
				dist[n] = dist[cell] + 1
				queue.append(n)
	return dist


func _pick_boss_cell(occupied: Dictionary, distances: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	if boss_placement == &"random_leaf":
		var leaves: Array[Vector2i] = []
		for cell: Vector2i in occupied.keys():
			if GridGenerator._openings_for(cell, occupied).size() == 1:
				leaves.append(cell)
		if not leaves.is_empty():
			return leaves[rng.randi() % leaves.size()]
	# Default / fallback: farthest from spawn.
	var best := Vector2i.ZERO
	var best_dist := -1
	for cell: Vector2i in distances.keys():
		if int(distances[cell]) > best_dist:
			best_dist = int(distances[cell])
			best = cell
	return best


func _enemies_for_openings(count: int) -> int:
	match count:
		1: return dead_end_enemies
		2: return passage_enemies
		3: return junction_enemies
		4: return hub_enemies
		_: return 2


# Linear ramp from density_scale_min (at zone_level_offset 0) to 1.0
# (at density_full_at_zone_level). Used to dial mob counts and pack chance
# down on the player's first few floors — see exports for the rationale.
func _compute_density_scale(zone_level_offset: int) -> float:
	var target: float = maxf(1.0, float(density_full_at_zone_level))
	var t: float = clampf(float(zone_level_offset) / target, 0.0, 1.0)
	return density_scale_min + (1.0 - density_scale_min) * t


func _emit_switch_puzzle(graph: LevelGraph, occupied: Dictionary,
		cell_to_node: Dictionary, start_cell: Vector2i, p_boss_cell: Vector2i,
		p_exit_cell: Vector2i, rng: RandomNumberGenerator) -> void:
	var boss_node_id: StringName = cell_to_node[p_boss_cell].id

	var boss_conns: Array[Connection] = []
	for c: Connection in graph.connections:
		if c.from_room == boss_node_id or c.to_room == boss_node_id:
			boss_conns.append(c)
	if boss_conns.is_empty():
		push_warning("[DungeonGenerator] boss cell has no connections — skipping switch puzzle.")
		return

	var pool: Array[Vector2i] = []
	for cell: Vector2i in occupied.keys():
		if cell == start_cell or cell == p_boss_cell or cell == p_exit_cell:
			continue
		pool.append(cell)
	GridGenerator._shuffle_in_place(pool, rng)

	var pool_idx := 0
	for door_conn: Connection in boss_conns:
		var n: int = mini(switch_count, pool.size() - pool_idx)
		if n <= 0:
			push_warning("[DungeonGenerator] ran out of switch host cells.")
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
		puzzle.required_count = 0
		graph.puzzles.append(puzzle)
