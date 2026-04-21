extends Node3D

const POP_UP_SPEED := 4.2
const POP_HORIZONTAL_SPEED := 1.8
const GRAVITY := 14.0
const SETTLED_HEIGHT := 0.35
const SPIN_SPEED := 2.5

var item: Item = null

@onready var _glyph: Label3D = $Visual/Glyph
@onready var _area: Area3D = $PickupArea

var _velocity: Vector3 = Vector3.ZERO
var _popping: bool = true

func configure(p_item: Item) -> void:
	item = p_item

func _ready() -> void:
	add_to_group(&"pickups")
	SpatialGrid.register(self, &"pickups")
	if item != null:
		_glyph.text = item.glyph
		_glyph.modulate = item.glyph_color
	var angle := randf() * TAU
	var speed_factor := randf_range(0.7, 1.1)
	_velocity = Vector3(
		cos(angle) * POP_HORIZONTAL_SPEED * speed_factor,
		POP_UP_SPEED * randf_range(0.9, 1.15),
		sin(angle) * POP_HORIZONTAL_SPEED * speed_factor,
	)
	_area.mouse_entered.connect(_on_hover_enter)
	_area.mouse_exited.connect(_on_hover_exit)
	_area.input_event.connect(_on_input_event)

func _physics_process(delta: float) -> void:
	$Visual.rotate_y(SPIN_SPEED * delta)
	if not _popping:
		return
	_velocity.y -= GRAVITY * delta
	global_position += _velocity * delta
	if global_position.y <= SETTLED_HEIGHT and _velocity.y < 0.0:
		global_position.y = SETTLED_HEIGHT
		_velocity = Vector3.ZERO
		_popping = false

func _on_hover_enter() -> void:
	if item != null:
		get_tree().call_group(&"interactable_tooltip", &"show_item", item)

func _on_hover_exit() -> void:
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if _popping:
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	for modal in get_tree().get_nodes_in_group(&"ui_modal"):
		if modal is CanvasItem and (modal as CanvasItem).visible:
			return
	if InventoryState.add_to_inventory(item):
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
		SpatialGrid.unregister(self)
		queue_free()
