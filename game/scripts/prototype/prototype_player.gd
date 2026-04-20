extends CharacterBody3D

signal health_changed(current: int, max_value: int)
signal resource_changed(current: int, max_value: int)
signal credits_changed(amount: int)
signal died

const KNOCKBACK_DURATION := 0.15
const DEATH_HOLD := 0.9
const RESPAWN_DELAY := 1.0
const INTERACT_RANGE_SQ := 6.25
const PLAYER_WORLD_POS_PARAM := &"player_world_pos"

const SKILL_INPUTS: Array[StringName] = [
	&"attack_single",
	&"attack_aoe",
	&"skill_1",
	&"skill_2",
	&"skill_3",
	&"skill_4",
	&"skill_q",
	&"skill_e",
]

const ANIM_IDLE: Array[StringName] = [&"Idle_Normal", &"Idle", &"IDLE_NORMAL"]
const ANIM_RUN: Array[StringName] = [&"Jog_Fwd", &"Walk_Normal", &"JOG_FWD", &"WALK_NORMAL"]
const ANIM_ATTACK: Array[StringName] = [&"Sword_Attack", &"Punch_Cross", &"SWORD_ATTACK", &"PUNCH_CROSS"]
const ANIM_DEATH: Array[StringName] = [
	&"Death_1", &"Death_2", &"Death_A", &"Death_B", &"Death",
	&"Dying_A", &"Dying_B", &"Die",
	&"DEATH_1", &"DEATH_2", &"DEATH",
]

@export var move_speed: float = 6.0
@export var accel: float = 50.0
@export var max_health: int = 100
@export var skills: Array[Skill] = []
@export var resource_pool: ResourcePool

@onready var visual: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/Character/AnimationPlayer

var class_id: StringName = &""
var spec_id: StringName = &""
var _camera: Camera3D
var _health: int
var _alive: bool = true
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0
var _attacking: bool = false
var _attack_aim: Vector3 = Vector3.ZERO
var _want_dir: Vector3 = Vector3.ZERO
var _cooldowns: Dictionary = {}
var _resource_current: float = 0.0
var _resource_last_int: int = 0
var _credits: int = 0

func _ready() -> void:
	_camera = get_viewport().get_camera_3d()
	add_to_group(&"player")
	class_id = PlayerState.class_id
	spec_id = PlayerState.spec_id
	_health = max_health
	_ensure_loop(ANIM_IDLE)
	_ensure_loop(ANIM_RUN)
	_play_anim(ANIM_IDLE)
	_apply_class_appearance()
	if resource_pool != null:
		_resource_current = float(resource_pool.start_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)
	_apply_debug_overrides()

func _apply_class_appearance() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UIThemeState.palette.player_color
	mat.metallic = 0.1
	mat.roughness = 0.6
	mat.no_depth_test = true
	mat.render_priority = 1
	_tint_meshes(visual, mat)

func _tint_meshes(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_meshes(child, mat)

func _apply_debug_overrides() -> void:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return
	if cfg.override_start_position:
		global_position = cfg.start_position
	if cfg.starting_credits > 0:
		_credits = cfg.starting_credits
		credits_changed.emit(_credits)

func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0) -> void:
	if not _alive:
		return
	if DebugState.config != null and DebugState.config.god_mode:
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

func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set(PLAYER_WORLD_POS_PARAM, global_position)

func _physics_process(delta: float) -> void:
	if not _alive:
		velocity = Vector3.ZERO
		return
	_tick_cooldowns(delta)
	_tick_resource_regen(delta)

	if _knockback_remain > 0.0:
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
		_knockback_remain -= delta
		_want_dir = Vector3.ZERO
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
		_want_dir = wish_dir
		var target: Vector3 = wish_dir * move_speed
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)
	velocity.y = 0.0
	move_and_slide()

	if _alive and not _attacking and _knockback_remain <= 0.0:
		if _want_dir.length_squared() > 0.01:
			_play_anim(ANIM_RUN)
			_face_direction(_want_dir)
		else:
			_play_anim(ANIM_IDLE)

	_handle_skill_input()

func _unhandled_input(event: InputEvent) -> void:
	if not _alive:
		return
	if event.is_action_pressed(&"interact"):
		if _is_any_modal_open() or _is_mouse_over_ui():
			return
		_try_interact()

func _try_interact() -> void:
	var nearest: Node = null
	var nearest_d2: float = INF
	for n in get_tree().get_nodes_in_group(&"interactables"):
		if not (n is Node3D):
			continue
		var n3 := n as Node3D
		var d2: float = global_position.distance_squared_to(n3.global_position)
		if d2 <= INTERACT_RANGE_SQ and d2 < nearest_d2:
			nearest_d2 = d2
			nearest = n
	if nearest != null and nearest.has_method(&"interact"):
		nearest.interact(self)

