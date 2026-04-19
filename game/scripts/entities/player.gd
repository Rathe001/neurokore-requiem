extends CharacterBody2D
class_name Player

signal health_changed(current: int, max_value: int)
signal resource_changed(current: int, max_value: int)
signal died

const SPEED := 240.0
const MAX_HEALTH := 100
const RESPAWN_DELAY := 2.0
const KNOCKBACK_DURATION := 0.12

# Skills are indexed by hotbar slot. See SKILL_INPUTS below for the
# input action mapped to each slot.
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

@export var skills: Array[Skill] = []
@export var resource_pool: ResourcePool

var current_health: int
var _cooldowns: Dictionary = {}
var _alive := true
var _knockback_velocity := Vector2.ZERO
var _knockback_remaining := 0.0
var _resource_current: float = 0.0
var _resource_last_int: int = 0

@onready var visual: Sprite2D = $Visual

func _ready() -> void:
	current_health = MAX_HEALTH
	add_to_group(&"player")
	health_changed.emit(current_health, MAX_HEALTH)
	if resource_pool != null:
		_resource_current = float(resource_pool.start_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)

func _physics_process(delta: float) -> void:
	if not _alive:
		return

	_tick_cooldowns(delta)
	_tick_resource_regen(delta)
	_knockback_remaining = maxf(0.0, _knockback_remaining - delta)

	if _knockback_remaining > 0.0:
		velocity = _knockback_velocity
	else:
		var input_vector := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		velocity = input_vector * SPEED
	move_and_slide()

	_update_facing(_aim_direction())
	_handle_skill_input()

func _handle_skill_input() -> void:
	for i in SKILL_INPUTS.size():
		if Input.is_action_pressed(SKILL_INPUTS[i]):
			if i < skills.size():
				_cast_skill(skills[i])
			return

func take_damage(amount: int, knockback_from: Vector2 = Vector2.ZERO, knockback_strength: float = 0.0) -> void:
	if not _alive:
		return
	current_health -= amount
	_flash()
	_apply_knockback(knockback_from, knockback_strength)
	health_changed.emit(current_health, MAX_HEALTH)
	if current_health <= 0:
		_die()

func _apply_knockback(source: Vector2, strength: float) -> void:
	if strength <= 0.0:
		return
	var offset := global_position - source
	if offset.length_squared() < 0.0001:
		return
	_knockback_velocity = offset.normalized() * strength
	_knockback_remaining = KNOCKBACK_DURATION

func _cast_skill(skill: Skill) -> void:
	if skill == null:
		return
	if _cooldowns.get(skill, 0.0) > 0.0:
		return
	if skill.resource_cost > 0 and _resource_current < float(skill.resource_cost):
		return
	_cooldowns[skill] = skill.cooldown
	if skill.resource_cost > 0:
		_spend_resource(skill.resource_cost)
	var aim := _aim_direction()
	AttackIndicator.spawn(self, skill, aim)
	if skill.wind_up > 0.0:
		await get_tree().create_timer(skill.wind_up).timeout
		if not is_instance_valid(self) or not _alive:
			return
	_resolve_skill_hit(skill, aim)

func _spend_resource(amount: int) -> void:
	if resource_pool == null:
		return
	_resource_current = maxf(0.0, _resource_current - float(amount))
	_emit_resource_if_changed()

func _tick_resource_regen(delta: float) -> void:
	if resource_pool == null or resource_pool.regen_per_sec <= 0.0:
		return
	if _resource_current >= float(resource_pool.max_value):
		return
	_resource_current = minf(float(resource_pool.max_value), _resource_current + resource_pool.regen_per_sec * delta)
	_emit_resource_if_changed()

func _emit_resource_if_changed() -> void:
	var new_int := int(_resource_current)
	if new_int != _resource_last_int:
		_resource_last_int = new_int
		resource_changed.emit(new_int, resource_pool.max_value)

func _resolve_skill_hit(skill: Skill, aim: Vector2) -> void:
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			var target := _find_enemy_in_cone(aim, skill.range, skill.cone_deg)
			if target:
				target.take_damage(skill.damage, global_position, skill.knockback)
		Skill.TargetingMode.AOE_RADIAL:
			for enemy in get_tree().get_nodes_in_group(&"enemies"):
				if global_position.distance_to(enemy.global_position) <= skill.range:
					enemy.take_damage(skill.damage, global_position, skill.knockback)

func _tick_cooldowns(delta: float) -> void:
	for skill in _cooldowns.keys():
		_cooldowns[skill] = maxf(0.0, _cooldowns[skill] - delta)

func get_cooldown_ratio(skill: Skill) -> float:
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	var remaining: float = _cooldowns.get(skill, 0.0)
	return clampf(remaining / skill.cooldown, 0.0, 1.0)

func _aim_direction() -> Vector2:
	var to_cursor := get_global_mouse_position() - global_position
	if to_cursor.length_squared() < 0.0001:
		return Vector2.RIGHT
	return to_cursor.normalized()

func _update_facing(aim: Vector2) -> void:
	if visual == null:
		return
	if aim.x > 0.05:
		visual.flip_h = false
	elif aim.x < -0.05:
		visual.flip_h = true

func _find_enemy_in_cone(aim: Vector2, max_distance: float, cone_deg: float) -> Node2D:
	var half_cone_cos := cos(deg_to_rad(cone_deg * 0.5))
	var nearest: Node2D = null
	var nearest_dist := max_distance
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		var to_enemy: Vector2 = enemy.global_position - global_position
		var dist := to_enemy.length()
		if dist > max_distance or dist < 0.0001:
			continue
		if aim.dot(to_enemy / dist) < half_cone_cos:
			continue
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist
	return nearest

func _die() -> void:
	_alive = false
	velocity = Vector2.ZERO
	if visual:
		visual.modulate = Color(0.3, 0.3, 0.3, 0.5)
	died.emit()
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_instance_valid(self):
		return
	_respawn()

func _respawn() -> void:
	current_health = MAX_HEALTH
	_alive = true
	if visual:
		visual.modulate = Color.WHITE
	health_changed.emit(current_health, MAX_HEALTH)
	if resource_pool != null:
		_resource_current = float(resource_pool.start_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)

func _flash() -> void:
	if visual == null:
		return
	visual.modulate = Color(1.0, 0.4, 0.4, 1.0)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(visual) and _alive:
		visual.modulate = Color.WHITE
