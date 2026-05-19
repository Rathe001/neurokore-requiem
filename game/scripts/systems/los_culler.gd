extends Node

## Hides enemies, pickups, corpses, and interactibles from rendering when the
## player has no line of sight to them. Each physics frame, raycasts player →
## target at chest height against the World physics layer (walls). The LoS
## decision sets a target state in `_target_los`; rendering visibility fades
## smoothly between opaque and transparent over ~0.13s in `_process` so things
## don't pop in/out as the player moves through doorways.
##
## For interactibles that are themselves StaticBody3D on the World layer (doors,
## loot crates, exits), the target's own RID is excluded from the raycast so
## the body isn't its own occluder.
##
## Performance:
## - Distance gate: targets past MAX_DIST_SQ are forced invisible without a raycast.
## - Cell cache: static interactibles & corpses only re-raycast when the player
##   crosses a cell boundary; otherwise the cached target persists.
## - Stagger: dynamic targets (enemies, pickups) split across STAGGER_GROUPS
##   physics frames so each frame raycasts roughly half the population.
## - Fade lerp runs every render frame, raycasts run on the physics tick.

const WORLD_LAYER_MASK := 1  # physics layer 1 ("World") — walls + floors
const PILLAR_LAYER_MASK := 128  # props/pillars — block LoS when crouching
const COVER_MASK := WORLD_LAYER_MASK | PILLAR_LAYER_MASK
const RAY_HEIGHT := 1.0      # chest-height sample so the ray clears floor/ceiling colliders
const RAY_HEIGHT_CROUCH := 0.5  # crouched ray — low enough for medium props to block
const PICKUP_RAY_HEIGHT := 0.5  # pickups settle low; sample closer to ground
# Squared distance beyond which targets are forced invisible without a raycast.
# The fixed isometric camera frustum tops out around 30m on the diagonal — past
# 40m a target is offscreen anyway, so skip the physics query at horde density.
const MAX_DIST_SQ := 40.0 * 40.0
# 4m cells — large enough that the player crosses a boundary infrequently
# (every few seconds at walking speed) but small enough that the visibility
# state stays accurate as they move.
const CELL_SIZE := 4.0
const _INV_CELL_SIZE := 1.0 / CELL_SIZE
# Sentinel cell forces a full re-test on first physics frame.
const _UNSET_CELL := Vector2i(2147483647, 2147483647)
# Spread dynamic raycasts across this many physics frames. At 2, half the
# population is tested each tick — visibility lag is at most one physics step.
const STAGGER_GROUPS := 2
# Higher rate = snappier fade. ~12 gives a ~0.08s time constant, short enough
# to feel responsive when running through a doorway, long enough to mask the
# binary LoS flip and the staggered raycast cadence.
const FADE_RATE := 12.0
# Once transparency exceeds this, switch visible=false to stop rendering. We
# leave a tiny margin below 1.0 because lerp asymptotes — without the margin
# we'd render imperceptibly transparent geometry forever.
const HIDE_THRESHOLD := 0.98

var _query := PhysicsRayQueryParameters3D.new()
# node -> bool: visual LoS — walls only (written by physics, read by process)
var _target_los: Dictionary = {}
# node -> bool: combat LoS — walls + cover props. Only populated for enemies
# that have visual LoS; if visual LoS is false, combat LoS is implicitly false.
# has_los_to_player() reads this for AI gating so cover blocks attacks without
# hiding enemies from the player's screen.
var _combat_los: Dictionary = {}
# node -> float: current transparency [0=opaque, 1=invisible], lerped each frame
var _transparency: Dictionary = {}
# node -> Array[GeometryInstance3D]: cached descendants we apply transparency to.
# Cached because walking the hierarchy every frame for every tracked node would
# add up at horde density; entity meshes are static after spawn.
var _geom_cache: Dictionary = {}
var _last_player_cell: Vector2i = _UNSET_CELL
var _stagger_frame: int = 0
# Entities whose transparency is actively transitioning (haven't settled at
# their target yet). _process only iterates this set, not the full _target_los
# population — at steady state most entities are either fully visible or fully
# hidden and don't need per-frame lerp updates.
var _transitioning: Dictionary = {}  # Node3D -> true
# Periodic stale-entry sweep counter — every STALE_SWEEP_INTERVAL render frames,
# scan _target_los for invalid / out-of-tree entries that slipped past _process
# because they were already settled (not in _transitioning).
const STALE_SWEEP_INTERVAL := 120
var _sweep_counter: int = 0
# Cached player reference — refreshed on cell change to avoid per-frame
# get_nodes_in_group(&"player") allocation.
var _player_cache: Node3D = null
# Cached group arrays for categories not tracked by SpatialGrid. Refreshed on
# cell change — acceptable lag for static/quasi-static entities.
var _corpses_cache: Array = []
var _static_glows_cache: Array = []
var _clutter_cache: Array = []
# Per-room MultiMeshInstance3D / floor StaticBody3D nodes for kit-bash
# levels. Hidden when their room isn't adjacent to the player's, which
# spares the GPU a per-frame vertex+shadow pass on offscreen rooms. Same
# cell-change refresh cadence as the other static caches.
var _room_geometry_cache: Array = []

