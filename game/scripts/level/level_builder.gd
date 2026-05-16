extends Node3D
class_name LevelBuilder
## Orchestrator. Walks the assigned LevelLayout's pieces and dispatches each
## one to the appropriate builders under scripts/level/build/. Holds onto the
## BuildContext so post-build operations (door lookup, respawn) can reuse the
## same caches and registries.

@export var layout: LevelLayout

var _ctx: LevelBuildContext
# Resolved piece list. When layout.graph is set this is solved from the graph
# at build time; otherwise it's a direct reference to layout.pieces. Cached
# so post-build operations (respawn) iterate the same set the builder used.
var _pieces: Array[LevelPiece] = []


func _ready() -> void:
	if layout == null:
		push_warning("[LevelBuilder] No layout assigned.")
		return
	_apply_mp_seed()
	_build_level()
	_bake_navigation()
	_store_mp_seed()


# In MP, ensure both host and late joiners use the same seed. Host
# captures a deterministic seed before the first build; late joiners
# read it from lobby data so they generate identical geometry.
func _apply_mp_seed() -> void:
	if not NetState.is_in_lobby():
		return
	if layout == null or layout.generator == null:
		return
	if NetState.is_client():
		# Late joiner: read the seed the host stored in lobby data.
		var lobby_seed := NetState.get_level_seed()
		if lobby_seed != 0:
			layout.generator.rng_seed = lobby_seed
	else:
		# Host: if the resource seed is 0 (time-based fallback, seed would
		# be lost), pin it to a random value so it's capturable after build.
		if layout.generator.rng_seed == 0:
			layout.generator.rng_seed = randi()
			if layout.generator.rng_seed == 0:
				layout.generator.rng_seed = 1


func _store_mp_seed() -> void:
	if not NetState.is_in_lobby() or not NetState.is_host():
		return
	if layout == null or layout.generator == null:
		return
	NetState.set_level_seed(layout.generator.rng_seed)


# Tear down the current level and rebuild from scratch with a new seed
# (when the layout has a generator). PrototypeRoot.reset_level calls this
# on NG+ for generator-driven layouts so the player walks into a fresh
# layout instead of replaying the same one. Async because queue_free
# needs a frame to drain before we can re-add nodes safely.
func rebuild(new_seed: int = 0) -> void:
	if layout == null:
		return
	for child in get_children():
		child.queue_free()
	# One process frame for the queue_free chain to actually remove nodes.
	# Without this, the new build's add_child calls would coexist with the
	# pending-deletion previous nodes (overlap warnings, double-spawned lights).
	await get_tree().process_frame
	if new_seed != 0 and layout.generator != null:
		layout.generator.rng_seed = new_seed
	_build_level()
	_bake_navigation()


# Single source of truth for the build sequence — invoked by _ready
# (initial load) and rebuild (NG+ regeneration). Creates a fresh
# BuildContext each call so material caches and slot/door registries
# don't carry across rebuilds.
func _build_level() -> void:
	# Resolve graph + pieces together so we can pass the active graph to
	# BuildContext. For generator-mode the graph is transient (not stored on
	# layout); BuildContext + PuzzleBuilder both need it for door indexing
	# and puzzle dispatch.
	RoomAcoustics.clear_zones()
	var active_graph := _resolve_graph()
	_pieces = _pieces_from_graph(active_graph)
	_ctx = LevelBuildContext.create(self, layout, active_graph)
	_index_room_pieces()
	GroundBuilder.build(_ctx)
	CeilingBuilder.build(_ctx)
	LightingBuilder.configure_fps_fog(_ctx)

	for piece: LevelPiece in _pieces:
		# Apply per-piece theme override (if any) for the duration of the
		# build, then restore the layout default. Resolution order:
		# piece.theme_override (per-instance, set by generator/solver) wins
		# over RoomDef.theme_override / CorridorDef.theme_override
		# (template-level). Null at every layer = leave the active theme.
		var override: LevelTheme = piece.theme_override
		if override == null:
			if piece.room != null and piece.room.theme_override != null:
				override = piece.room.theme_override
			elif piece.corridor != null and piece.corridor.theme_override != null:
				override = piece.corridor.theme_override
		if override != null:
			_ctx.apply_theme(override)

		if piece.room != null:
			_build_room(piece)
		elif piece.corridor != null:
			_build_corridor(piece)

		if override != null:
			_ctx.apply_theme(layout.theme)

	# Stamp every piece's footprint into ExplorationState now that final
	# positions are known. Done before PuzzleBuilder so any door / switch
	# placements that query room_at_world resolve correctly.
	_register_exploration()

	# Puzzles run last — they reference doors and interactable slots, which
	# only exist after the geometry pass.
	PuzzleBuilder.apply_all(_ctx, layout)


