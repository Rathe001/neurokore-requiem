class_name PlayerTelekinesis
extends Node

## Polymath Telekinesis — auto-fires grabbing bolts at a fixed cadence when
## the perk aggregate is > 0. Each bolt picks a distinct enemy in range,
## spawns a TelekinesisGrab that lifts → slams → deals AoE damage on impact.
## Bolt count comes from Effects.get_aggregate(&"telekinesis_bolts"), capped
## at TELEKINESIS_MAX_BOLTS.

const TELEKINESIS_INTERVAL := 6.0
const TELEKINESIS_RANGE := 12.0
const TELEKINESIS_BASE_DAMAGE := 13
const TELEKINESIS_BOLT_STAGGER := 0.12
const TELEKINESIS_MAX_BOLTS := 8

var _host: PrototypePlayer
var _telekinesis_t: float = 0.0


func setup(host: PrototypePlayer) -> void:
	_host = host


func tick(delta: float) -> void:
	if not _host.is_alive():
		return
	var bolts := mini(int(round(Effects.get_aggregate(&"telekinesis_bolts"))), TELEKINESIS_MAX_BOLTS)
	if bolts <= 0:
		return
	_telekinesis_t -= delta
	if _telekinesis_t > 0.0:
		return
	_telekinesis_t = TELEKINESIS_INTERVAL
	var targets := _pick_targets(bolts)
	if targets.is_empty():
		return
	var dmg := int(round(float(TELEKINESIS_BASE_DAMAGE) * AttributeState.get_player_damage_mult(_host.class_id, _host.spec_id)))
	for i in targets.size():
		var captured_target: Node3D = targets[i]
		if i == 0:
			_spawn_grab(captured_target, dmg)
		else:
			_host.get_tree().create_timer(TELEKINESIS_BOLT_STAGGER * float(i)).timeout.connect(
				func() -> void: _spawn_grab(captured_target, dmg),
				CONNECT_ONE_SHOT)


func _pick_targets(count: int) -> Array[Node3D]:
	var pool: Array[Node3D] = []
	for n in SpatialGrid.query_radius(_host.global_position, TELEKINESIS_RANGE, &"enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method(&"apply_grab"):
			continue
		if n.has_method(&"is_player_friendly") and n.is_player_friendly():
			continue
		if not LosCuller.has_los_to_player(n):
			continue
		pool.append(n)
	if pool.is_empty():
		return []
	pool.shuffle()
	if pool.size() <= count:
		return pool
	return pool.slice(0, count)


func _spawn_grab(target: Node3D, dmg: int) -> void:
	if not _host.is_alive() or target == null or not is_instance_valid(target):
		return
	var grab := TelekinesisGrab.new()
	grab.setup(_host, target, dmg)
	_host.get_parent().add_child(grab)
