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
const DIM_FACTOR := 0.05        # ambient level when no player nearby (line of sight)
const OCCLUDED_DIM_FACTOR := 0.0  # ambient level when blocked by wall or closed door
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

func _ready() -> void:
	_query.collision_mask = WORLD_LAYER_MASK
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	get_tree().node_added.connect(_on_node_added)
	# Catch lights that already exist when this autoload starts.
	_scan(get_tree().root)

func _process(delta: float) -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var player := players[0] as Node3D
	if player == null:
		return
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return
	var p := player.global_position
	var from := p + Vector3(0, RAY_HEIGHT, 0)
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
		# the is_instance_valid branch.
		if not is_instance_valid(key):
			to_remove.append(key)
			continue
		var light := key as Light3D
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
		if blocked:
			factor = OCCLUDED_DIM_FACTOR
		elif dist >= OUTER_RADIUS:
			factor = DIM_FACTOR
		else:
			var t := smoothstep(INNER_RADIUS, OUTER_RADIUS, dist)
			factor = lerp(1.0, DIM_FACTOR, t)
		_visible[key] = (not blocked) and (dist < OUTER_RADIUS)
		var target: float = baseline * factor
		light.light_energy = lerp(light.light_energy, target, weight)
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
			# Pre-dim to the occluded floor so newly-spawned lights don't render
			# at full baseline for the one frame before _process runs its first
			# proximity check. Without this, every light flashes bright on level
			# load, exposing the entire level for ~0.5s while the lerp settles.
			light.light_energy = light.light_energy * OCCLUDED_DIM_FACTOR
