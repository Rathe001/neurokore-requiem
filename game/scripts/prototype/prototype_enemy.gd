extends CharacterBody3D
class_name PrototypeEnemy

signal died

const KNOCKBACK_DURATION := 0.15
const DEATH_HOLD := 1.6
const DEATH_FALLBACK_DURATION := 0.6

const CREDIT_DROP_MIN := 1
const CREDIT_DROP_MAX := 5
const CREDIT_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_credit_pickup.tscn")

const GRAVITY := 22.0
const CHASE_SPEED := 3.2
const AGGRO_RANGE := 10.0
const ATTACK_RANGE := 2.2
const ATTACK_DAMAGE := 10
const ATTACK_COOLDOWN := 1.6
const ATTACK_WINDUP := 0.4
const ATTACK_CONE_DEG := 80.0
const ATTACK_KNOCKBACK := 5.0

const ANIM_IDLE: Array[StringName] = [&"Idle_Normal", &"Idle", &"IDLE_NORMAL"]
const ANIM_RUN: Array[StringName] = [&"Jog_Fwd", &"Walk_Normal", &"JOG_FWD", &"WALK_NORMAL"]
const ANIM_ATTACK: Array[StringName] = [&"Sword_Attack", &"Punch_Cross", &"SWORD_ATTACK", &"PUNCH_CROSS"]
const ANIM_DEATH: Array[StringName] = [
	&"Death_1", &"Death_2", &"Death_A", &"Death_B", &"Death",
	&"Dying_A", &"Dying_B", &"Die",
	&"DEATH_1", &"DEATH_2", &"DEATH",
]

const OUTLINE_GROW := 0.04

@export var max_health: int = 40
@export_range(0.0, 1.0, 0.05) var credit_drop_chance: float = 0.6
@export var display_name: String = "Enemy"

@onready var visual: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/Character/AnimationPlayer
@onready var health_bar: MeshInstance3D = $HealthBar
@onready var collision: CollisionShape3D = $Collision
@onready var floor_ring: MeshInstance3D = $FloorRing

var _health: int
var _alive: bool = true
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0
var _attack_cd: float = 0.0
var _casting: bool = false
var _want_dir: Vector3 = Vector3.ZERO
var _player_ref: Node3D
var _outline_mat: StandardMaterial3D
var _outlined_meshes: Array[MeshInstance3D] = []
var _hover_hooked: bool = false

func _ready() -> void:
	_init_enemy()
	_setup_hover()

func _init_enemy() -> void:
	add_to_group(&"enemies")
	SpatialGrid.register(self, &"enemies")
	_health = max_health
	_alive = true
	_knockback_remain = 0.0
	_attack_cd = 0.0
	_casting = false
	_want_dir = Vector3.ZERO
	_player_ref = null
	set_physics_process(true)
	collision_layer = 1
	collision_mask = 1
	if collision != null:
		collision.disabled = false
	if floor_ring != null:
		floor_ring.visible = true
	if visual != null:
		visual.rotation = Vector3.ZERO
	_ensure_loop(ANIM_IDLE)
	_ensure_loop(ANIM_RUN)
	_play_anim(ANIM_IDLE)
	if health_bar != null:
		health_bar.visible = false

## Re-initialize an enemy returned from the pool.
func reset() -> void:
	remove_from_group(&"corpses")
	_init_enemy()

func _setup_hover() -> void:
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.albedo_color = Color.WHITE
	_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_mat.grow = true
	_outline_mat.grow_amount = OUTLINE_GROW
	_collect_meshes(visual)
	if not _hover_hooked:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		_hover_hooked = true

