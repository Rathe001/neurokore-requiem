extends Node

## Dims point and spot lights to a fraction of their authored energy unless
## the player is nearby. Each frame, every tracked light's `light_energy` is
## lerped between `DIM_FACTOR * baseline` and `baseline` based on the player's
## horizontal distance, smoothstepped across [INNER_RADIUS, OUTER_RADIUS].
##
## DirectionalLight3D is intentionally excluded — sun/moon lighting shouldn't
## react to the player.
##
## Lights are auto-discovered: every OmniLight3D / SpotLight3D in the tree is
## registered when added, and its baseline energy is captured then. Edit
## `light_energy` in the editor as usual; this autoload reads that value as
## the "full brightness" target.
##
## A raycast against the World physics layer also gates each light: if a wall
## or closed door blocks the player→light path, the light is forced to the dim
## floor regardless of distance, so rooms behind doors stay dark until entered.

const INNER_RADIUS := 4.0       # within this distance: full authored energy
const OUTER_RADIUS := 12.0      # beyond this distance: DIM_FACTOR * authored energy
const DIM_FACTOR := 0.0         # full dark when no player nearby. Was 0.05 — at the
								#   iso camera angle that 5% baseline lit the OUTER
								#   walls of adjacent rooms with enough energy to read
								#   as a halo / light bleed in the void surrounding
								#   the level. With 0.0, lights truly turn off when
								#   the player isn't near them.
const OCCLUDED_DIM_FACTOR := 0.0  # ambient level when blocked by wall or closed door
# Energy threshold below which a light is hidden from the renderer entirely
# via `visible = false`. Set well below human-perceivable brightness so the
# toggle is invisible but Godot's forward+ light culling can skip the node.
# Without this, ProximityLighting was leaving 200+ OmniLight3Ds at energy
# ≈ 0 still flagged visible, costing ~30ms of per-frame engine proc on
# dense levels.
const LIGHT_VISIBILITY_EPSILON: float = 0.01
const WORLD_LAYER_MASK := 1     # walls + floors + doors
const RAY_HEIGHT := 0.5         # low sample height — clears floor colliders but stays
								#   below crouch-tunnel ceilings; the ray is horizontal
								#   (same Y on both endpoints), so we never aim it up at
								#   ceiling-mounted lights and trip on a low overhead.
const SMOOTHING_RATE := 6.0     # higher = snappier; ~6 gives a ~0.17s time constant
# 4m cells — lights are static, so the raycast result only changes when the
# player crosses a cell boundary. Re-raycasting every frame is wasted work;
# the distance-based lerp still runs every frame so the fade stays smooth.
const CELL_SIZE := 4.0
const _INV_CELL_SIZE := 1.0 / CELL_SIZE
const _UNSET_CELL := Vector2i(2147483647, 2147483647)

var _baselines: Dictionary = {}  # Light3D -> float (baseline energy)
var _visible: Dictionary = {}    # Light3D -> bool (in proximity AND line of sight)
var _blocked: Dictionary = {}    # Light3D -> bool (cached LoS test result)
var _query := PhysicsRayQueryParameters3D.new()
var _last_player_cell: Vector2i = _UNSET_CELL
var _cached_player: Node3D       # refreshed when invalidated or on cell change

func _ready() -> void:
	_query.collision_mask = WORLD_LAYER_MASK
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	get_tree().node_added.connect(_on_node_added)
	# Catch lights that already exist when this autoload starts.
	_scan(get_tree().root)

