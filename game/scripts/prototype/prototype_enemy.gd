extends CharacterBody3D

signal died

const KNOCKBACK_DURATION := 0.15
const DEATH_HOLD := 1.6

const CHASE_SPEED := 3.2
const AGGRO_RANGE := 10.0
const ATTACK_RANGE := 2.2
const ATTACK_DAMAGE := 10
const ATTACK_COOLDOWN := 1.6
const ATTACK_WINDUP := 0.4
const ATTACK_CONE_DEG := 80.0
const ATTACK_KNOCKBACK := 5.0
const ATTACK_COLOR := Color(1.0, 0.3, 0.18, 1.0)

const ANIM_IDLE: Array[StringName] = [&"Idle_Normal", &"Idle", &"IDLE_NORMAL"]
const ANIM_RUN: Array[StringName] = [&"Jog_Fwd", &"Walk_Normal", &"JOG_FWD", &"WALK_NORMAL"]
const ANIM_ATTACK: Array[StringName] = [&"Sword_Attack", &"Punch_Cross", &"SWORD_ATTACK", &"PUNCH_CROSS"]
const ANIM_DEATH: Array[StringName] = [&"Death_1", &"DEATH_1", &"Death"]

@export var max_health: int = 40

@onready var visual: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/Character/AnimationPlayer

var _health: int
var _alive: bool = true
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0
var _attack_cd: float = 0.0
var _casting: bool = false

func _ready() -> void:
	add_to_group(&"enemies")
	_health = max_health
	_play_anim(ANIM_IDLE)

func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0) -> void:
	if not _alive:
		return
	_health -= amount
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
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)

	if _knockback_remain > 0.0:
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		_knockback_remain -= delta
	elif _casting:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_chase_tick()
	velocity.y = 0.0
	move_and_slide()

	if _alive and not _casting:
		var speed2 := velocity.x * velocity.x + velocity.z * velocity.z
		if speed2 > 0.25:
			_play_anim(ANIM_RUN)
			_face_velocity()
		else:
			_play_anim(ANIM_IDLE)

func _chase_tick() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > AGGRO_RANGE or dist < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if dist <= ATTACK_RANGE and _attack_cd <= 0.0:
		_cast_attack(player, to_player / dist)
		return
	var dir := to_player / dist
	velocity.x = dir.x * CHASE_SPEED
	velocity.z = dir.z * CHASE_SPEED

func _cast_attack(player: Node3D, aim: Vector3) -> void:
	_casting = true
	_attack_cd = ATTACK_COOLDOWN
	velocity.x = 0.0
	velocity.z = 0.0
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.2)
	PrototypeAttackIndicator.spawn_cone(self, aim, ATTACK_RANGE, ATTACK_CONE_DEG, ATTACK_COLOR, ATTACK_WINDUP)
	await get_tree().create_timer(ATTACK_WINDUP).timeout
	_casting = false
	if not _alive or not is_instance_valid(player):
		return
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist > ATTACK_RANGE or dist < 0.001:
		return
	var half_cos := cos(deg_to_rad(ATTACK_CONE_DEG * 0.5))
	if aim.dot(to_p / dist) < half_cos:
		return
	if player.has_method(&"take_damage"):
		player.take_damage(ATTACK_DAMAGE, global_position, ATTACK_KNOCKBACK)

func _die() -> void:
	_alive = false
	died.emit()
	set_physics_process(false)
	_play_anim(ANIM_DEATH, 1.0)
	await get_tree().create_timer(DEATH_HOLD).timeout
	queue_free()

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
