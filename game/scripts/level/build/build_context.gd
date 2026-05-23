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
## Cached extracted Meshes from kit PackedScenes (wall_model, floor_model).
## Avoids instantiating the .glb scene per room just to grab its mesh; the
## first room's build extracts and caches, subsequent rooms reuse. Both
## start null and stay null when the theme has no kit model assigned.
var wall_kit_mesh: Mesh
var floor_kit_mesh: Mesh
## Raw vertex-space AABB of the kit mesh — what MultiMeshInstance3D sees
## when it renders the mesh (the .glb's scene transforms are NOT applied
## by MMI, only the per-instance transform we set). Used for SCALING
## decisions: scale = target_size / raw_aabb.size.
var wall_kit_aabb: AABB
var floor_kit_aabb: AABB
## Visual AABB with the .glb's node-chain transforms baked in (root scale,
## etc.) — what the .glb looks like when instantiated as a regular scene.
## Used for TILING decisions: how wide is one "native" panel in design
## space, so we know how many tiles to lay out.
var wall_kit_aabb_visual: AABB
var floor_kit_aabb_visual: AABB
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
# calls hit the cache. When LevelBuilder.USE_DEBUG_LEVEL_VIZ is on, the
# theme's material slots are ignored and the debug ShaderMaterials are
# loaded from `res://resources/level/debug/` instead — this keeps debug
# viz working regardless of which materials the theme has authored, and
# means production themes can leave the material slots null (kit-bash
# walls don't need them; pillars/trim use a dark-grey fallback).
func _resolve_materials(t: LevelTheme) -> Dictionary:
	if _material_cache.has(t):
		return _material_cache[t]
	var wall: Material
	var floor_m: Material
	var wall_alt: Material
	var floor_alt: Material
	if LevelBuilder.USE_DEBUG_LEVEL_VIZ:
		wall = load("res://resources/level/debug/wall_debug.tres") as Material
		floor_m = load("res://resources/level/debug/floor_debug.tres") as Material
		wall_alt = load("res://resources/level/debug/wall_alt_debug.tres") as Material
		floor_alt = load("res://resources/level/debug/floor_alt_debug.tres") as Material
	else:
		# Default material fallbacks for themes that leave material slots
		# null (the kit-bash themes do this — the kit MMI shader provides
		# the visual, no theme material needed). When kit_walls / kit_floors
		# are disabled and we fall back to procedural geometry, the
		# procedural mesh needs SOME material or it renders as default
		# white BoxMesh. Dark concrete grey with PBR-tuned metal/rough
		# reads well under the high-energy fluorescents.
		wall = t.wall_material if t.wall_material != null else _make_themed_wall_material(t)
		floor_m = t.floor_material if t.floor_material != null else _make_themed_floor_material(t)
		wall_alt = t.wall_material_alt if t.wall_material_alt != null else wall
		floor_alt = t.floor_material_alt if t.floor_material_alt != null else floor_m
	var mats := {&"wall": wall, &"floor": floor_m, &"wall_alt": wall_alt, &"floor_alt": floor_alt}
	_material_cache[t] = mats
	return mats


# Per-theme procedural materials. Each theme spawns its own ShaderMaterial
# instance — same shader, identical structural config (panel size, seams,
# rivets, trim), differing only in the four tint uniforms read from
# LevelTheme.wall_*_offset / .wall_tint (and floor_*). Caching happens via
# _material_cache keyed by theme.
const _PROCEDURAL_WALL_SHADER: Shader = preload("res://scripts/level/build/procedural_wall.gdshader")


