class_name PrototypeDoor
extends StaticBody3D

const SLIDE_DURATION := 0.4
const SLIDE_DISTANCE := 4.7
const TINT_NEUTRAL := Color(0.55, 0.65, 0.75, 1.0)
const TINT_LOCKED := Color(0.85, 0.25, 0.2, 1.0)

@export var locked: bool = false

@onready var mesh: MeshInstance3D = $Mesh
@onready var collision: CollisionShape3D = $Collision

var _open: bool = false
var _rest_y: float = 0.0
var _tween: Tween
var _mat: StandardMaterial3D

func _ready() -> void:
	add_to_group(&"doors")
	add_to_group(&"interactables")
	_rest_y = mesh.position.y
	_mat = StandardMaterial3D.new()
	_mat.metallic = 0.6
	_mat.roughness = 0.4
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 0.6
	mesh.material_override = _mat
	_refresh_tint()

func is_open() -> bool:
	return _open

func is_locked() -> bool:
	return locked

func open() -> void:
	if _open or locked:
		return
	_open = true
	collision.disabled = true
	_animate(_rest_y + SLIDE_DISTANCE)

func close() -> void:
	if not _open:
		return
	_open = false
	collision.disabled = false
	_animate(_rest_y)

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func interact(_user: Node) -> void:
	if locked:
		return
	toggle()

func unlock() -> void:
	if not locked:
		return
	locked = false
	_refresh_tint()

func _animate(target_y: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(mesh, "position:y", target_y, SLIDE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _refresh_tint() -> void:
	var c := TINT_LOCKED if locked else TINT_NEUTRAL
	_mat.albedo_color = c
	_mat.emission = c
