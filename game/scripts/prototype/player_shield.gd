class_name PlayerShield
extends Node

## Active offhand shield system — handles both SHIELD_BUFF (duration-based
## partial damage reduction) and SHIELD_HOLD (held full block until break
## or release). Manages pool, duration, cooldown, and movement speed factor.

const SHIELD_HOLD_SPEED_FACTOR := 0.2

var _host: PrototypePlayer

var _active: bool = false
var _pool: int = 0
var _pool_max: int = 0
var _reduction: float = 0.0
var _cooldown_remain: float = 0.0
var _cooldown_total: float = 0.0
var _duration_remain: float = 0.0
var _kind: Skill.ActiveKind = Skill.ActiveKind.NONE


func setup(host: PrototypePlayer) -> void:
	_host = host


# ── Queries ───────────────────────────────────────────────────────────────────

func is_shield_skill(skill: Skill) -> bool:
	return skill.active_kind == Skill.ActiveKind.SHIELD_BUFF or skill.active_kind == Skill.ActiveKind.SHIELD_HOLD


func get_shield_buff_kind() -> Skill.ActiveKind:
	return _kind


func get_shield_buff_state() -> Dictionary:
	return {
		"active": _active,
		"pool": _pool,
		"pool_max": _pool_max,
		"reduction": _reduction,
		"cooldown_remain": _cooldown_remain,
		"cooldown_total": _cooldown_total,
		"duration_remain": _duration_remain,
	}


func get_speed_factor() -> float:
	if _active and _kind == Skill.ActiveKind.SHIELD_HOLD:
		return SHIELD_HOLD_SPEED_FACTOR
	return 1.0


func get_cooldown_ratio(skill: Skill) -> float:
	if _cooldown_total <= 0.0:
		return 0.0
	return clampf(_cooldown_remain / _cooldown_total, 0.0, 1.0)


func get_cooldown_remain(_skill: Skill) -> float:
	return maxf(_cooldown_remain, 0.0)


# ── Damage absorption ─────────────────────────────────────────────────────────

## Returns {"amount": reduced_damage, "knockback": reduced_knockback}.
func absorb_damage(amount: int, knockback_strength: float) -> Dictionary:
	if _active and knockback_strength > 0.0:
		match _kind:
			Skill.ActiveKind.SHIELD_HOLD:
				knockback_strength = 0.0
			Skill.ActiveKind.SHIELD_BUFF:
				knockback_strength *= maxf(1.0 - _reduction, 0.0)
	if _active and _reduction > 0.0:
		var absorbed: int = mini(int(ceil(float(amount) * _reduction)), _pool)
		amount = maxi(amount - absorbed, 0)
		_pool -= absorbed
		if _pool <= 0:
			_break()
		else:
			_emit_changed()
	return {"amount": amount, "knockback": knockback_strength}


# ── Tick ──────────────────────────────────────────────────────────────────────

func tick(delta: float) -> void:
	if _active:
		match _kind:
			Skill.ActiveKind.SHIELD_BUFF:
				_duration_remain -= delta
				if _duration_remain <= 0.0:
					_expire()
			Skill.ActiveKind.SHIELD_HOLD:
				if not Input.is_action_pressed(&"alt_fire"):
					_release_hold()
	elif _cooldown_remain > 0.0:
		_cooldown_remain = maxf(0.0, _cooldown_remain - delta)
		if _cooldown_remain <= 0.0:
			_emit_changed()


# ── Activation ────────────────────────────────────────────────────────────────

func activate_offhand_skill(skill: Skill) -> void:
	match skill.active_kind:
		Skill.ActiveKind.SHIELD_BUFF, Skill.ActiveKind.SHIELD_HOLD:
			_activate(skill)
		_:
			pass


func _activate(skill: Skill) -> void:
	if _active:
		return
	if _cooldown_remain > 0.0:
		return
	var bonus_pool: int = 0
	var offhand: Item = InventoryState.get_equipped(&"offhand")
	if offhand != null:
		bonus_pool = offhand.get_modifier(&"shield_pool_bonus")
	var fresh_pool_max := maxi(skill.shield_pool + bonus_pool, 1)
	var refresh_pool := false
	if skill.active_kind == Skill.ActiveKind.SHIELD_BUFF:
		refresh_pool = true
		_reduction = clampf(skill.damage_reduction, 0.0, 1.0)
		_duration_remain = maxf(skill.duration, 0.1)
	else:
		refresh_pool = _pool <= 0
		_reduction = 1.0
		_duration_remain = 0.0
	if refresh_pool:
		_pool_max = fresh_pool_max
		_pool = fresh_pool_max
	_cooldown_total = maxf(skill.cooldown, 0.1)
	_kind = skill.active_kind
	_active = true
	_emit_changed()


# ── State transitions ─────────────────────────────────────────────────────────

func _release_hold() -> void:
	if not _active or _kind != Skill.ActiveKind.SHIELD_HOLD:
		return
	_active = false
	_emit_changed()


func _break() -> void:
	_active = false
	_pool = 0
	_duration_remain = 0.0
	_cooldown_remain = _cooldown_total
	_emit_changed()


func _expire() -> void:
	_active = false
	_pool = 0
	_duration_remain = 0.0
	_emit_changed()


func cleanup() -> void:
	if not _active and _pool_max == 0 and _cooldown_remain <= 0.0:
		return
	_active = false
	_pool = 0
	_pool_max = 0
	_reduction = 0.0
	_cooldown_remain = 0.0
	_cooldown_total = 0.0
	_duration_remain = 0.0
	_kind = Skill.ActiveKind.NONE
	_emit_changed()


func _emit_changed() -> void:
	_host.shield_buff_changed.emit(_active, _pool, _pool_max, _reduction, _cooldown_remain, _cooldown_total, _duration_remain)
