extends CharacterBody2D
class_name Enemy

signal died

const AGGRO_RANGE := 250.0
const CONTACT_RANGE := 40.0
const CONTACT_DAMAGE := 10
const ATTACK_COOLDOWN := 1.0

@export var speed: float = 140.0
@export var max_health: int = 100
@export var display_name: String = "Enemy"

var current_health: int
var _attack_cd := 0.0

@onready var visual: Sprite2D = $Visual
@onready var health_bar: HealthBar = $HealthBar

func _enter_tree() -> void:
	add_to_group(&"enemies")

func _ready() -> void:
	current_health = max_health
	health_bar.set_health(current_health, max_health)
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	var hud := _get_hud()
	if hud != null:
		hud.show_tooltip(display_name)

func _on_mouse_exited() -> void:
	var hud := _get_hud()
	if hud != null:
		hud.hide_tooltip()

func _get_hud() -> Node:
	var nodes := get_tree().get_nodes_in_group(&"hud")
	return nodes[0] if nodes.size() > 0 else null

func _physics_process(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)

	var player := _find_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()

	if dist <= CONTACT_RANGE:
		velocity = Vector2.ZERO
		if _attack_cd <= 0.0 and player.has_method(&"take_damage"):
			_attack_cd = ATTACK_COOLDOWN
			player.take_damage(CONTACT_DAMAGE)
	elif dist <= AGGRO_RANGE:
		velocity = to_player.normalized() * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()

func take_damage(amount: int) -> void:
	current_health -= amount
	_flash()
	health_bar.set_health(current_health, max_health)
	if current_health <= 0:
		var hud := _get_hud()
		if hud != null:
			hud.hide_tooltip()
		died.emit()
		queue_free()

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
