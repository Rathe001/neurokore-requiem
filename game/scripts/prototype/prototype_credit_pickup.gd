extends Node3D

const POP_UP_SPEED := 4.8
const POP_HORIZONTAL_SPEED := 2.2
const GRAVITY := 14.0
const SETTLED_HEIGHT := 0.35
const MAGNET_RADIUS := 2.5
const COLLECT_RADIUS := 0.6
const MAGNET_SPEED := 9.0
const SPIN_SPEED := 2.5

@export var amount: int = 1

@onready var visual: Node3D = $Visual

var _velocity: Vector3 = Vector3.ZERO
var _popping: bool = true
var _player_ref: Node3D

func _ready() -> void:
	_init_pickup()

func _init_pickup() -> void:
	add_to_group(&"pickups")
	SpatialGrid.register(self, &"pickups")
	_player_ref = get_tree().get_first_node_in_group(&"player") as Node3D
	_randomize_pop()

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
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group(&"player") as Node3D
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
	if player.has_method(&"add_credits"):
		player.add_credits(amount)
	SpatialGrid.unregister(self)
	EntityPool.release(self)
