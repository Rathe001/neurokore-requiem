class_name UVRevealable extends Node

## Attach to any Node3D to make it UV-hidden. The node is invisible by default
## and fades in when the player has a UV light equipped, toggled on, and within
## range. Also gates interactability — the parent is added/removed from the
## "interactables" group and SpatialGrid based on reveal state.

const FADE_IN_SPEED := 4.0
const FADE_OUT_SPEED := 6.0

var _parent: Node3D
var _revealed: bool = false
var _alpha: float = 0.0
var _registered_interactable: bool = false

func _ready() -> void:
	_parent = get_parent() as Node3D
	if _parent == null:
		push_warning("[UVRevealable] Parent must be a Node3D.")
		return
	_parent.add_to_group(&"uv_hidden")
	_parent.visible = false

func _process(delta: float) -> void:
	if _parent == null:
		return
	var should_reveal := _is_in_uv_range()
	if should_reveal:
		_alpha = minf(_alpha + FADE_IN_SPEED * delta, 1.0)
	else:
		_alpha = maxf(_alpha - FADE_OUT_SPEED * delta, 0.0)

	var was_revealed := _revealed
	_revealed = _alpha > 0.0
	_parent.visible = _revealed

	if _revealed:
		_apply_alpha(_parent, _alpha)

	# Gate interactability on being fully (or mostly) revealed.
	var interactable := _alpha > 0.5
	if interactable and not _registered_interactable:
		_registered_interactable = true
		if _parent.has_method(&"interact"):
			_parent.add_to_group(&"interactables")
			SpatialGrid.register(_parent, &"interactables")
	elif not interactable and _registered_interactable:
		_registered_interactable = false
		if _parent.is_in_group(&"interactables"):
			_parent.remove_from_group(&"interactables")
			SpatialGrid.unregister(_parent)

func _is_in_uv_range() -> bool:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return false
	var player: Node = players[0]
	if not player.has_method(&"is_uv_active"):
		return false
	if not player.is_uv_active():
		return false
	var uv_range: float = player.get_uv_range()
	var offset: Vector3 = _parent.global_position - (player as Node3D).global_position
	return offset.length() <= uv_range

func _apply_alpha(node: Node3D, alpha: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.material_override != null and mi.material_override is StandardMaterial3D:
				var mat := mi.material_override as StandardMaterial3D
				mat.albedo_color.a = alpha
		elif child is Label3D:
			var label := child as Label3D
			label.modulate.a = alpha
		if child is Node3D:
			_apply_alpha(child, alpha)
