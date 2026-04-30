extends Area3D
class_name PrototypeProjectile

const PROTO_BASE_CRIT_CHANCE: float = 0.15
const PROTO_BASE_CRIT_MULT: float = 1.5

var direction: Vector3 = Vector3.FORWARD
var speed: float = 30.0
var max_range: float = 20.0
var damage_min: int = 0
var damage_max: int = 0
var damage_mult: float = 1.0
var accuracy: float = 1.0
var crit_chance: float = 0.0
var knockback_strength: float = 0.0
var source_position: Vector3 = Vector3.ZERO

var _traveled: float = 0.0
var _hit: bool = false
var _connected: bool = false

func _ready() -> void:
	_connect_signal()

func _connect_signal() -> void:
	if not _connected:
		body_entered.connect(_on_body_entered)
		_connected = true

func reset() -> void:
	_traveled = 0.0
	_hit = false
	set_physics_process(true)
	_connect_signal()

func _pool_release() -> void:
	_traveled = 0.0
	_hit = false
	monitoring = false

func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += direction * step
	_traveled += step
	if _traveled >= max_range:
		_release()

func _on_body_entered(body: Node3D) -> void:
	if _hit:
		return
	if not body.is_in_group(&"enemies"):
		return
	if not body.has_method(&"take_damage"):
		return
	_hit = true
	if _roll_hit():
		var is_crit := _roll_crit()
		var dmg := _roll_damage(is_crit)
		body.take_damage(dmg, source_position, knockback_strength, 1, is_crit)
	_release()

func _release() -> void:
	monitoring = false
	EntityPool.release(self)

func _roll_hit() -> bool:
	if accuracy >= 1.0:
		return true
	return randf() < accuracy

func _roll_crit() -> bool:
	var base := crit_chance if crit_chance > 0.0 else PROTO_BASE_CRIT_CHANCE
	var chance := base + PerkState.get_aggregate(&"crit_chance_pct")
	return randf() < chance

func _roll_damage(is_crit: bool) -> int:
	var base := randi_range(damage_min, damage_max) if damage_max > 0 else 10
	var dmg := int(round(float(base) * damage_mult))
	if is_crit:
		var mult := PROTO_BASE_CRIT_MULT + PerkState.get_aggregate(&"crit_damage_pct")
		dmg = int(round(float(dmg) * mult))
	return dmg
