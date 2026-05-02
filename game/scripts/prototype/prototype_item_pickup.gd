extends Node3D

const POP_UP_SPEED := 4.2
const POP_HORIZONTAL_SPEED := 1.8
const GRAVITY := 14.0
const SETTLED_HEIGHT := 0.35
const BOB_HEIGHT := 0.10
const BOB_SPEED := 2.2
const SPIN_SPEED := 0.8

var item: Item = null

@onready var _object: Node3D = $Visual/Object
@onready var _halo: MeshInstance3D = $Visual/Halo
@onready var _beam: MeshInstance3D = $Visual/Beam
@onready var _area: Area3D = $PickupArea

var _velocity: Vector3 = Vector3.ZERO
var _popping: bool = true
var _bob_phase: float = 0.0
var _object_y: float = 0.0
var _name_label: Label3D = null

func configure(p_item: Item) -> void:
	item = p_item

func _ready() -> void:
	add_to_group(&"pickups")
	SpatialGrid.register(self, &"pickups")
	_object_y = _object.position.y
	_bob_phase = randf() * TAU
	# Halo + beam dropped — they're noisy at scale (every loot drop in a
	# generated level adds another pulsing rim/light beam). Replaced by a
	# billboarded name label so the player can read what's on the floor at
	# a glance, rarity-tinted so colour still telegraphs value.
	_halo.visible = false
	_beam.visible = false
	if item != null:
		_object.add_child(ItemVisuals.build(item))
		_build_name_label(item)
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


func _build_name_label(p_item: Item) -> void:
	_name_label = Label3D.new()
	_name_label.text = tr(p_item.name_key) if p_item.name_key != "" else "Item"
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.fixed_size = true
	# fixed_size scales by pixel_size; small footprint so the label hovers
	# unobtrusively above the loot. Previous values were sized for a
	# headline, not a label.
	_name_label.pixel_size = 0.0011
	_name_label.font_size = 20
	# Thick fully-opaque black outline so the rarity-coloured text reads
	# legibly against light corridors AND dark rooms without a backplate.
	_name_label.outline_size = 12
	_name_label.modulate = p_item.glyph_color
	_name_label.outline_modulate = Color(0, 0, 0, 1.0)
	_name_label.position = Vector3(0, 0.9, 0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name_label)


func _physics_process(delta: float) -> void:
	if _popping:
		_velocity.y -= GRAVITY * delta
		var next_pos := global_position + _velocity * delta
		var horiz := Vector3(_velocity.x, 0.0, _velocity.z)
		if horiz.length_squared() > 0.0001:
			var space := get_world_3d().direct_space_state
			var ray_from := global_position + Vector3(0.0, 0.4, 0.0)
			var ray_to := next_pos + Vector3(0.0, 0.4, 0.0)
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			if not space.intersect_ray(query).is_empty():
				next_pos.x = global_position.x
				next_pos.z = global_position.z
				_velocity.x = 0.0
				_velocity.z = 0.0
		global_position = next_pos
		if global_position.y <= SETTLED_HEIGHT and _velocity.y < 0.0:
			global_position.y = SETTLED_HEIGHT
			_velocity = Vector3.ZERO
			_popping = false
		return
	_bob_phase += delta
	_object.position.y = _object_y + sin(_bob_phase * BOB_SPEED) * BOB_HEIGHT
	_object.rotation.y = _bob_phase * SPIN_SPEED

func _on_hover_enter() -> void:
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	if item != null:
		get_tree().call_group(&"interactable_tooltip", &"show_item", item)
	if _name_label != null:
		# Brighter on hover so the player sees what they're targeting.
		_name_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _on_hover_exit() -> void:
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
	if _name_label != null and item != null:
		_name_label.modulate = item.glyph_color

func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if _popping:
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	for modal in get_tree().get_nodes_in_group(&"ui_modal"):
		if not is_instance_valid(modal):
			continue
		if modal is CanvasItem and (modal as CanvasItem).visible:
			return
	if InventoryState.add_to_inventory(item):
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
		var player := get_tree().get_first_node_in_group(&"player")
		if player != null and player.has_method(&"consume_click"):
			player.consume_click()
		SpatialGrid.unregister(self)
		queue_free()
