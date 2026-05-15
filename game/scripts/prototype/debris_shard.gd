class_name DebrisShard
extends MeshInstance3D
## Lightweight tumbling debris chunk spawned when a DestructibleProp breaks.
## Hand-rolled physics (velocity + gravity + angular spin) instead of
## RigidBody3D — keeps the cost near-zero even when many props break at
## once during horde combat. Fades out over the last 30% of its lifetime
## and self-frees when done.

var mesh_resource: Mesh
var mat: StandardMaterial3D
var velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
var gravity: float = 12.0
var lifetime: float = 1.2
## Ground Y level — set by DestructibleProp to the prop's base so shards
## land on the floor, not at the prop's centre.
var floor_y: float = 0.0

var _age: float = 0.0
var _grounded: bool = false


func _ready() -> void:
	mesh = mesh_resource
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	if not _grounded:
		velocity.y -= gravity * delta
		global_position += velocity * delta
		# Tumble — rotate around all three axes for chaotic spin.
		rotate_x(angular_velocity.x * delta)
		rotate_y(angular_velocity.y * delta)
		rotate_z(angular_velocity.z * delta)
		# Stop on the floor — approximate the ground plane at spawn height.
		if global_position.y <= floor_y:
			global_position.y = floor_y
			_grounded = true
			velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO

	# Fade out over the last 30% of lifetime.
	var fade_start := lifetime * 0.7
	if _age > fade_start and mat != null:
		var t := (_age - fade_start) / (lifetime - fade_start)
		mat.albedo_color.a = 1.0 - t
