class_name PrototypeSwitch
extends StaticBody3D

enum Action { TOGGLE, OPEN, CLOSE, UNLOCK }

const COLOR_ACTIVE := Color(0.35, 0.95, 1.0, 1.0)
const COLOR_USED := Color(0.4, 0.5, 0.55, 1.0)
const OUTLINE_GROW := 0.04

@export var target_door: NodePath
@export var action: Action = Action.TOGGLE
@export var display_name: String = "Switch"

@onready var mesh: MeshInstance3D = $Mesh
@onready var lamp: MeshInstance3D = $Lamp

var _used: bool = false
var _mat: StandardMaterial3D
var _outline: MeshInstance3D

func _ready() -> void:
	add_to_group(&"interactables")
	SpatialGrid.register(self, &"interactables")
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 4.0
	lamp.material_override = _mat
	_build_outline()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_lamp()

func _build_outline() -> void:
	_outline = MeshInstance3D.new()
	_outline.mesh = mesh.mesh
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.WHITE
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = OUTLINE_GROW
	_outline.material_override = m
	_outline.visible = false
	mesh.add_child(_outline)

func _on_mouse_entered() -> void:
	_outline.visible = true
	get_tree().call_group(&"interactable_tooltip", &"show_text", display_name)

func _on_mouse_exited() -> void:
	_outline.visible = false
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
	_mat.albedo_color = c
	_mat.emission = c