# Builds the per-instance room_id → piece lookup that puzzles use for
# AABB queries. Same key format the door + slot registries use, so a
# puzzle holding "switch_hub" finds the same piece regardless of whether
# the level was authored or generated.
func _index_room_pieces() -> void:
	for piece: LevelPiece in _pieces:
		if piece.room == null:
			continue
		var pid: StringName = piece.room_id if piece.room_id != &"" else piece.room.id
		_ctx.pieces_by_id[pid] = piece


# Stamps every piece's XZ footprint into ExplorationState's cell map so
# LosCuller can room-gate entity visibility and the minimap fog can track
# which rooms have been seen. Reset of prior state happens via the
# &"level_reset_handler" group dispatch on descend — by the time this runs
# the cell map is empty. Corridors get synthetic ids derived from their
# world position since CorridorDef carries no id of its own; per-piece
# uniqueness is enough for the cell-map's last-write-wins behaviour.
func _register_exploration() -> void:
	for piece: LevelPiece in _pieces:
		if piece.room != null:
			var rd := piece.room
			var pid: StringName = piece.room_id if piece.room_id != &"" else rd.id
			ExplorationState.register_room(pid, piece.position, rd.size.x * 0.5, rd.size.y * 0.5)
		elif piece.corridor != null:
			var cd := piece.corridor
			var hx: float = cd.width * 0.5 if cd.axis == CorridorDef.Axis.Z else cd.length * 0.5
			var hz: float = cd.length * 0.5 if cd.axis == CorridorDef.Axis.Z else cd.width * 0.5
			var cid: StringName = piece.room_id if piece.room_id != &"" else StringName("corridor_%d_%d" % [int(round(piece.position.x)), int(round(piece.position.z))])
			ExplorationState.register_room(cid, piece.position, hx, hz)
	# Adjacency between pieces is what stops the "clutter / enemies vanish
	# around the corner" leak when an open architectural space spans two
	# graph pieces (room + corridor, two rooms with a wide opening). Built
	# from the registered footprints, so it must come after the loop.
	ExplorationState.finalize_layout()


# Returns the graph that drives this build (generator output or
# layout.graph), or null when only legacy pieces[] are configured.
# Triggers a navmesh rebake on the scene's NavigationRegion3D (if present).
# The region is set up to parse the &"structures" group, which our wall /
# floor / pillar StaticBodies join when built. Async bake — enemies guard
# their nav agent's pathing on whether a route is available, so they
# stand idle for a frame or two during the bake. Falls through quietly
# when no nav region exists (legacy prototype scene).
func _bake_navigation() -> void:
	var region := _find_nav_region(get_tree().current_scene)
	if region == null:
		return
	region.bake_navigation_mesh(true)


static func _find_nav_region(node: Node) -> NavigationRegion3D:
	if node == null:
		return null
	if node is NavigationRegion3D:
		return node
	for child in node.get_children():
		var r := _find_nav_region(child)
		if r != null:
			return r
	return null


func _resolve_graph() -> LevelGraph:
	if layout.generator != null:
		var generated := layout.generator.generate()
		if generated != null:
			return generated
		push_warning("[LevelBuilder] Generator returned null; falling through.")
	return layout.graph


# Solves a graph into LevelPieces, or returns layout.pieces when graph is
# null (legacy hand-authored pieces[] mode).
func _pieces_from_graph(g: LevelGraph) -> Array[LevelPiece]:
	if g != null:
		return GraphSolver.solve(g)
	return layout.pieces


