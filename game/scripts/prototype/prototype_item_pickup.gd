extends Node3D

const POP_UP_SPEED := 4.2
const POP_HORIZONTAL_SPEED := 1.8
const GRAVITY := 14.0
const SETTLED_HEIGHT := 0.35
const BOB_HEIGHT := 0.10
const BOB_SPEED := 2.2
const SPIN_SPEED := 0.8
const HALO_PULSE_SPEED := 1.6
const HALO_PULSE_RANGE := 0.10

var item: Item = null

@onready var _object: Node3D = $Visual/Object
@onready var _halo: MeshInstance3D = $Visual/Halo
@onready var _beam: MeshInstance3D = $Visual/Beam
@onready var _area: Area3D = $PickupArea

var _velocity: Vector3 = Vector3.ZERO
var _popping: bool = true
var _bob_phase: float = 0.0
var _object_y: float = 0.0
var _halo_mat: StandardMaterial3D
var _halo_base_energy: float = 0.0

func configure(p_item: Item) -> void:
	item = p_item

func _ready() -> void:
	add_to_group(&"pickups")
	SpatialGrid.register(self, &"pickups")
	_object_y = _object.position.y
	_bob_phase = randf() * TAU
	if item != null:
		_object.add_child(ItemVisuals.build(item))
		_apply_rarity_visuals(item.glyph_color, item.rarity)
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

func _apply_rarity_visuals(color: Color, rarity: StringName) -> void:
	_halo_base_energy = _halo_energy_for(rarity)
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	_halo_mat.emission_enabled = true
	_halo_mat.emission = color
	_halo_mat.emission_energy_multiplier = _halo_base_energy
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_halo.material_override = _halo_mat

	if rarity == &"rare" or rarity == &"unique":
		_beam.visible = true
		var beam_mat := StandardMaterial3D.new()
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var alpha: float = 0.32 if rarity == &"unique" else 0.20
		beam_mat.albedo_color = Color(color.r, color.g, color.b, alpha)
		beam_mat.emission_enabled = true
		beam_mat.emission = color
		beam_mat.emission_energy_multiplier = 1.8 if rarity == &"unique" else 1.3
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam.material_override = beam_mat
	else:
		_beam.visible = false

func _halo_energy_for(rarity: StringName) -> float:
	match rarity:
		&"unique": return 3.0
		&"rare":   return 2.4
		&"magic":  return 1.8
		_:         return 1.4

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
	if _halo_mat != null:
		var pulse := 1.0 + sin(_bob_phase * HALO_PULSE_SPEED) * HALO_PULSE_RANGE
		_halo_mat.emission_energy_multiplier = _halo_base_energy * pulse

func _on_hover_enter() -> void:
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	if item != null:
		get_tree().call_group(&"interactable_tooltip", &"show_item", item)

func _on_hover_exit() -> void:
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

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
