class_name PrototypeSwitch
extends HoverableInteractable

enum Action { TOGGLE, OPEN, CLOSE, UNLOCK }

const COLOR_ACTIVE := Color(0.35, 0.95, 1.0, 1.0)
const COLOR_USED := Color(0.4, 0.5, 0.55, 1.0)
# Hover-state emission boost for the lamp. The shared outline halo is small
# at this scale (0.4 × 1.4 × 0.6 housing) and reads poorly against dark
# walls, so the lamp itself flares to signal hover.
const LAMP_EMISSION_IDLE := 4.0
const LAMP_EMISSION_HOVER := 12.0

@export var target_door: NodePath
@export var action: Action = Action.TOGGLE

@onready var mesh: MeshInstance3D = $Mesh
@onready var lamp: MeshInstance3D = $Lamp

var _used: bool = false
var _mat: StandardMaterial3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = LAMP_EMISSION_IDLE
	lamp.material_override = _mat
	super._ready()
	_refresh_lamp()

func _on_mouse_entered() -> void:
	super._on_mouse_entered()
	if _mat != null and not _used:
		_mat.emission_energy_multiplier = LAMP_EMISSION_HOVER

func _on_mouse_exited() -> void:
	super._on_mouse_exited()
	if _mat != null:
		_mat.emission_energy_multiplier = LAMP_EMISSION_IDLE

func _get_outline_source() -> MeshInstance3D:
	return mesh

# Clear the "used" lamp state so the switch is interactable again after reset.
func reset_state() -> void:
	_used = false
	_refresh_lamp()
	_set_interactive(true)

func interact(_user: Node) -> void:
	if target_door == NodePath():
		return
	var door := get_node_or_null(target_door) as PrototypeDoor
	if door == null:
		return
	# One-shot actions become inert once consumed so multi-switch puzzles can't
	# be cheesed by re-triggering the same panel. Toggle is intentionally
	# excluded — it's the only repeatable action.
	if _used and action != Action.TOGGLE:
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
	_set_interactive(false)

# Used switches drop out of mouse picking, the SpatialGrid interactable index,
# and any active hover/tooltip state so they read as inert. reset_state() flips
# this back on for NG+ runs.
func _set_interactive(on: bool) -> void:
	input_ray_pickable = on
	if on:
		SpatialGrid.register(self, &"interactables")
	else:
		SpatialGrid.unregister(self)
		if _outline != null:
			_outline.visible = false
		remove_from_group(&"hovered_clickable")
		remove_from_group(&"tooltip_target")
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func _refresh_lamp() -> void:
	var c := COLOR_USED if _used else COLOR_ACTIVE
	_mat.albedo_color = c
	_mat.emission = c