# ── Rooms ─────────────────────────────────────────────────────────────────

func _build_room(piece: LevelPiece) -> void:
	var rd := piece.room
	var center := piece.position
	var hx := rd.size.x * 0.5
	var hz := rd.size.y * 0.5
	var thick := _ctx.theme.wall_thickness
	# Per-instance identity (preferred) → RoomDef.id (legacy fallback).
	var piece_id: StringName = piece.room_id if piece.room_id != &"" else rd.id

	if rd.pit_floor:
		PitBuilder.build_room_pit(_ctx, center, rd)
	else:
		FloorBuilder.build_piece_floor(_ctx, center, rd.size.x, rd.size.y)

	# Single procedural wall mesh for the entire room (one draw call).
	WallBuilder.build_room_mesh(_ctx, center, rd)
	_build_room_wall_collisions(piece_id, rd, center, hx, hz, thick)

	# Decorative columns — architectural blockers, distinct from pit pillars.
	for p in rd.decorative_pillars:
		WallBuilder.create_decorative_pillar(_ctx, center + Vector3(p.x, 0, p.y), rd.decorative_pillar_size)

	LightingBuilder.place_room_fluorescents(_ctx, center, rd)
	LightingBuilder.create_fill_light(_ctx, center, rd.size.x, rd.size.y)
	LightingBuilder.create_fog_volume(_ctx, center, rd.size.x, rd.size.y)
	LightingBuilder.create_room_particles(_ctx, center, rd.size.x, rd.size.y)
	DecalBuilder.place_puddles(_ctx, center, hx, hz, rd)
	ClutterBuilder.scatter_clutter(_ctx, center, hx, hz, rd, piece_id)
	InteractableBuilder.spawn_slots(_ctx, piece_id, center, rd, piece.additional_slots)
	# Per-instance count beats template default; -1 sentinel falls back.
	var enemy_count: int = piece.enemy_count_override if piece.enemy_count_override >= 0 else rd.enemy_count
	EnemySpawner.spawn_in_bounds(_ctx, piece, center, hx, hz, enemy_count, rd.enemy_scene, piece.enemy_level_range, rd.enemy_classes, piece.pack_chance_override)

	var ap: AcousticProfile = rd.acoustic_profile
	if ap == null:
		ap = AcousticProfile.from_area(rd.size.x * rd.size.y)
	RoomAcoustics.register_zone(center, Vector2(hx, hz), ap)


# Per-wall collision bodies and door instances. Wall *visuals* come from the
# single procedural room mesh; this loop only materialises physics + doors.
func _build_room_wall_collisions(piece_id: StringName, rd: RoomDef, center: Vector3, hx: float, hz: float, thick: float) -> void:
	var walls: Array[Dictionary] = [
		{"side": RoomDef.Wall.NORTH, "pos": center + Vector3(0, 0, -hz), "span": rd.size.x + thick, "sx": 1.0, "sz": 0.0},
		{"side": RoomDef.Wall.SOUTH, "pos": center + Vector3(0, 0, hz), "span": rd.size.x + thick, "sx": 1.0, "sz": 0.0},
		{"side": RoomDef.Wall.EAST, "pos": center + Vector3(hx, 0, 0), "span": rd.size.y + thick, "sx": 0.0, "sz": 1.0},
		{"side": RoomDef.Wall.WEST, "pos": center + Vector3(-hx, 0, 0), "span": rd.size.y + thick, "sx": 0.0, "sz": 1.0},
	]

	for w: Dictionary in walls:
		var side: RoomDef.Wall = w["side"] as RoomDef.Wall
		var wpos: Vector3 = w["pos"]
		var span: float = w["span"]
		var sx: float = w["sx"]
		var sz: float = w["sz"]

		var has_opening := side in rd.openings
		if has_opening:
			var gap := rd.opening_width
			var jamb_len := (span - gap) * 0.5
			if jamb_len > 0.0:
				var offset := (gap + jamb_len) * 0.5
				var wall_sx := jamb_len * sx + thick * sz
				var wall_sz := jamb_len * sz + thick * sx
				var dir := Vector3(sx, 0, sz)
				WallBuilder.create_wall_body(_ctx, wpos + dir * offset, wall_sx, wall_sz)
				WallBuilder.create_wall_body(_ctx, wpos - dir * offset, wall_sx, wall_sz)

			var door_key := StringName("%s_%d" % [piece_id, side])
			if (side in rd.door_openings) or _ctx.connection_doors.has(door_key):
				DoorBuilder.build_door(_ctx, piece_id, rd, side, wpos)
		else:
			var wall_sx := span * sx + thick * sz
			var wall_sz := span * sz + thick * sx
			WallBuilder.create_wall_body(_ctx, wpos, wall_sx, wall_sz)