func _handle_skill_input() -> void:
	if _attacking:
		return
	for i in SKILL_INPUTS.size():
		if not Input.is_action_pressed(SKILL_INPUTS[i]):
			continue
		if _is_any_modal_open() or _is_mouse_over_ui():
			return
		if i < skills.size():
			_cast_skill(skills[i])
		return

func _is_any_modal_open() -> bool:
	for modal in get_tree().get_nodes_in_group(&"ui_modal"):
		if modal is CanvasItem and modal.visible:
			return true
	return false

func _is_mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _cast_skill(skill: Skill) -> void:
	if skill == null or _attacking:
		return
	if _cooldowns.get(skill, 0.0) > 0.0:
		return
	var infinite_resource := DebugState.config != null and DebugState.config.infinite_resource
	if skill.resource_cost > 0 and not infinite_resource and _resource_current < float(skill.resource_cost):
		return
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		return
	_cooldowns[skill] = skill.cooldown
	if skill.resource_cost > 0:
		_spend_resource(skill.resource_cost)
	_attacking = true
	_attack_aim = aim
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.4)
	PrototypeAttackIndicator.spawn(self, skill, aim)
	if skill.wind_up > 0.0:
		await get_tree().create_timer(skill.wind_up).timeout
	_attacking = false
	if not _alive:
		return
	_resolve_skill_hit(skill, _attack_aim)

func _resolve_skill_hit(skill: Skill, aim: Vector3) -> void:
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			_resolve_cone(skill, aim)
		Skill.TargetingMode.AOE_RADIAL:
			_resolve_aoe(skill)

func _resolve_cone(skill: Skill, aim: Vector3) -> void:
	var half_cos := cos(deg_to_rad(skill.cone_deg * 0.5))
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not (e is Node3D):
			continue
		var enode := e as Node3D
		var to_enemy: Vector3 = enode.global_position - global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		if dist > skill.range or dist < 0.001:
			continue
		if aim.dot(to_enemy / dist) < half_cos:
			continue
		if enode.has_method(&"take_damage"):
			enode.take_damage(skill.damage, global_position, skill.knockback)

func _resolve_aoe(skill: Skill) -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not (e is Node3D):
			continue
		var enode := e as Node3D
		var to_enemy: Vector3 = enode.global_position - global_position
		to_enemy.y = 0.0
		if to_enemy.length() > skill.range:
			continue
		if enode.has_method(&"take_damage"):
			enode.take_damage(skill.damage, global_position, skill.knockback)

func _tick_cooldowns(delta: float) -> void:
	for skill in _cooldowns.keys():
		_cooldowns[skill] = maxf(0.0, _cooldowns[skill] - delta)

func _tick_resource_regen(delta: float) -> void:
	if resource_pool == null or resource_pool.regen_per_sec <= 0.0:
		return
	if _resource_current >= float(resource_pool.max_value):
		return
	_resource_current = minf(float(resource_pool.max_value), _resource_current + resource_pool.regen_per_sec * delta)
	_emit_resource_if_changed()

func _spend_resource(amount: int) -> void:
	if resource_pool == null:
		return
	if DebugState.config != null and DebugState.config.infinite_resource:
		return
	_resource_current = maxf(0.0, _resource_current - float(amount))
	_emit_resource_if_changed()

func _emit_resource_if_changed() -> void:
	var new_int := int(_resource_current)
	if new_int != _resource_last_int:
		_resource_last_int = new_int
		resource_changed.emit(new_int, resource_pool.max_value)

func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	_credits += amount
	credits_changed.emit(_credits)

func get_credits() -> int:
	return _credits

func get_cooldown_ratio(skill: Skill) -> float:
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	var remaining: float = _cooldowns.get(skill, 0.0)
	return clampf(remaining / skill.cooldown, 0.0, 1.0)

func _die() -> void:
	_alive = false
	died.emit()
	var played := _play_anim(ANIM_DEATH, 1.0)
	if not played and anim_player != null:
		anim_player.pause()
	if visual != null:
		var tween := create_tween()
		tween.tween_property(visual, "scale:y", 0.15, 0.5)
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
	_cooldowns.clear()
	if visual != null:
		visual.scale = Vector3.ONE
	if resource_pool != null:
		_resource_current = float(resource_pool.start_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)
	health_changed.emit(_health, max_health)
	_play_anim(ANIM_IDLE)

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

func _flatten(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized()
