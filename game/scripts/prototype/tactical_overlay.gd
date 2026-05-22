extends Node3D
class_name TacticalOverlay

## Tactical range overlay projected by SCANNER head mod. Shows two
## concentric ground rings: inner = weapon effective range (full damage),
## outer = falloff boundary (2× range). Distance labels at cardinal
## directions. Refreshes on equipment change.

const SHADER: Shader = preload("res://scripts/prototype/tactical_overlay.gdshader")
const GROUND_LIFT := 0.03
const LABEL_LIFT := 0.04
const PLANE_MARGIN := 1.1  # slight oversize so ring edges aren't clipped
const INNER_COLOR := Color(0.2, 0.85, 0.4)
const OUTER_COLOR := Color(0.95, 0.6, 0.15)
const LABEL_FONT_SIZE := 8
const LABEL_OUTLINE_SIZE := 2

var _mesh_inst: MeshInstance3D
var _material: ShaderMaterial
var _plane: PlaneMesh
var _inner_labels: Array[Label3D] = []
var _outer_labels: Array[Label3D] = []
var _current_inner_range: float = 0.0
var _current_outer_range: float = 0.0

# Cardinal directions on the XZ plane (N, E, S, W).
const DIRECTIONS: Array[Vector3] = [
	Vector3(0.0, 0.0, -1.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(-1.0, 0.0, 0.0),
]


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER

	_plane = PlaneMesh.new()
	_plane.size = Vector2(1.0, 1.0)

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = _plane
	_mesh_inst.material_override = _material
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.position = Vector3(0.0, GROUND_LIFT, 0.0)
	add_child(_mesh_inst)

	for i in 4:
		_inner_labels.append(_create_label(INNER_COLOR))
		_outer_labels.append(_create_label(OUTER_COLOR))

	InventoryState.equipment_changed.connect(_on_equipment_changed)
	refresh()
	set_process(true)


# Per-frame: update the shader's room_aabb uniform with the rect of the
# piece the player is currently standing in. Shader uses it to clip
# rings that extend past the room walls into the outer void.
func _process(_delta: float) -> void:
	var player := get_parent()
	if player == null or not (player is Node3D):
		return
	var room_id := ExplorationState.room_at_world((player as Node3D).global_position)
	if room_id == &"":
		# Unregistered position — let the rings render unclipped. Default
		# uniform sentinel covers this since the shader's initial value
		# is a huge "always inside" rect.
		_material.set_shader_parameter(&"room_aabb", Vector4(-9999.0, -9999.0, 9999.0, 9999.0))
		return
	var rect := ExplorationState.get_piece_aabb(room_id)
	if rect.size == Vector2.ZERO:
		_material.set_shader_parameter(&"room_aabb", Vector4(-9999.0, -9999.0, 9999.0, 9999.0))
		return
	_material.set_shader_parameter(&"room_aabb", Vector4(
		rect.position.x,
		rect.position.y,
		rect.position.x + rect.size.x,
		rect.position.y + rect.size.y,
	))


func _on_equipment_changed(_slot: StringName) -> void:
	refresh()


func refresh() -> void:
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	var inner_range: float = 0.0
	if weapon != null and weapon.weapon_range > 0.0:
		inner_range = weapon.weapon_range
	else:
		# Fallback to fire skill range.
		var player := get_parent()
		if player != null and player.has_method(&"resolve_skill"):
			var skill: Skill = player.resolve_skill(0)
			if skill != null:
				inner_range = skill.skill_range
	if inner_range <= 0.0:
		inner_range = 3.0  # unarmed default
	var outer_range := inner_range * PlayerCombat.FALLOFF_RANGE_MULT
	_current_inner_range = inner_range
	_current_outer_range = outer_range

	# Resize the plane to fit the outer ring with margin.
	var plane_diameter := outer_range * 2.0 * PLANE_MARGIN
	_plane.size = Vector2(plane_diameter, plane_diameter)

	# Normalize radii to 0–1 range (plane UV maps -1..1 in shader).
	var norm_inner := inner_range / (outer_range * PLANE_MARGIN)
	var norm_outer := outer_range / (outer_range * PLANE_MARGIN)
	_material.set_shader_parameter(&"inner_radius", norm_inner)
	_material.set_shader_parameter(&"outer_radius", norm_outer)

	# Position labels at cardinal directions.
	_update_labels(_inner_labels, inner_range)
	_update_labels(_outer_labels, outer_range)


func set_active(on: bool) -> void:
	visible = on


func _update_labels(labels: Array[Label3D], range_val: float) -> void:
	var text := "%dm" % int(round(range_val))
	for i in 4:
		var label := labels[i]
		label.text = text
		label.position = DIRECTIONS[i] * range_val + Vector3(0.0, LABEL_LIFT, 0.0)


func _create_label(color: Color) -> Label3D:
	var label := Label3D.new()
	label.font_size = LABEL_FONT_SIZE
	label.outline_size = LABEL_OUTLINE_SIZE
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.double_sided = true
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)
	return label
