extends CharacterBody3D

signal health_changed(current: int, max_value: int)
signal died

const BASIC_RANGE := 3.5
const BASIC_DAMAGE := 25
const BASIC_CONE_DEG := 60.0
const BASIC_KNOCKBACK := 6.0
const BASIC_COLOR := Color(0.55, 0.85, 1.0, 1.0)
const BASIC_COOLDOWN := 0.3
const BASIC_WINDUP := 0.12

const KNOCKBACK_DURATION := 0.15
const DEATH_HOLD := 0.9
const RESPAWN_DELAY := 1.0

const ANIM_IDLE: Array[StringName] = [&"Idle_Normal", &"Idle", &"IDLE_NORMAL"]
const ANIM_RUN: Array[StringName] = [&"Jog_Fwd", &"Walk_Normal", &"JOG_FWD", &"WALK_NORMAL"]
const ANIM_ATTACK: Array[StringName] = [&"Sword_Attack", &"Punch_Cross", &"SWORD_ATTACK", &"PUNCH_CROSS"]
const ANIM_DEATH: Array[StringName] = [&"Death_1", &"DEATH_1", &"Death"]

@export var move_speed: float = 6.0
@export var accel: float = 50.0
@export var max_health: int = 100

@onready var visual: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/Character/AnimationPlayer

var _camera: Camera3D
var _attack_cd: float = 0.0
var _health: int
var _alive: bool = true
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0
var _attacking: bool = false
var _attack_aim: Vector3 = Vector3.ZERO

func _ready() -> void:
	_camera = get_viewport().get_camera_3d()
	add_to_group(&"player")
	_health = max_health
	_play_anim(ANIM_IDLE)

func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0) -> void:
	if not _alive:
		return
	_health = max(_health - amount, 0)
	health_changed.emit(_health, max_health)
	if knockback_strength > 0.0:
		var dir := global_position - knockback_from
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			_knockback_vel = dir.normalized() * knockback_strength
			_knockback_remain = KNOCKBACK_DURATION
	if _health <= 0:
		_die()

func _physics_process(delta: float) -> void:
	if not _alive:
		velocity = Vector3.ZERO
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)

	if _knockback_remain > 0.0:
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		_knockback_remain -= delta
	elif _attacking:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var input_vec := Vector2(
			Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
			Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
		)
		var wish_dir := Vector3.ZERO
		if input_vec.length_squared() > 0.0:
			var cam_forward := _flatten(-_camera.global_transform.basis.z)
			var cam_right := _flatten(_camera.global_transform.basis.x)
			wish_dir = (cam_right * input_vec.x - cam_forward * input_vec.y).normalized()
		var target: Vector3 = wish_dir * move_speed
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)
	velocity.y = 0.0
	move_and_slide()

	if _alive and not _attacking:
		var speed2 := velocity.x * velocity.x + velocity.z * velocity.z
		if speed2 > 0.25:
			_play_anim(ANIM_RUN)
			_face_velocity()
		else:
			_play_anim(ANIM_IDLE)

func _die() -> void:
	_alive = false
	died.emit()
	_play_anim(ANIM_DEATH, 1.0)
	await get_tree().create_timer(DEATH_HOLD).timeout
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	_respawn()

func _respawn() -> void:
	global_position = Vector3.ZERO
	velocity = Vector3.ZERO
	_knockback_remain = 0.0
	_attacking = false
	_health = max_health
	_alive = true
	health_changed.emit(_health, max_health)
	_play_anim(ANIM_IDLE)

func _unhandled_input(event: InputEvent) -> void:
	if not _alive:
		return
	if event.is_action_pressed(&"attack_single"):
		_cast_basic_attack()

func _cast_basic_attack() -> void:
	if _attack_cd > 0.0 or _attacking:
		return
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		return
	_attack_cd = BASIC_COOLDOWN
	_attacking = true
	_attack_aim = aim
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.4)
	PrototypeAttackIndicator.spawn_cone(
		self,
		aim,
		BASIC_RANGE,
		BASIC_CONE_DEG,
		BASIC_COLOR,
		BASIC_WINDUP,
	)
	await get_tree().create_timer(BASIC_WINDUP).timeout
	_attacking = false
	if not _alive:
		return
	_resolve_hit(_attack_aim)

func _resolve_hit(aim: Vector3) -> void:
	var half_cos := cos(deg_to_rad(BASIC_CONE_DEG * 0.5))
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not (e is Node3D):
			continue
		var enode := e as Node3D
		var to_enemy: Vector3 = enode.global_position - global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		if dist > BASIC_RANGE or dist < 0.001:
			continue
		if aim.dot(to_enemy / dist) < half_cos:
			continue
		if enode.has_method(&"take_damage"):
			enode.take_damage(BASIC_DAMAGE, global_position, BASIC_KNOCKBACK)

func _aim_direction() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var mouse_pos := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var dir := _camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.001:
		return Vector3.ZERO
	var t: float = (global_position.y - from.y) / dir.y
	if t < 0.0:
		return Vector3.ZERO
	var hit := from + dir * t
	var flat := hit - global_position
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	return flat.normalized()

func _face_velocity() -> void:
	var d := Vector3(velocity.x, 0.0, velocity.z)
	if d.length_squared() > 0.01:
		_face_direction(d.normalized())

func _face_direction(dir: Vector3) -> void:
	if visual == null or dir.length_squared() < 0.0001:
		return
	visual.look_at(visual.global_position + dir, Vector3.UP)

func _play_anim(candidates: Array[StringName], speed: float = 1.0) -> void:
	if anim_player == null:
		return
	for name in candidates:
		if not anim_player.has_animation(name):
			continue
		var name_str := String(name)
		if anim_player.current_animation == name_str and anim_player.is_playing():
			return
		anim_player.speed_scale = speed
		anim_player.play(name_str)
		return

func _flatten(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized()