# ── Corridors ─────────────────────────────────────────────────────────────

func _build_corridor(piece: LevelPiece) -> void:
	var cd := piece.corridor
	var center := piece.position

	WallBuilder.build_corridor_walls(_ctx, center, cd)
	FloorBuilder.build_corridor_floor(_ctx, center, cd)
	if cd.ceiling_height > 0.0:
		WallBuilder.build_low_ceiling(_ctx, center, cd)

	LightingBuilder.place_corridor_fluorescents(_ctx, center, cd)

	var hw := cd.width * 0.5
	var hl := cd.length * 0.5
	var hx := hw if cd.axis == CorridorDef.Axis.Z else hl
	var hz := hl if cd.axis == CorridorDef.Axis.Z else hw
	var fog_x := cd.width if cd.axis == CorridorDef.Axis.Z else cd.length
	var fog_z := cd.length if cd.axis == CorridorDef.Axis.Z else cd.width
	LightingBuilder.create_fill_light(_ctx, center, fog_x, fog_z)
	LightingBuilder.create_fog_volume(_ctx, center, fog_x, fog_z)
	LightingBuilder.create_room_particles(_ctx, center, fog_x, fog_z)
	var corridor_enemies: int = piece.enemy_count_override if piece.enemy_count_override >= 0 else cd.enemy_count
	EnemySpawner.spawn_in_bounds(_ctx, piece, center, hx, hz, corridor_enemies, cd.enemy_scene, Vector2i.ZERO, cd.enemy_classes, piece.pack_chance_override)

	var ap: AcousticProfile = cd.acoustic_profile
	if ap == null:
		ap = AcousticProfile.from_area(cd.width * cd.length)
	RoomAcoustics.register_zone(center, Vector2(hx, hz), ap)


# ── Public API ────────────────────────────────────────────────────────────

func get_door(room_id: StringName, wall: RoomDef.Wall) -> Node:
	# room_id is a per-instance id (RoomNode.id in graph mode, RoomDef.id in
	# legacy mode) — same key DoorBuilder uses when registering.
	var key := StringName("%s_%s" % [room_id, _ctx.wall_keys[wall]])
	return _ctx.doors.get(key)


# Re-spawns every piece's enemies at their original positions, each rolling a
# level in [center_level - spread, center_level + spread] (clamped >= 1) so
# the demo stays challenging as the player levels up.
func respawn_enemies(center_level: int, spread: int = 1) -> void:
	if layout == null:
		return
	var lo := maxi(1, center_level - spread)
	var hi := maxi(lo, center_level + spread)
	var lvl_range := Vector2i(lo, hi)
	for piece: LevelPiece in _pieces:
		if piece.room != null:
			var rd := piece.room
			var hx := rd.size.x * 0.5
			var hz := rd.size.y * 0.5
			EnemySpawner.spawn_in_bounds(_ctx, piece, piece.position, hx, hz, rd.enemy_count, rd.enemy_scene, lvl_range, rd.enemy_classes)
		elif piece.corridor != null:
			var cd := piece.corridor
			var hx := cd.width * 0.5 if cd.axis == CorridorDef.Axis.Z else cd.length * 0.5
			var hz := cd.length * 0.5 if cd.axis == CorridorDef.Axis.Z else cd.width * 0.5
			EnemySpawner.spawn_in_bounds(_ctx, piece, piece.position, hx, hz, cd.enemy_count, cd.enemy_scene, lvl_range, cd.enemy_classes)
