class_name UVSwitch extends StaticBody3D

## A wall switch that is only visible and interactable under UV light.
## Uses UVRevealable for range-based reveal. When interacted, performs
## the configured action on the target door.

enum Action { TOGGLE, OPEN, CLOSE, UNLOCK }

const MESH_SIZE := Vector3(0.3, 0.3, 0.05)
const LAMP_SIZE := Vector3(0.1, 0.1, 0.02)
const COLOR_ACTIVE := Color(0.4, 0.15, 0.9, 1.0)
const COLOR_USED := Color(0.25, 0.1, 0.45, 0.5)

@export var target_door: NodePath
@export var action: Action = Action.TOGGLE
@export var display_name: String = "Hidden Switch"

var _used: bool = false
var _mesh: MeshInstance3D
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _collision: CollisionShape3D
var _outline: MeshInstance3D

func _ready() -> void:
	# Body mesh.
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = MESH_SIZE
	_mesh.mesh = box
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.2, 0.1, 0.3, 0.9)
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = body_mat
	add_child(_mesh)

	# Lamp indicator.
	_lamp = MeshInstance3D.new()
	var lamp_box := BoxMesh.new()
	lamp_box.size = LAMP_SIZE
	_lamp.mesh = lamp_box
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission_energy_multiplier = 3.0
	_lamp.material_override = _lamp_mat
	_lamp.position = Vector3(0, 0, MESH_SIZE.z * 0.5 + LAMP_SIZE.z * 0.5)
	add_child(_lamp)
	_refresh_lamp()

	# Collision.
	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = MESH_SIZE
	_collision.shape = shape
	add_child(_collision)

	# Outline for hover.
	_outline = MeshInstance3D.new()
	_outline.mesh = box
	var outline_mat := StandardMaterial3D.new()
	outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.albedo_color = Color.WHITE
	outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	outline_mat.grow = true
	outline_mat.grow_amount = 0.03
	_outline.material_override = outline_mat
	_outline.visible = false
	_mesh.add_child(_outline)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# UV reveal component — handles visibility, fade, and interactable registration.
	var revealer := UVRevealable.new()
	add_child(revealer)

func _on_mouse_entered() -> void:
	if not visible:
		return
	_outline.visible = true
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"show_text", display_name)

func _on_mouse_exited() -> void:
	_outline.visible = false
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func interact(_user: Node) -> void:
	if target_door == NodePath():
		return
	var door := get_node_or_null(target_door) as PrototypeDoor
	if door == null:
		return
	match action:
		Action.TOGGLE:
			door.toggle()
		Action.OPEN:
			door.open()
			_mark_used()
		Action.CLOSE:
			door.close()
			_mark_used()
		Action.UNLOCK:
			door.unlock()
			_mark_used()

func _mark_used() -> void:
	if _used:
		return
	_used = true
	_refresh_lamp()

func _refresh_lamp() -> void:
	var c := COLOR_USED if _used else COLOR_ACTIVE
	_lamp_mat.albedo_color = c
	_lamp_mat.emission = c
