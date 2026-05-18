extends Node

## Fades meshes in the &"overhang" group when they sit between the camera and
## the player, so the player remains visible under low ceilings, catwalks, and
## any other overhead geometry. Uses GeometryInstance3D.transparency (an
## engine-level per-instance render parameter) so it works regardless of the
## mesh's material — including ShaderMaterial wall pieces, which an
## albedo-alpha approach can't touch.
##
## Each registered mesh's world-space AABB is cached at registration time and
## segment-tested against the camera→player line every frame. Overhangs are
## static, so the AABB doesn't need recomputing.

const FADE_RATE := 8.0             # ~0.13s time constant for fade in/out
# Target transparency when an overhang occludes the player. 0.4 = 60% opacity
# — enough to read "there's geometry here" while still seeing the player and
# anything else underneath. Bump toward 1.0 for full hide; toward 0.0 for no
# fade.
const OCCLUDED_TRANSPARENCY := 0.4
const HIDE_THRESHOLD := 0.99       # transparency >= this → set visible=false to
                                   #   skip the transparent draw pass entirely
                                   #   (no-op while OCCLUDED_TRANSPARENCY < 1)
const PLAYER_SAMPLE_HEIGHT := 0.9  # aim at chest, not feet — feet sample can
                                   #   miss the player when crouching, leaving
                                   #   the overhang opaque exactly when needed

# mesh -> AABB (world-space, cached at registration)
var _aabbs: Dictionary = {}
# mesh -> float current transparency (lerped each frame)
var _transparency: Dictionary = {}
var _cached_player: Node3D

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan(get_tree().root)

func _on_node_added(node: Node) -> void:
	# Defer the group check by one tree-process step. node_added fires
	# synchronously during add_child, but callers commonly call add_to_group
	# AFTER add_child, so checking the group here would miss them.
	if node is MeshInstance3D:
		(func() -> void:
			if is_instance_valid(node): _maybe_register(node)
		).call_deferred()

func _maybe_register(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is MeshInstance3D and node.is_in_group(&"overhang"):
		_register(node as MeshInstance3D)

func _scan(node: Node) -> void:
	if node is MeshInstance3D and node.is_in_group(&"overhang"):
		_register(node as MeshInstance3D)
	for child in node.get_children():
		_scan(child)

func _register(mesh: MeshInstance3D) -> void:
	if _aabbs.has(mesh):
		return
	if mesh.mesh == null:
		return
	_aabbs[mesh] = mesh.global_transform * mesh.mesh.get_aabb()
	_transparency[mesh] = 0.0   # start fully opaque

func _process(delta: float) -> void:
	if not is_instance_valid(_cached_player):
		_cached_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _cached_player == null:
		return
	var player := _cached_player
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var to := player.global_position + Vector3(0.0, PLAYER_SAMPLE_HEIGHT, 0.0)
	var weight: float = 1.0 - exp(-FADE_RATE * delta)
	var to_remove: Array = []
	for key in _aabbs:
		if not is_instance_valid(key):
			to_remove.append(key)
			continue
		var mesh := key as MeshInstance3D
		var aabb: AABB = _aabbs[key]
		var occluding := aabb.intersects_segment(from, to) != null
		var target: float = OCCLUDED_TRANSPARENCY if occluding else 0.0
		var current: float = _transparency[key]
		current = lerp(current, target, weight)
		_transparency[key] = current
		mesh.transparency = current
		mesh.visible = current < HIDE_THRESHOLD
	for k in to_remove:
		_aabbs.erase(k)
		_transparency.erase(k)
