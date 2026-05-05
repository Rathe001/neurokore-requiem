class_name PlayerGrenade
extends Node

## Grenade offhand system — throws an arcing AoE projectile at the cursor
## position. Manages its own cooldown (like PlayerShield). Resource cost
## is handled by the player before calling activate().

const GRENADE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_grenade.tscn")
const MAX_THROW_RANGE := 12.0

var _host: PrototypePlayer
var _cooldown_remain: float = 0.0
var _cooldown_total: float = 0.0


func setup(host: PrototypePlayer) -> void:
	_host = host


# ── Queries ───────────────────────────────────────────────────────────────────

func is_grenade_skill(skill: Skill) -> bool:
	return skill.active_kind == Skill.ActiveKind.GRENADE


func is_on_cooldown() -> bool:
	return _cooldown_remain > 0.0


func get_cooldown_ratio(_skill: Skill) -> float:
	if _cooldown_total <= 0.0:
		return 0.0
	return clampf(_cooldown_remain / _cooldown_total, 0.0, 1.0)


func get_cooldown_remain(_skill: Skill) -> float:
	return maxf(_cooldown_remain, 0.0)


# ── Tick ──────────────────────────────────────────────────────────────────────

func tick(delta: float) -> void:
	if _cooldown_remain > 0.0:
		_cooldown_remain = maxf(0.0, _cooldown_remain - delta)


# ── Activation ────────────────────────────────────────────────────────────────

func activate(skill: Skill, cursor_offset: Vector3) -> void:
	if _cooldown_remain > 0.0:
		return
	if cursor_offset.length_squared() < 0.0001:
		return
	var max_sq := MAX_THROW_RANGE * MAX_THROW_RANGE
	if cursor_offset.length_squared() > max_sq:
		cursor_offset = cursor_offset.normalized() * MAX_THROW_RANGE
	var offhand: Item = InventoryState.get_equipped(&"offhand")
	var grenade: PrototypeGrenade = EntityPool.acquire(GRENADE_SCENE) as PrototypeGrenade
	grenade.target_position = _host.global_position + cursor_offset
	if offhand != null and offhand.damage_max > 0:
		grenade.damage_min = offhand.damage_min
		grenade.damage_max = offhand.damage_max
		grenade.crit_chance = offhand.crit_chance
	else:
		grenade.damage_min = skill.damage
		grenade.damage_max = skill.damage
	if offhand != null and offhand.blast_radius > 0.0:
		grenade.blast_radius = offhand.blast_radius
	else:
		grenade.blast_radius = skill.blast_radius
	grenade.damage_mult = 1.0
	grenade.knockback = skill.knockback
	grenade.grenade_type = skill.grenade_type
	grenade.source_position = _host.global_position
	_host.get_parent().add_child(grenade)
	grenade.global_position = _host.global_position + Vector3(0.0, 1.2, 0.0)
	_cooldown_total = maxf(skill.cooldown, 0.1)
	_cooldown_remain = _cooldown_total


# ── Cleanup ───────────────────────────────────────────────────────────────────

func cleanup() -> void:
	_cooldown_remain = 0.0
	_cooldown_total = 0.0
