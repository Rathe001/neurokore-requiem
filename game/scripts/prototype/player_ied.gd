class_name PlayerIED
extends Node

## Survivalist IED — every LMB attack tosses a trap at the cursor while
## the perk is active. The active set is FIFO-capped at the perk aggregate;
## a trap detonates when an enemy enters its proximity radius or after 15s
## idle. Higher tiers shorten the arming window.

const IED_TRAP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_trap.tscn")
const IED_MAX_TRAPS_CAP := 8
const IED_ARM_DELAY_BY_TIER: Array[float] = [0.0, 2.0, 1.2, 0.6]
const IED_MAX_PLACEMENT_RANGE := 8.0

var _host: PrototypePlayer
var _ied_traps: Array[PrototypeTrap] = []


func setup(host: PrototypePlayer) -> void:
	_host = host


func get_trap_count() -> int:
	return _ied_traps.size()


func get_trap_max() -> int:
	return mini(int(round(Effects.get_aggregate(&"ied_max_traps"))), IED_MAX_TRAPS_CAP)


func toss_trap(cursor_offset: Vector3) -> void:
	if not _host.is_alive():
		return
	var max_traps := mini(int(round(Effects.get_aggregate(&"ied_max_traps"))), IED_MAX_TRAPS_CAP)
	if max_traps <= 0:
		return
	if cursor_offset.length_squared() < 0.0001:
		return
	var max_sq := IED_MAX_PLACEMENT_RANGE * IED_MAX_PLACEMENT_RANGE
	if cursor_offset.length_squared() > max_sq:
		cursor_offset = cursor_offset.normalized() * IED_MAX_PLACEMENT_RANGE
	var live: Array[PrototypeTrap] = []
	for t in _ied_traps:
		if t != null and is_instance_valid(t):
			live.append(t)
	_ied_traps = live
	while _ied_traps.size() >= max_traps:
		var oldest: PrototypeTrap = _ied_traps.pop_front()
		if oldest != null and is_instance_valid(oldest):
			oldest.queue_free()
	var tier := AttributeState.get_unlocked_tier(&"ing", PlayerState.class_id, PlayerState.spec_id)
	var arm_delay: float = IED_ARM_DELAY_BY_TIER[clampi(tier, 1, IED_ARM_DELAY_BY_TIER.size() - 1)]
	var trap: PrototypeTrap = IED_TRAP_SCENE.instantiate()
	trap.arm_delay = arm_delay
	_host.get_parent().add_child(trap)
	trap.global_position = _host.global_position + cursor_offset
	_ied_traps.append(trap)


func cleanup() -> void:
	for t in _ied_traps:
		if t != null and is_instance_valid(t):
			t.queue_free()
	_ied_traps.clear()
