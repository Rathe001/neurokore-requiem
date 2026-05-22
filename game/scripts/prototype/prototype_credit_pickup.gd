extends Node3D

const POP_UP_SPEED := 4.8
const POP_HORIZONTAL_SPEED := 2.2
const GRAVITY := 14.0
const SETTLED_HEIGHT := 0.35
const MAGNET_RADIUS := 2.5
const COLLECT_RADIUS := 0.6
const MAGNET_SPEED := 9.0
const SPIN_SPEED := 2.5

const CREDIT_COLOR := Color(1.0, 0.85, 0.25)

@export var amount: int = 1

@onready var visual: Node3D = $Visual

var _velocity: Vector3 = Vector3.ZERO
var _popping: bool = true
var _player_ref: Node3D
var _amount_label: Label3D = null
var _collecting: bool = false

func _ready() -> void:
	_init_pickup()

func _init_pickup() -> void:
	add_to_group(&"pickups")
	SpatialGrid.register(self, &"pickups")
	_player_ref = _find_local_player()
	_collecting = false
	_ensure_amount_label()
	_randomize_pop()


# Build (or refresh) the floating "<N> cr" label. Lives once per pickup
# instance — pooled credits hit reset() with a new amount, so the text
# needs re-syncing on each acquire.
func _ensure_amount_label() -> void:
	if _amount_label == null:
		_amount_label = Label3D.new()
		_amount_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Walls occlude the label — without depth testing the credit
		# amount leaked through walls and showed in adjacent rooms.
		# Matches prototype_item_pickup._build_name_label which already
		# set this correctly.
		_amount_label.no_depth_test = false
		_amount_label.fixed_size = true
		_amount_label.pixel_size = 0.0011
		_amount_label.font_size = 20
		# Thick fully-opaque outline matching item pickup labels — keeps the
		# gold "N cr" readable on any background without a backplate.
		_amount_label.outline_size = 12
		_amount_label.modulate = CREDIT_COLOR
		_amount_label.outline_modulate = Color(0, 0, 0, 1.0)
		_amount_label.position = Vector3(0, 0.9, 0)
		_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_amount_label)
	_amount_label.text = "%d cr" % amount

func _randomize_pop() -> void:
	_popping = true
	var angle := randf() * TAU
	var speed_factor := randf_range(0.7, 1.1)
	_velocity = Vector3(
		cos(angle) * POP_HORIZONTAL_SPEED * speed_factor,
		POP_UP_SPEED * randf_range(0.9, 1.15),
		sin(angle) * POP_HORIZONTAL_SPEED * speed_factor,
	)

func reset() -> void:
	_init_pickup()

func _pool_release() -> void:
	remove_from_group(&"pickups")
	_popping = true
	_collecting = false
	_velocity = Vector3.ZERO
	_player_ref = null

func _physics_process(delta: float) -> void:
	if visual != null:
		visual.rotate_y(SPIN_SPEED * delta)
	if _popping:
		_tick_pop(delta)
	else:
		_tick_settled(delta)

func _tick_pop(delta: float) -> void:
	_velocity.y -= GRAVITY * delta
	global_position += _velocity * delta
	if global_position.y <= SETTLED_HEIGHT and _velocity.y < 0.0:
		global_position.y = SETTLED_HEIGHT
		_velocity = Vector3.ZERO
		_popping = false

func _tick_settled(delta: float) -> void:
	if _collecting:
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = _find_local_player()
	var player := _player_ref
	if player == null:
		return
	var target: Vector3 = player.global_position + Vector3(0.0, 0.8, 0.0)
	var to_player: Vector3 = target - global_position
	var dist := to_player.length()
	if dist < COLLECT_RADIUS:
		_collect(player)
		return
	if dist < MAGNET_RADIUS:
		global_position += (to_player / dist) * MAGNET_SPEED * delta

func _collect(player: Node) -> void:
	if _collecting:
		return
	# SP path: direct collect + return to pool.
	if not NetState.is_in_lobby():
		if player.has_method(&"add_credits"):
			player.add_credits(amount)
		SpatialGrid.unregister(self)
		# Deferred — _collect runs from _physics_process, and EntityPool.release
		# removes a CollisionObject from the tree, which physics forbids mid-step.
		EntityPool.release.call_deferred(self)
		return
	# MP path: request from host via PickupsContainer. Mark _collecting
	# to prevent duplicate requests while waiting for the host confirm.
	_collecting = true
	var container := get_tree().get_first_node_in_group(&"pickups_container")
	if container != null:
		# Host collects inline (rpc_id to self doesn't fire for server).
		if NetState.is_host():
			if player.has_method(&"add_credits"):
				player.add_credits(amount)
			SpatialGrid.unregister(self)
			queue_free.call_deferred()
		else:
			container.request_credit_collect.rpc_id(1, get_path())


## In MP, find only the LOCAL player (the one with multiplayer authority)
## so credits magnet to the player on this machine, not a remote avatar.
func _find_local_player() -> Node3D:
	if not NetState.is_in_lobby():
		return get_tree().get_first_node_in_group(&"player") as Node3D
	for node in get_tree().get_nodes_in_group(&"player"):
		if node is Node3D and node.is_multiplayer_authority():
			return node as Node3D
	return null