func _ready() -> void:
	_query.collision_mask = WORLD_LAYER_MASK
	_query.collide_with_areas = false
	_query.collide_with_bodies = true

func _physics_process(_delta: float) -> void:
	# Refresh player reference on cell change or first frame.
	if _player_cache == null or not is_instance_valid(_player_cache):
		_player_cache = _find_local_player()
		if _player_cache == null:
			return
	var player := _player_cache
	if player == null or not player.is_inside_tree():
		return
	var world := player.get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	# Both ray endpoints anchor to player Y, keeping each ray horizontal so it
	# can't graze ceilings/floors when targets settle at different heights
	# (e.g. crouch tunnels, pickups on the ground vs. enemies at chest height).
	var player_pos := player.global_position
	var from := player_pos + Vector3(0, RAY_HEIGHT, 0)
	var pickup_from := player_pos + Vector3(0, PICKUP_RAY_HEIGHT, 0)
	# Enemy-specific cover ray: crouching lowers the origin so medium props
	# (barrels, crates) block the cast — giving the player cover while ducked.
	var crouching: bool = player.has_method(&"is_crouching") and player.is_crouching()
	var enemy_from := player_pos + Vector3(0, RAY_HEIGHT_CROUCH if crouching else RAY_HEIGHT, 0)
	var player_cell := Vector2i(
		int(floor(player_pos.x * _INV_CELL_SIZE)),
		int(floor(player_pos.z * _INV_CELL_SIZE)),
	)
	var cell_changed := player_cell != _last_player_cell
	_last_player_cell = player_cell
	# First frame uses _UNSET_CELL so cell_changed is always true on frame 0,
	# which populates the corpse/static_glow caches immediately.

	# Room-aware visibility gate. Entities outside the player's current
	# room are forced invisible without raycasting — fixes the "I can see
	# enemies and loot through dark adjacent rooms" leak that pure LoS
	# raycasting can't catch when a doorway gives a clear line through
	# the wall plane. `player_room == &""` (player standing outside any
	# registered piece, e.g. legacy hand-authored levels with no
	# ExplorationState population) falls back to plain LoS behaviour so
	# we don't accidentally hide everything.
	var player_room: StringName = ExplorationState.room_at_world(player_pos)
	if player_room != &"":
		ExplorationState.reveal_room(player_room)

	if cell_changed:
		# Re-validate player ref on cell change in case of scene transitions.
		var local := _find_local_player()
		if local != null:
			_player_cache = local
		# Refresh cached group arrays for categories not in SpatialGrid.
		_corpses_cache = get_tree().get_nodes_in_group(&"corpses")
		_static_glows_cache = get_tree().get_nodes_in_group(&"static_glows")
		_clutter_cache = get_tree().get_nodes_in_group(&"clutter")
		_room_geometry_cache = get_tree().get_nodes_in_group(&"room_geometry")

	var stagger := _stagger_frame
	_stagger_frame = (_stagger_frame + 1) % STAGGER_GROUPS

	# Enemies — dynamic; stagger across STAGGER_GROUPS frames.
	# Iterate SpatialGrid's flat membership set (no per-frame allocation).
	# Newly seen enemies (no cache entry) are tested immediately so their target
	# state is correct from frame 0.
	#
	# Two LoS values per enemy:
	#   visual_los  — WORLD_LAYER_MASK only (walls). Drives rendering show/hide.
	#   combat_los  — COVER_MASK (walls + cover props). Drives has_los_to_player()
	#                 for enemy AI gating. Only tested when visual_los is true
	#                 (if a wall blocks, cover is irrelevant).
	var enemy_members: Dictionary = SpatialGrid.get_members(&"enemies")
	var index := 0
	for e in enemy_members:
		var enemy := e as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		# Room gate. Hide entities outside the player's piece + its
		# directly-adjacent pieces; doorways between distant rooms give a
		# clear ray that we don't want to count, and the adjacency reveal
		# covers connected open spaces.
		var blocked := _room_blocks(enemy, player_room)
		# Clutter destructibles (barrels, exam tables, etc.) register as
		# &"enemies" for damage routing but they're static level geometry.
		# Skip the per-entity LoS raycast (false-negatives on geometry-
		# edge props turn them into invisible obstacles in the player's
		# own room) but still respect the room gate so they don't leak
		# into distant unexplored rooms. Cover function is handled by
		# the PILLAR-layer combat-LOS test in enemy AI, not by visibility.
		if enemy.is_in_group(&"clutter"):
			_set_target(enemy, not blocked)
			_combat_los[enemy] = not blocked
			index += 1
			continue
		if blocked:
			_set_target(enemy, false)
			_combat_los[enemy] = false
			index += 1
			continue
		var first_seen := not _target_los.has(enemy)
		if first_seen or (index + stagger) % STAGGER_GROUPS == 0:
			var visual_los: bool
			var combat_los: bool
			if enemy.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
				visual_los = false
				combat_los = false
			else:
				# Visual ray — walls only.
				_query.collision_mask = WORLD_LAYER_MASK
				_query.exclude = []
				_query.from = from
				_query.to = Vector3(enemy.global_position.x, from.y, enemy.global_position.z)
				visual_los = space.intersect_ray(_query).is_empty()
				# Combat ray — walls + cover. Only needed when the enemy is
				# visible; skipped for destructible props (they don't have AI).
				if visual_los and not enemy.is_in_group(&"structures"):
					_query.collision_mask = COVER_MASK
					_query.from = enemy_from
					_query.to = Vector3(enemy.global_position.x, enemy_from.y, enemy.global_position.z)
					combat_los = space.intersect_ray(_query).is_empty()
					_query.collision_mask = WORLD_LAYER_MASK
				else:
					combat_los = visual_los
			_set_target(enemy, visual_los)
			_combat_los[enemy] = combat_los
		index += 1
	# Pickups skip the per-pickup LoS raycast — loot should be visible from
	# anywhere within the player's current room so players can see what's
	# in a room they've stepped into without sight-line bookkeeping. Room
	# gating still applies so loot in adjacent rooms doesn't leak through
	# open doorways (it'll fade in when the player enters that room).
	# Iterate SpatialGrid's flat membership set (no per-frame allocation).
	var pickup_members: Dictionary = SpatialGrid.get_members(&"pickups")
	for p in pickup_members:
		var pickup := p as Node3D
		if pickup == null:
			continue
		_set_target(pickup, not _room_blocks(pickup, player_room))
	# Corpses — static after the death-hold transition. Same low-ray sample as
	# pickups (corpses lie on the floor) and same cell-cached cadence as the
	# other static targets — re-raycast only when the player crosses a cell.
	# Uses cached group array refreshed on cell change (corpses aren't in
	# SpatialGrid since they're inert post-death entities).
	for c in _corpses_cache:
		# Cache is refreshed only on cell-change, so entries can go stale
		# between frames if a corpse is freed (despawn, despawned post-
		# death-hold). is_instance_valid catches both null and freed —
		# the bare null check missed freed-but-not-null and crashed
		# downstream when the cast tried to read global_position.
		if not is_instance_valid(c) or not c.is_inside_tree():
			continue
		var corpse := c as Node3D
		if corpse == null:
			continue
		if _room_blocks(corpse, player_room):
			_set_target(corpse, false)
			continue
		var corpse_first := not _target_los.has(corpse)
		if not (cell_changed or corpse_first):
			continue
		var corpse_los: bool
		if corpse.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
			corpse_los = false
		else:
			_query.exclude = []
			_query.from = pickup_from
			_query.to = Vector3(corpse.global_position.x, pickup_from.y, corpse.global_position.z)
			corpse_los = space.intersect_ray(_query).is_empty()
		_set_target(corpse, corpse_los)
	# Static glows — emissive meshes that aren't proper Light3Ds (pit ooze, etc).
	# ProximityLighting only dims OmniLight3D/SpotLight3D, so emissive surfaces
	# stay bright through walls without this. Same low-ray + cell-cache cadence
	# as corpses since they're tied to floor-level features.
	# Uses cached group array refreshed on cell change.
	for s in _static_glows_cache:
		# Guard against freed objects — same pattern as the corpses
		# loop above. The cache is refreshed on cell change, but a glow
		# can be freed mid-cell when its parent room teardown runs;
		# the cast below would crash on the freed instance.
		if not is_instance_valid(s) or not s.is_inside_tree():
			continue
		var glow := s as Node3D
		if glow == null:
			continue
		if _room_blocks(glow, player_room):
			_set_target(glow, false)
			continue
		var glow_first := not _target_los.has(glow)
		if not (cell_changed or glow_first):
			continue
		var glow_los: bool
		if glow.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
			glow_los = false
		else:
			_query.exclude = []
			_query.from = pickup_from
			_query.to = Vector3(glow.global_position.x, pickup_from.y, glow.global_position.z)
			glow_los = space.intersect_ray(_query).is_empty()
		_set_target(glow, glow_los)
	# Clutter — indestructible props (barriers, server racks, pipes, grates).
	# Uses the dedicated &"clutter" group (NOT &"structures", which includes
	# walls, floors, ceilings — all level geometry). Skip the per-entity LoS
	# raycast (false-negatives on geometry-edge props turn them into
	# invisible obstacles) but still apply the room gate so indestructibles
	# don't leak into distant unexplored rooms. Skip entries already in the
	# enemies loop (destructibles double-listed).
	for st in _clutter_cache:
		if not is_instance_valid(st) or not st.is_inside_tree():
			continue
		var structure := st as Node3D
		if structure == null or structure.is_in_group(&"enemies"):
			continue
		_set_target(structure, not _room_blocks(structure, player_room))
	# Room-gated kit-bash level geometry. The room_geometry group is the
	# wall + floor MultiMeshInstance3Ds (or their wrapping StaticBody3D for
	# floors with collision). Each MMI is positioned at the room's center
	# so room_at_world resolves correctly. Hide/show via .visible — no
	# fade because rooms are far enough apart that the pop isn't visible,
	# and the room-gate adjacency already keeps "one room over" visible.
	# Skipping vertex + shadow work on offscreen rooms is the biggest perf
	# win for kit-bash levels.
	for rg in _room_geometry_cache:
		if not is_instance_valid(rg) or not rg.is_inside_tree():
			continue
		var geom := rg as Node3D
		if geom == null:
			continue
		# Geometry-permissive: ignore closed-door state when deciding whether
		# the room's walls/floor render. Otherwise a closed door on an
		# adjacent room would hide the wall it sits in and the door would
		# appear to float in void.
		var geom_room: StringName = ExplorationState.room_at_world(geom.global_position)
		var should_hide := player_room != &"" and not ExplorationState.rooms_geometry_visible_together(player_room, geom_room)
		if geom.visible == should_hide:
			geom.visible = not should_hide
	# Interactibles — static (doors, switches, crates). Re-raycast only when the
	# player crosses a cell boundary, since neither side is moving otherwise.
	# Iterate SpatialGrid's flat membership set (no per-frame allocation).
	var interactable_members: Dictionary = SpatialGrid.get_members(&"interactables")
	for i in interactable_members:
		var body := i as CollisionObject3D
		if body == null or not body.is_inside_tree():
			continue
		# UVRevealable owns the visible flag for items in the "uv_hidden" group;
		# don't fight it.
		if body.is_in_group(&"uv_hidden"):
			continue
		# Room gate. Doors sit on the wall plane between two rooms and
		# should be visible from either adjacent room, so they bypass
		# the room check — the raycast against the door's actual mesh
		# below handles "you can see the door from here." All other
		# interactables (switches, exit pads, loot crates) live inside
		# a specific room and gate normally.
		if not (body is PrototypeDoor) and _room_blocks(body, player_room):
			_set_target(body, false)
			continue
		var body_first := not _target_los.has(body)
		if not (cell_changed or body_first):
			continue
		var body_los: bool
		if body.global_position.distance_squared_to(player_pos) > MAX_DIST_SQ:
			body_los = false
		else:
			_query.exclude = [body.get_rid()]
			_query.from = from
			if body is PrototypeDoor:
				# Doors sit flush in the wall plane with jambs flanking them
				# on the same World layer. Aiming at the door's centre lets
				# an off-axis ray clip a jamb before reaching the excluded
				# door, falsely reporting occluded. We offset the test point
				# along the door's local X (wall normal) by 0.6m onto the
				# player's side of the wall — that always lands ~0.4m past
				# the wall surface regardless of approach angle, where a
				# fixed offset along the player-direction would stay inside
				# the wall at glancing angles.
				#
				# We also test two endpoints offset along the door's local Z
				# (along the door width) at ±1.5m. A single central ray can
				# still clip a jamb corner at glancing angles even when the
				# door itself is plainly visible; if any of the three
				# endpoints clears, the door is considered visible.
				var wall_normal := body.global_transform.basis.x
				var door_along := body.global_transform.basis.z
				var to_player := player_pos - body.global_position
				var side: float = signf(to_player.dot(wall_normal))
				if side == 0.0:
					side = 1.0
				var base := body.global_position + wall_normal * (side * 0.6)
				var endpoints: Array[Vector3] = [
					base,
					base + door_along * 1.5,
					base - door_along * 1.5,
				]
				body_los = false
				for ep: Vector3 in endpoints:
					_query.to = Vector3(ep.x, from.y, ep.z)
					if space.intersect_ray(_query).is_empty():
						body_los = true
						break
			else:
				var to_player_xz := Vector3(
					player_pos.x - body.global_position.x,
					0.0,
					player_pos.z - body.global_position.z,
				)
				if to_player_xz.length_squared() > 0.0001:
					to_player_xz = to_player_xz.normalized() * 0.6
				var target_pos := body.global_position + to_player_xz
				_query.to = Vector3(target_pos.x, from.y, target_pos.z)
				body_los = space.intersect_ray(_query).is_empty()
				# Fallback: if the offset-point ray failed, try the body's
				# centre directly. The body's RID is excluded, so a clear ray
				# to centre means nothing else on the World layer sits
				# between player and body. Catches cases where the offset
				# point lands inside another collider while the body itself
				# is visible.
				if not body_los:
					_query.to = Vector3(body.global_position.x, from.y, body.global_position.z)
					body_los = space.intersect_ray(_query).is_empty()
		_set_target(body, body_los)

