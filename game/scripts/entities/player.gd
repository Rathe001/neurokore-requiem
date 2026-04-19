extends CharacterBody2D
class_name Player

signal health_changed(current: int, max_value: int)
signal died

const SPEED := 240.0
const MAX_HEALTH := 100
const RESPAWN_DELAY := 2.0

@export var single_skill: Skill
@export var aoe_skill: Skill

var current_health: int
var _cooldowns: Dictionary = {}
var _alive := true

@onready var visual: Sprite2D = $Visual

func _ready() -> void:
	current_health = MAX_HEALTH
	add_to_group(&"player")
	health_changed.emit(current_health, MAX_HEALTH)

func _physics_process(delta: float) -> void:
	if not _alive:
		return

	_tick_cooldowns(delta)

	var input_vector := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = input_vector * SPEED
	move_and_slide()

	_update_facing(_aim_direction())

	if Input.is_action_pressed(&"attack_single"):
		_cast_skill(single_skill)
	elif Input.is_action_pressed(&"attack_aoe"):
		_cast_skill(aoe_skill)

func take_damage(amount: int) -> void:
	if not _alive:
		return
	current_health -= amount
	_flash()
	health_changed.emit(current_health, MAX_HEALTH)
	if current_health <= 0:
		_die()

func _cast_skill(skill: Skill) -> void:
	if skill == null:
		return
	if _cooldowns.get(skill, 0.0) > 0.0:
		return
	_cooldowns[skill] = skill.cooldown
	var aim := _aim_direction()
	AttackIndicator.spawn(self, skill, aim)
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			var target := _find_enemy_in_cone(aim, skill.range, skill.cone_deg)
			if target:
				target.take_damage(skill.damage)
		Skill.TargetingMode.AOE_RADIAL:
			for enemy in get_tree().get_nodes_in_group(&"enemies"):
				if global_position.distance_to(enemy.global_position) <= skill.range:
					enemy.take_damage(skill.damage)

func _tick_cooldowns(delta: float) -> void:
	for skill in _cooldowns.keys():
		_cooldowns[skill] = maxf(0.0, _cooldowns[skill] - delta)

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

func _flash() -> void:
	if visual == null:
		return
	visual.modulate = Color(1.0, 0.4, 0.4, 1.0)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(visual) and _alive:
		visual.modulate = Color.WHITE
