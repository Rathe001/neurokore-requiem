extends CharacterBody2D
class_name Player

const SPEED := 240.0
const MAX_HEALTH := 100

const SINGLE_ATTACK_RANGE := 80.0
const SINGLE_ATTACK_DAMAGE := 25
const SINGLE_ATTACK_COOLDOWN := 0.3

const AOE_ATTACK_RANGE := 120.0
const AOE_ATTACK_DAMAGE := 15
const AOE_ATTACK_COOLDOWN := 0.5

const RESPAWN_DELAY := 2.0

var current_health: int
var _single_cd := 0.0
var _aoe_cd := 0.0
var _alive := true

@onready var visual: Polygon2D = $Visual
@onready var health_bar: HealthBar = $HealthBar

func _ready() -> void:
	current_health = MAX_HEALTH
	add_to_group(&"player")
	health_bar.set_health(current_health, MAX_HEALTH)

func _physics_process(delta: float) -> void:
	if not _alive:
		return

	_single_cd = maxf(0.0, _single_cd - delta)
	_aoe_cd = maxf(0.0, _aoe_cd - delta)

	var input_vector := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	velocity = input_vector * SPEED
	move_and_slide()

	if Input.is_action_pressed(&"attack_single"):
		_attack_single()
	elif Input.is_action_pressed(&"attack_aoe"):
		_attack_aoe()

func take_damage(amount: int) -> void:
	if not _alive:
		return
	current_health -= amount
	_flash()
	health_bar.set_health(current_health, MAX_HEALTH)
	if current_health <= 0:
		_die()

func _attack_single() -> void:
	if _single_cd > 0.0:
		return
	_single_cd = SINGLE_ATTACK_COOLDOWN
	var target := _find_nearest_enemy(SINGLE_ATTACK_RANGE)
	if target:
		target.take_damage(SINGLE_ATTACK_DAMAGE)

func _attack_aoe() -> void:
	if _aoe_cd > 0.0:
		return
	_aoe_cd = AOE_ATTACK_COOLDOWN
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if global_position.distance_to(enemy.global_position) <= AOE_ATTACK_RANGE:
			enemy.take_damage(AOE_ATTACK_DAMAGE)

func _find_nearest_enemy(max_distance: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := max_distance
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		var dist := global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist
	return nearest

func _die() -> void:
	_alive = false
	velocity = Vector2.ZERO
	if visual:
		visual.color = Color(0.3, 0.3, 0.3, 0.5)
	print("You died. Restarting in ", RESPAWN_DELAY, "s...")
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	get_tree().reload_current_scene()

func _flash() -> void:
	if visual == null:
		return
	var original_color := visual.color
	visual.color = Color.WHITE
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(visual):
		visual.color = original_color