func _process(delta: float) -> void:
	# Framerate-independent damping: weight = 1 - e^(-rate * dt). Catches up
	# ~63% of the gap each ~0.08s, masking the binary physics-tick LoS flip.
	var weight: float = 1.0 - exp(-FADE_RATE * delta)
	var to_remove: Array = []
	var settled: Array = []
	for key in _transitioning:
		if not is_instance_valid(key):
			to_remove.append(key)
			continue
		var node := key as Node3D
		# Pooled entities lose their parent on release. Drop their cache entries
		# so a re-acquired instance fades in cleanly instead of inheriting the
		# previous owner's transparency state.
		if not node.is_inside_tree():
			to_remove.append(key)
			continue
		var los: bool = _target_los.get(key, false)
		var target_t: float = 0.0 if los else 1.0
		var current: float = _transparency.get(key, 1.0)
		current = lerp(current, target_t, weight)
		# lerp asymptotes — it never reaches exactly 0 or 1. When current
		# is non-zero, Godot routes the GeometryInstance3D through the
		# transparent rendering pipeline (no depth writes, back-to-front
		# sort), which causes camera-angle-dependent face dropouts on
		# multi-surface meshes. Snap to exactly 0 / 1 once we're close
		# enough so visible entities stay in the opaque pass. Cause of
		# the long-standing "textures look glitchy" feel across the
		# whole game — every tracked entity was permanently in the
		# transparent pass at transparency = ~0.001.
		if current < 0.005:
			current = 0.0
		elif current > HIDE_THRESHOLD:
			current = 1.0
		_transparency[key] = current
		# Show as soon as the target flips to visible — the alpha fade does the
		# rest. Hide only once we've fully faded out, so a brief LoS flicker
		# (e.g. a pickup briefly behind a glancing wall) doesn't hard-cut.
		if los and not node.visible:
			node.visible = true
		elif not los and current >= HIDE_THRESHOLD and node.visible:
			node.visible = false
		var geoms: Array = _geom_cache.get(key, [])
		for g in geoms:
			if is_instance_valid(g):
				(g as GeometryInstance3D).transparency = current
		# Check if this entity has settled at its target transparency.
		if los and current < 0.005:
			settled.append(key)
		elif not los and current >= HIDE_THRESHOLD:
			settled.append(key)
	for k in to_remove:
		_target_los.erase(k)
		_combat_los.erase(k)
		_transparency.erase(k)
		_geom_cache.erase(k)
		_transitioning.erase(k)
	for k in settled:
		_transitioning.erase(k)
	# Periodic stale-entry sweep for entities that became invalid while settled
	# (not in _transitioning). Runs infrequently — ~2x per second at 60fps.
	_sweep_counter += 1
	if _sweep_counter >= STALE_SWEEP_INTERVAL:
		_sweep_counter = 0
		var stale: Array = []
		for key in _target_los:
			if not is_instance_valid(key):
				stale.append(key)
			elif not (key as Node3D).is_inside_tree():
				stale.append(key)
		for k in stale:
			_target_los.erase(k)
			_combat_los.erase(k)
			_transparency.erase(k)
			_geom_cache.erase(k)
			_transitioning.erase(k)