# Walls: 1m panels, modest bevel border + small rivets, very reflective
# (catches the ceiling fluorescents). Vertical surface so it doesn't get
# worn from foot traffic — keep wear/roughness low.
static func _make_themed_wall_material(t: LevelTheme) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _PROCEDURAL_WALL_SHADER
	# Structural config — identical across all themes; this is the family
	# resemblance every wall shares.
	m.set_shader_parameter(&"panel_size_x", 1.0)
	m.set_shader_parameter(&"panel_size_y", 1.0)
	m.set_shader_parameter(&"seam_width", 0.018)
	m.set_shader_parameter(&"seam_bevel", 0.04)
	m.set_shader_parameter(&"seam_depth", 0.14)
	m.set_shader_parameter(&"border_width", 0.04)
	m.set_shader_parameter(&"border_height", 0.03)
	m.set_shader_parameter(&"rivet_inset", 0.10)
	m.set_shader_parameter(&"rivet_radius", 0.028)
	m.set_shader_parameter(&"rivet_height", 0.015)
	m.set_shader_parameter(&"metallic_value", 0.75)
	m.set_shader_parameter(&"roughness_value", 0.32)
	m.set_shader_parameter(&"roughness_wear", 0.18)
	m.set_shader_parameter(&"wear_albedo_strength", 0.35)
	# Theme tints — subtle modulations, defaults are identity.
	m.set_shader_parameter(&"tint_color", t.wall_tint)
	m.set_shader_parameter(&"wear_offset", t.wall_wear_offset)
	m.set_shader_parameter(&"metallic_offset", t.wall_metallic_offset)
	m.set_shader_parameter(&"roughness_offset", t.wall_roughness_offset)
	return m


# Floors: 0.5m panels — half the wall tile size so the floor reads as
# small, dense floor tiles rather than chunky 2m slabs. Seam/border/rivet
# dimensions are in UV space (normalized per panel) so they scale
# automatically with panel_size — the same UV values that were a few cm
# wide on 2m panels become millimetre-scale details on 0.5m panels,
# which is what gives the smaller-tile look its proportional finish.
# More prominent bevel borders + larger rivets (UV-relative), slightly
# less reflective and more worn since the player walks on them. Iso
# camera catches floor reflections well, so metallic stays high even
# at higher roughness.
static func _make_themed_floor_material(t: LevelTheme) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _PROCEDURAL_WALL_SHADER
	m.set_shader_parameter(&"panel_size_x", 0.5)
	m.set_shader_parameter(&"panel_size_y", 0.5)
	m.set_shader_parameter(&"seam_width", 0.025)
	m.set_shader_parameter(&"seam_bevel", 0.06)
	m.set_shader_parameter(&"seam_depth", 0.18)
	m.set_shader_parameter(&"border_width", 0.07)
	m.set_shader_parameter(&"border_height", 0.04)
	m.set_shader_parameter(&"rivet_inset", 0.16)
	m.set_shader_parameter(&"rivet_radius", 0.045)
	m.set_shader_parameter(&"rivet_height", 0.025)
	m.set_shader_parameter(&"metallic_value", 0.7)
	m.set_shader_parameter(&"roughness_value", 0.42)
	m.set_shader_parameter(&"roughness_wear", 0.28)
	m.set_shader_parameter(&"wear_albedo_strength", 0.5)
	# Floors take foot traffic and spills — splotches turned on. Walls
	# inherit the shader default (0.0, clean).
	m.set_shader_parameter(&"splotch_strength", 0.55)
	m.set_shader_parameter(&"splotch_scale", 1.6)
	m.set_shader_parameter(&"splotch_threshold", 0.52)
	# Floors have no chair rail / baseboard — disable trim. (Shader gates
	# trim on `is_wall` anyway, but explicit-zero keeps the surface_height
	# branch off on floor fragments and saves a couple ops.)
	m.set_shader_parameter(&"baseboard_height", 0.0)
	m.set_shader_parameter(&"chair_rail_thickness", 0.0)
	# Theme tints for floors.
	m.set_shader_parameter(&"tint_color", t.floor_tint)
	m.set_shader_parameter(&"wear_offset", t.floor_wear_offset)
	m.set_shader_parameter(&"metallic_offset", t.floor_metallic_offset)
	m.set_shader_parameter(&"roughness_offset", t.floor_roughness_offset)
	return m


func _apply_material_set(mats: Dictionary) -> void:
	wall_material = mats[&"wall"]
	floor_material = mats[&"floor"]
	wall_material_alt = mats[&"wall_alt"]
	floor_material_alt = mats[&"floor_alt"]


