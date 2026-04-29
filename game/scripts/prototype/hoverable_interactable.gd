class_name HoverableInteractable
extends StaticBody3D

# Shared scaffolding for clickable world objects: hover outline, group
# membership, tooltip dispatch, and a reset_state() hook so the level-reset
# loop can restore initial state. Subclasses provide the outline source mesh,
# tooltip text, and any reset behavior.

const OUTLINE_GROW := 0.04

@export var display_name: String = ""

var _outline: MeshInstance3D

func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"resettable")
	SpatialGrid.register(self, &"interactables")
	var src := _get_outline_source()
	if src != null and src.mesh != null:
		_build_outline(src)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

# Subclass override: which MeshInstance3D do we wrap an outline halo around?
# Return null to skip outline (e.g. interactables with bespoke hover visuals).
func _get_outline_source() -> MeshInstance3D:
	return null

# Subclass override: tooltip text for the current state. Empty string suppresses.
func _get_tooltip_text() -> String:
	return display_name

# Subclass override: called by PrototypeRoot.reset_level() via the "resettable"
# group. Restore initial state (close doors, re-lock, clear "used" flags, etc).
func reset_state() -> void:
	pass

func _build_outline(src: MeshInstance3D) -> void:
	_outline = MeshInstance3D.new()
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var st := SurfaceTool.new()
	st.create_from(src.mesh, 0)
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
	src.add_child(_outline)

func _on_mouse_entered() -> void:
	if _outline != null:
		_outline.visible = true
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	var text := _get_tooltip_text()
	if text != "":
		get_tree().call_group(&"interactable_tooltip", &"show_text", text)

func _on_mouse_exited() -> void:
	if _outline != null:
		_outline.visible = false
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