func _collect_meshes(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			_outlined_meshes.append(child)
		_collect_meshes(child)

func _set_outline(on: bool) -> void:
	var mat: Material = _outline_mat if on else null
	for mi in _outlined_meshes:
		if is_instance_valid(mi):
			mi.material_overlay = mat

func _on_mouse_entered() -> void:
	if not _alive:
		return
	_set_outline(true)
	get_tree().call_group(&"interactable_tooltip", &"show_text", display_name)

func _on_mouse_exited() -> void:
	_set_outline(false)
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0) -> void:
	if not _alive:
		return
	if DebugState.config != null and DebugState.config.one_shot_enemies:
		amount = max(amount, max_health)
	_health -= amount
	_update_health_bar()
	if knockback_strength > 0.0:
		var dir := global_position - knockback_from
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			_knockback_vel = dir.normalized() * knockback_strength
			_knockback_remain = KNOCKBACK_DURATION
	if _health <= 0:
		_die()

func _update_health_bar() -> void:
	if health_bar == null:
		return
	var ratio := clampf(float(_health) / float(max_health), 0.0, 1.0)
	health_bar.visible = _alive and ratio < 1.0
	health_bar.set_instance_shader_parameter(&"fill_ratio", ratio)

func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	if _knockback_remain > 0.0:
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		_knockback_remain -= delta
		_want_dir = Vector3.ZERO
	elif _casting:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_chase_tick()
	move_and_slide()

	if _alive and not _casting and _knockback_remain <= 0.0:
		if _want_dir.length_squared() > 0.01:
			_play_anim(ANIM_RUN)
			_face_direction(_want_dir)
		else:
			_play_anim(ANIM_IDLE)

func _chase_tick() -> void:
	_want_dir = Vector3.ZERO
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group(&"player") as Node3D
	var player := _player_ref
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
	_want_dir = dir
	velocity.x = dir.x * CHASE_SPEED
	velocity.z = dir.z * CHASE_SPEED

func _cast_attack(player: Node3D, aim: Vector3) -> void:
	_casting = true
	_attack_cd = ATTACK_COOLDOWN
	velocity.x = 0.0
	velocity.z = 0.0
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.2)
	PrototypeAttackIndicator.spawn_cone(self, aim, ATTACK_RANGE, ATTACK_CONE_DEG, ATTACK_WINDUP)
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
	if health_bar != null:
		health_bar.visible = false
	_drop_credits()
	var played := _play_anim(ANIM_DEATH, 1.0)
	if not played:
		if anim_player != null:
			anim_player.pause()
		if visual != null:
			var tween := create_tween()
			tween.tween_property(visual, "rotation:x", deg_to_rad(-75.0), DEATH_FALLBACK_DURATION)
	await get_tree().create_timer(DEATH_HOLD).timeout
	_become_corpse()

func _drop_credits() -> void:
	if randf() >= credit_drop_chance:
		return
	var parent := get_parent()
	if parent == null:
		return
	var pickup := CREDIT_PICKUP_SCENE.instantiate()
	pickup.amount = randi_range(CREDIT_DROP_MIN, CREDIT_DROP_MAX)
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector3(0.0, 1.0, 0.0)

func _become_corpse() -> void:
	SpatialGrid.unregister(self)
	remove_from_group(&"enemies")
	add_to_group(&"corpses")
	_set_outline(false)
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
	if collision != null:
		collision.disabled = true
	if floor_ring != null:
		floor_ring.visible = false
	collision_layer = 0
	collision_mask = 0
	get_tree().call_group(&"corpse_manager", &"register_corpse", self)

func _face_direction(dir: Vector3) -> void:
	if visual == null or dir.length_squared() < 0.0001:
		return
	visual.look_at(visual.global_position + dir, Vector3.UP)

func _play_anim(candidates: Array[StringName], speed: float = 1.0) -> bool:
	if anim_player == null:
		return false
	for name in candidates:
		if not anim_player.has_animation(name):
			continue
		var name_str := String(name)
		if anim_player.current_animation == name_str and anim_player.is_playing():
			return true
		anim_player.speed_scale = speed
		anim_player.play(name_str)
		return true
	return false

func _ensure_loop(candidates: Array[StringName]) -> void:
	if anim_player == null:
		return
	for name in candidates:
		if not anim_player.has_animation(name):
			continue
		var anim := anim_player.get_animation(name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		return
