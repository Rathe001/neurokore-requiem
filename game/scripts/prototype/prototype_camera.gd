extends Camera3D

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(10, 14, 10)

var _target: Node3D

func _ready() -> void:
	if target_path != NodePath():
		_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		_snap_to_target()
	else:
		look_at(Vector3.ZERO, Vector3.UP)
	print("[prototype_camera] ready, target=", _target)

func _process(_delta: float) -> void:
	if _target == null:
		return
	_snap_to_target()

func _snap_to_target() -> void:
	global_position = _target.global_position + offset
	look_at(_target.global_position, Vector3.UP)
