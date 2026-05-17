extends RefCounted
class_name LevelBuildContext
## Shared state passed to every builder during level construction.
## Builders are stateless static methods that read materials/caches from
## here and attach their nodes to `root`. The doors registry is the one
## piece of output collected back for LevelBuilder.get_door().

var root: Node3D
## Container node for spawned enemies. Enemies are added as children of
## this node so the MultiplayerSpawner can replicate them in MP. Defaults
## to root when no dedicated container is found (backwards compat).
var enemies: Node3D
## Container node for spawned pickups (items + credits). In MP the
## PickupsContainer's MultiplayerSpawner replicates drops to all peers.
var pickups: Node3D
var layout: LevelLayout
## The active LevelGraph used by this build. For graph-mode layouts this is
## layout.graph; for generator-mode it's the transient graph the generator
## emitted this build. PuzzleBuilder + connection-door indexing both read
## from here, NOT from layout.graph (which is null in generator mode).
var graph: LevelGraph
var theme: LevelTheme
var wall_material: Material
var floor_material: Material
var wall_material_alt: Material
var floor_material_alt: Material
var wall_meshes: Dictionary = {}
var wall_shapes: Dictionary = {}
## Cache: LevelTheme → {wall, floor, wall_alt, floor_alt} so apply_theme()
## doesn't rebuild StandardMaterial3D / ShaderMaterial instances every time
## a piece swaps to an already-seen theme.
var _material_cache: Dictionary = {}
var doors: Dictionary = {}
## Spawned interactables, keyed "{room_id}.{slot_id}" → Node. Populated by
## InteractableBuilder during room construction; consumed by PuzzleBuilder
## (and anything else that needs to find a placed interactable by name).
var slots: Dictionary = {}
## Walls where the LevelBuilder should instantiate a door because a graph
## Connection requested one (in addition to RoomDef.door_openings). Keyed
## "{piece_id}_{wall_int}" → true. Precomputed in create() so the wall
## loop doesn't have to walk graph.connections per wall.
var connection_doors: Dictionary = {}
## room_id (per-instance, same key as ctx.doors / ctx.slots use) → LevelPiece.
## Populated by LevelBuilder after pieces are resolved; lets puzzles look up
## a room's position + size for AABB queries (e.g. ClearRoomPuzzle).
## Only room pieces are indexed — corridors are not.
var pieces_by_id: Dictionary = {}
var wall_keys: Array = []


static func create(root_: Node3D, layout_: LevelLayout, graph_: LevelGraph = null) -> LevelBuildContext:
	var ctx := LevelBuildContext.new()
	ctx.root = root_
	var ec := root_.get_node_or_null("EnemiesContainer") as Node3D
	ctx.enemies = ec if ec != null else root_
	var pc := root_.get_node_or_null("PickupsContainer") as Node3D
	ctx.pickups = pc if pc != null else root_
	ctx.layout = layout_
	# Caller passes the resolved graph (generator output OR layout.graph).
	# Falling back to layout.graph keeps backward compat with anything that
	# called create() pre-graph-passing (only LevelBuilder in practice).
	ctx.graph = graph_ if graph_ != null else layout_.graph
	ctx.theme = layout_.theme
	ctx.wall_keys = RoomDef.Wall.keys()
	ctx._init_materials()
	ctx._index_connection_doors()
	return ctx


# Walks the graph's connections (if any) and indexes which (piece_id, wall)
# combinations should get a door from the connection layer. Empty for
# legacy pieces[]-only levels; runs even when generator-resolved so the
# generator can request doors via Connection.has_door.
func _index_connection_doors() -> void:
	if graph == null:
		return
	for c: Connection in graph.connections:
		if c == null or not c.has_door:
			continue
		var key := StringName("%s_%d" % [c.from_room, c.from_wall])
		connection_doors[key] = true


func _init_materials() -> void:
	if theme == null:
		push_warning("[LevelBuildContext] Layout has no theme.")
		return
	_apply_material_set(_resolve_materials(theme))


# Swap the active material set to one derived from `t`. Null falls back to
# the layout's default theme. No-op when the requested theme is already
# active. Builders read ctx.wall_material / ctx.floor_material etc. on
# every call (no caching at the call site), so mutating these between
# piece builds is safe.
func apply_theme(t: LevelTheme) -> void:
	var target: LevelTheme = t if t != null else layout.theme
	if target == null or target == theme:
		return
	theme = target
	_apply_material_set(_resolve_materials(target))


# Returns (and caches) the {wall, floor, wall_alt, floor_alt} set for a
# given theme. First call per theme builds the materials; subsequent
# calls hit the cache.
func _resolve_materials(t: LevelTheme) -> Dictionary:
	if _material_cache.has(t):
		return _material_cache[t]
	# Pre-baked material overrides take priority — used for Blenderkit-
	# sourced PBR materials (StandardMaterial3D with texture set), bypasses
	# the shader/color procedural path entirely.
	var wall: Material = t.wall_material_override if t.wall_material_override != null \
		else _make_material(t.wall_shader, t.wall_color, t.wall_metallic, t.wall_roughness, t.wall_shader_params)
	var floor_m: Material = t.floor_material_override if t.floor_material_override != null \
		else _make_material(t.floor_shader, t.floor_color, t.floor_metallic, t.floor_roughness, t.floor_shader_params)
	# Alt materials fall back to the primary (not a fresh standard material)
	# when no alt shader is supplied — corridors look the same as rooms
	# unless the theme opts in to a variant.
	var wall_alt: Material
	if t.wall_material_alt_override != null:
		wall_alt = t.wall_material_alt_override
	elif t.wall_shader_alt != null:
		wall_alt = _make_shader_material(t.wall_shader_alt, t.wall_shader_alt_params)
	else:
		wall_alt = wall
	var floor_alt: Material
	if t.floor_material_alt_override != null:
		floor_alt = t.floor_material_alt_override
	elif t.floor_shader_alt != null:
		floor_alt = _make_shader_material(t.floor_shader_alt, t.floor_shader_alt_params)
	else:
		floor_alt = floor_m
	var mats := {&"wall": wall, &"floor": floor_m, &"wall_alt": wall_alt, &"floor_alt": floor_alt}
	_material_cache[t] = mats
	return mats


func _apply_material_set(mats: Dictionary) -> void:
	wall_material = mats[&"wall"]
	floor_material = mats[&"floor"]
	wall_material_alt = mats[&"wall_alt"]
	floor_material_alt = mats[&"floor_alt"]


static func _make_material(shader: Shader, color: Color, metallic: float, roughness: float, shader_params: Dictionary = {}) -> Material:
	if shader != null:
		return _make_shader_material(shader, shader_params)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


static func _make_shader_material(shader: Shader, shader_params: Dictionary = {}) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader
	for key in shader_params:
		sm.set_shader_parameter(key, shader_params[key])
	return sm
