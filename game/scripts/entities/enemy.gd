extends CharacterBody2D
class_name Enemy

signal died

const AGGRO_RANGE := 250.0
const KNOCKBACK_DURATION := 0.12
const DEATH_DURATION := 0.25

@export var speed: float = 140.0
@export var max_health: int = 100
@export var attack: Skill

var current_health: int
var _attack_cd := 0.0
var _knockback_velocity := Vector2.ZERO
var _knockback_remaining := 0.0
var _dying := false

@onready var visual: Sprite2D = $Visual
@onready var health_bar: HealthBar = $HealthBar

func _enter_tree() -> void:
	add_to_group(&"enemies")

func _ready() -> void:
	current_health = max_health
	health_bar.set_health(current_health, max_health)

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_knockback_remaining = maxf(0.0, _knockback_remaining - delta)

	if _knockback_remaining > 0.0:
		velocity = _knockback_velocity
		move_and_slide()
		return

	var player := _find_player()
	if player == null or attack == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()

	if dist <= attack.range:
		velocity = Vector2.ZERO
		if _attack_cd <= 0.0 and player.has_method(&"take_damage"):
			_cast_attack(to_player.normalized(), player)
	elif dist <= AGGRO_RANGE:
		velocity = to_player.normalized() * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

func _cast_attack(aim: Vector2, player: Node) -> void:
	_attack_cd = attack.cooldown
	AttackIndicator.spawn(self, attack, aim)
	if attack.wind_up > 0.0:
		await get_tree().create_timer(attack.wind_up).timeout
		if not is_instance_valid(self) or not is_instance_valid(player):
			return
	var to_player: Vector2 = player.global_position - global_position
	if to_player.length() > attack.range:
		return
	if attack.targeting_mode == Skill.TargetingMode.SINGLE_CONE:
		var half_cos := cos(deg_to_rad(attack.cone_deg * 0.5))
		if aim.dot(to_player.normalized()) < half_cos:
			return
	if player.has_method(&"take_damage"):
		player.take_damage(attack.damage, global_position, attack.knockback)

func take_damage(amount: int, knockback_from: Vector2 = Vector2.ZERO, knockback_strength: float = 0.0) -> void:
	if _dying:
		return
	current_health -= amount
	_flash()
	_apply_knockback(knockback_from, knockback_strength)
	health_bar.set_health(current_health, max_health)
	if current_health <= 0:
		_die()

func _die() -> void:
	_dying = true
	died.emit()
	set_physics_process(false)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, DEATH_DURATION)
	if visual != null:
		tween.tween_property(visual, "scale", visual.scale * 1.25, DEATH_DURATION)
	await tween.finished
	queue_free()

func _apply_knockback(source: Vector2, strength: float) -> void:
	if strength <= 0.0:
		return
	var offset := global_position - source
	if offset.length_squared() < 0.0001:
		return
	_knockback_velocity = offset.normalized() * strength
	_knockback_remaining = KNOCKBACK_DURATION

func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group(&"player")
	return players[0] if players.size() > 0 else null

func _flash() -> void:
	if visual == null:
		return
	visual.modulate = Color(1.0, 0.4, 0.4, 1.0)
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(visual):
		visual.modulate = Color.WHITE
