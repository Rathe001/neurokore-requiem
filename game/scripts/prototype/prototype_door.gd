class_name PrototypeDoor
extends StaticBody3D

const SLIDE_DURATION := 0.4
const SLIDE_DISTANCE := 4.7
const TINT_NEUTRAL := Color(0.55, 0.65, 0.75, 1.0)
const TINT_LOCKED := Color(0.85, 0.25, 0.2, 1.0)
const OUTLINE_GROW := 0.04

@export var locked: bool = false
@export var display_name: String = "Door"

@onready var mesh: MeshInstance3D = $Mesh
@onready var collision: CollisionShape3D = $Collision

var _open: bool = false
var _rest_y: float = 0.0
var _tween: Tween
var _mat: ShaderMaterial
var _outline: MeshInstance3D

const _FADE_SHADER: Shader = preload("res://scripts/prototype/proximity_fade.gdshader")

func _ready() -> void:
	add_to_group(&"doors")
	add_to_group(&"interactables")
	SpatialGrid.register(self, &"interactables")
	_rest_y = mesh.position.y
	_mat = ShaderMaterial.new()
	_mat.shader = _FADE_SHADER
	mesh.material_override = _mat
	_build_outline()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh_tint()

func _build_outline() -> void:
	_outline = MeshInstance3D.new()
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var st := SurfaceTool.new()
	st.create_from(mesh.mesh, 0)
	st.generate_normals(true)
	_outline.mesh = st.commit()
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
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	var label := "%s (Locked)" % display_name if locked else display_name
	get_tree().call_group(&"interactable_tooltip", &"show_text", label)

func _on_mouse_exited() -> void:
	_outline.visible = false
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

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
	_mat.set_shader_parameter(&"base_color", Color(c.r, c.g, c.b))
	_mat.set_shader_parameter(&"emission_color", Color(c.r, c.g, c.b))