func _physics_process(delta: float) -> void:
	# Runs on the physics tick (was _process). Jolt errors out on
	# `world.direct_space_state` access from _process — strict about when
	# physics state is readable, where the legacy GodotPhysics engine was
	# silently lenient. 60Hz physics tick is plenty for ambient-light
	# falloff smoothing; no perceptible difference vs. running at render
	# rate.
	#
	# Quit-to-menu / level-change can leave _cached_player as a valid (not
	# freed) instance whose tree has been torn down. get_world_3d() then
	# returns an empty Ref<World3D> and direct_space_state on that is a
	# null-instance access. Re-fetch via group lookup; if no player exists
	# in the new tree state, sit out the frame.
	if not is_instance_valid(_cached_player) or not _cached_player.is_inside_tree():
		_cached_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _cached_player == null:
		return
	var player := _cached_player
	var world := player.get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var p := player.global_position
	var from := p + Vector3(0, RAY_HEIGHT, 0)
	# Room-gating: any light whose room isn't visible-together with the
	# player's room (per ExplorationState) gets forced to 0 energy regardless
	# of line-of-sight or distance. Without this, lights in adjacent rooms
	# that are visible through a doorway have clear LoS, dim only by the
	# distance fade, and still pour energy onto the OUTER faces of the
	# player's room walls — visible as a halo around the level.
	# player_room == &"" (hand-authored / legacy levels with no
	# ExplorationState population) skips this check.
	var player_room: StringName = ExplorationState.room_at_world(p)
	# Framerate-independent damping: weight = 1 - e^(-rate * dt). At rate=6,
	# this catches up ~63% of the gap each ~0.17s, masking raycast pop and
	# distance-band edges as a smooth fade.
	var weight: float = 1.0 - exp(-SMOOTHING_RATE * delta)
	var player_cell := Vector2i(
		int(floor(p.x * _INV_CELL_SIZE)),
		int(floor(p.z * _INV_CELL_SIZE)),
	)
	var cell_changed := player_cell != _last_player_cell
	_last_player_cell = player_cell
	var to_remove: Array = []
	for key in _baselines.keys():
		# Validity check has to come BEFORE the cast — `as Light3D` on a freed
		# instance triggers "Trying to cast a freed object" before we'd reach
		# the is_instance_valid branch. Tree check covers the second case
		# where a light is still valid (not freed) but has been removed from
		# the tree — accessing global_position then would spam the
		# "!is_inside_tree()" warning every frame until the next free.
		if not is_instance_valid(key):
			to_remove.append(key)
			continue
		var light := key as Light3D
		if not light.is_inside_tree():
			to_remove.append(key)
			continue
		var baseline: float = _baselines[key]
		var d2: Vector3 = light.global_position - p
		# Horizontal distance — vertical separation shouldn't dim, since the
		# camera is fixed-pitch and lights are mounted at varying heights.
		var dist := Vector2(d2.x, d2.z).length()
		var factor: float
		var blocked: bool
		# Reuse the cached blocked state when the player hasn't crossed a cell
		# boundary since the last raycast. Lights are static, so the answer
		# can't change without the player moving meaningfully.
		#
		# We raycast at all distances now, not just within OUTER_RADIUS.
		# Skipping it for far lights left them stuck at DIM_FACTOR (5%)
		# regardless of LoS — distant rooms behind walls would glow dimly
		# from far away and only go dark once the player crossed the falloff
		# threshold, which read as "rooms get darker when I approach them."
		# The cell cache caps the raycast cost: ~N raycasts per cell crossing
		# (≈1/sec at walking speed), not per frame.
		if cell_changed or not _blocked.has(key):
			# Horizontal ray at chest height — we only care whether a wall sits
			# between the player's footprint and the light's footprint, not
			# whether the light's ceiling mount is reachable. Aiming up at
			# ceiling-mounted lights would dim everything when crouching under
			# a low overhead.
			_query.from = from
			_query.to = Vector3(light.global_position.x, from.y, light.global_position.z)
			blocked = not space.intersect_ray(_query).is_empty()
			_blocked[key] = blocked
		else:
			blocked = _blocked[key]
		var room_gated := false
		if player_room != &"":
			var light_room: StringName = ExplorationState.room_at_world(light.global_position)
			room_gated = not ExplorationState.rooms_visible_together(player_room, light_room)
		if blocked or room_gated:
			factor = OCCLUDED_DIM_FACTOR
		elif dist >= OUTER_RADIUS:
			factor = DIM_FACTOR
		else:
			var t := smoothstep(INNER_RADIUS, OUTER_RADIUS, dist)
			factor = lerp(1.0, DIM_FACTOR, t)
		_visible[key] = (not blocked) and (not room_gated) and (dist < OUTER_RADIUS)
		var target: float = baseline * factor
		light.light_energy = lerp(light.light_energy, target, weight)
		# Cull dimmed lights from the renderer entirely. ProximityLighting
		# was leaving 200+ OmniLight3Ds at light_energy ≈ 0 but with
		# `visible = true`, so Godot's forward+ renderer still walked them
		# every frame for per-tile light culling + buffer allocation —
		# ~30ms of engine-side proc on dense procgen levels (NG+6 has 259
		# lights / 16 visible per the perf HUD). Setting visible=false on
		# energy<EPSILON drops them from the render pipeline. The threshold
		# is well below human perception so the toggle is invisible. Cheap:
		# one bool compare + occasional property write per frame.
		var should_be_visible: bool = light.light_energy > LIGHT_VISIBILITY_EPSILON
		if light.visible != should_be_visible:
			light.visible = should_be_visible
	for key in to_remove:
		_baselines.erase(key)
		_visible.erase(key)
		_blocked.erase(key)

## True if `light` is currently within the proximity falloff band AND has
## line of sight to the player. Used to gate effects (flicker, audio) that
## should only run when the light is actually contributing to the scene.
func is_visible(light: Node) -> bool:
	return _visible.get(light, false)

func _on_node_added(node: Node) -> void:
	_register(node)

func _scan(node: Node) -> void:
	_register(node)
	for child in node.get_children():
		_scan(child)

func _register(node: Node) -> void:
	if node is OmniLight3D or node is SpotLight3D:
		var light := node as Light3D
		if not _baselines.has(light):
			_baselines[light] = light.light_energy
			# Pre-dim using the actual player→light distance instead of a hard
			# occluded floor. Without this, transient lights (projectile glows,
			# beam impact lights) spawn at zero energy and the smoothing ramp
			# (~0.17s) takes longer than the projectile's flight — they never
			# reach visible brightness. Level lights spawned before the player
			# exists fall back to OCCLUDED_DIM_FACTOR, preserving the original
			# "no level-load flash" behaviour.
			light.light_energy = light.light_energy * _initial_factor_for(light)


func _initial_factor_for(light: Light3D) -> float:
	if not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _cached_player == null:
		return OCCLUDED_DIM_FACTOR
	var player := _cached_player
	var d := light.global_position - player.global_position
	var dist := Vector2(d.x, d.z).length()
	if dist >= OUTER_RADIUS:
		return DIM_FACTOR
	var t := smoothstep(INNER_RADIUS, OUTER_RADIUS, dist)
	return lerp(1.0, DIM_FACTOR, t)