func _set_target(node: Node3D, los: bool) -> void:
	var is_new := not _target_los.has(node)
	if is_new:
		# Fresh entries fade in from invisible regardless of initial LoS state —
		# avoids a one-frame flash at full opacity before the first lerp tick.
		_transparency[node] = 1.0
		_geom_cache[node] = _collect_geom(node)
	# Add to transitioning set when LoS state changes or on first see.
	if is_new or _target_los[node] != los:
		_transitioning[node] = true
	_target_los[node] = los
	# Pickability follows the discrete LoS target, not the lerped alpha. A
	# faded-but-not-yet-hidden target is still occluded by a wall and clicks
	# through it would be wrong; conversely a fading-in target should be
	# clickable as soon as the player rounds the corner.
	if node is CollisionObject3D:
		(node as CollisionObject3D).input_ray_pickable = los
	for child in node.get_children():
		if child is CollisionObject3D:
			(child as CollisionObject3D).input_ray_pickable = los

func _collect_geom(node: Node) -> Array:
	var out: Array = []
	if node is GeometryInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_collect_geom(child))
	return out

# Returns the avatar with multiplayer authority on this peer — i.e. the
# LOCAL player. Critical in MP: the &"player" group contains every peer's
# avatar, so picking [0] would land on a remote (often the host's) avatar
# on the client side, and every LoS / room calculation would run against
# the wrong position. Falls back to the first group member when no node
# has authority — covers SP (default authority is server=1, both equal)
# and the brief window before MultiplayerSpawner sets authority on
# joining peers.
func _find_local_player() -> Node3D:
	var players := get_tree().get_nodes_in_group(&"player")
	for n in players:
		var node := n as Node3D
		if node != null and is_instance_valid(node) and node.is_multiplayer_authority():
			return node
	if players.is_empty():
		return null
	return players[0] as Node3D


## True if `node` has combat line of sight to the player — accounts for cover
## props (PILLAR layer) when the player is crouching. Used by enemy AI to gate
## attacks. Falls back to visual LoS for nodes without a combat entry (pickups,
## structures, etc.).
func has_los_to_player(node: Node) -> bool:
	if _combat_los.has(node):
		return _combat_los[node]
	return _target_los.get(node, false)


# Returns true if room-gating should hide the entity — it sits outside the
# player's current room AND outside any room directly touching the player's
# room. Pieces adjacent at openings (corridor↔room, room↔room) read as
# co-visible so the player can see clutter and enemies in the connected
# space they're perceptually standing in, but rooms two hops away stay
# hidden. Returns false when player_room is empty (legacy / hand-authored
# scenes that skip ExplorationState.register_room) so those keep pre-
# room-gating LoS behaviour.
func _room_blocks(entity: Node3D, player_room: StringName) -> bool:
	if player_room == &"":
		return false
	var entity_room: StringName = ExplorationState.room_at_world(entity.global_position)
	return not ExplorationState.rooms_visible_together(player_room, entity_room)
