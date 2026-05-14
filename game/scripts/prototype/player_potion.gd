class_name PlayerPotion
extends Node

## Health potion system — origin-specific consumable (Stimpack / Battery).
## 3 charges, 30s recharge per charge, heals over time. Modeled after
## PlayerGrenade: setup/tick/activate pattern, player owns the live state.

const MAX_CHARGES := 3
const RECHARGE_TIME := 30.0
const USE_COOLDOWN := 1.0
const HOT_INTERVAL := 0.5

var _host: PrototypePlayer
var _charges: int = MAX_CHARGES
var _recharge_timer: float = 0.0
var _use_cooldown: float = 0.0
var _hot_remain: float = 0.0
var _hot_per_tick: float = 0.0
var _hot_tick_timer: float = 0.0
# Accumulates the fractional HP that round() drops each tick. With a
# small heal_total (e.g. 10% of 60 HP = 6) spread across 12 ticks the
# per-tick amount is 0.5, which alternates 0/1 under naive rounding and
# under-delivers. Carrying the remainder forward guarantees we heal the
# full amount promised by the tooltip.
var _hot_carry: float = 0.0


func setup(host: PrototypePlayer) -> void:
	_host = host


# ── Queries ───────────────────────────────────────────────────────────────────

func is_potion_skill(skill: Skill) -> bool:
	return skill.active_kind == Skill.ActiveKind.POTION


func is_on_cooldown() -> bool:
	return _use_cooldown > 0.0 or _charges <= 0


func get_cooldown_ratio(_skill: Skill) -> float:
	# Per-use cooldown takes priority while active.
	if _use_cooldown > 0.0:
		return clampf(_use_cooldown / USE_COOLDOWN, 0.0, 1.0)
	# No charges — show recharge progress.
	if _charges <= 0 and RECHARGE_TIME > 0.0:
		return clampf(_recharge_timer / RECHARGE_TIME, 0.0, 1.0)
	return 0.0


func get_cooldown_remain(_skill: Skill) -> float:
	if _use_cooldown > 0.0:
		return _use_cooldown
	if _charges <= 0:
		return maxf(_recharge_timer, 0.0)
	return 0.0


func get_charges() -> int:
	return _charges


func get_heal_remaining() -> int:
	if _hot_remain <= 0.0 or _hot_per_tick <= 0.0:
		return 0
	var ticks_left := int(ceil(_hot_remain / HOT_INTERVAL))
	return int(round(_hot_per_tick * float(ticks_left)))


# ── Tick ──────────────────────────────────────────────────────────────────────

func tick(delta: float) -> void:
	# Per-use cooldown.
	if _use_cooldown > 0.0:
		_use_cooldown = maxf(0.0, _use_cooldown - delta)

	# Charge recharge — one at a time.
	if _charges < MAX_CHARGES:
		_recharge_timer -= delta
		if _recharge_timer <= 0.0:
			_charges += 1
			if _charges < MAX_CHARGES:
				_recharge_timer = RECHARGE_TIME

	# HoT ticking.
	if _hot_remain > 0.0:
		_hot_tick_timer -= delta
		if _hot_tick_timer <= 0.0:
			_hot_tick_timer += HOT_INTERVAL
			# Carry the fractional remainder forward so 0.5/tick still
			# heals the full 0.5 each tick instead of round()-ing to zero.
			_hot_carry += _hot_per_tick
			var heal_amt := int(floor(_hot_carry))
			if heal_amt > 0:
				_host.heal(heal_amt)
				_hot_carry -= float(heal_amt)
		_hot_remain -= delta
		if _hot_remain <= 0.0:
			# Flush any sub-1 HP carry on the final tick so the total
			# heal lands at full pct value, not pct - <1.
			if _hot_carry >= 0.5:
				_host.heal(1)
			_hot_remain = 0.0
			_hot_per_tick = 0.0
			_hot_carry = 0.0


# ── Activation ────────────────────────────────────────────────────────────────

func activate(_skill: Skill) -> void:
	if _charges <= 0 or _use_cooldown > 0.0:
		return
	var consumable: Item = InventoryState.get_equipped(&"consumable")
	if consumable == null:
		return
	# heal_duration is rolled as float (0.0-5.0); get_modifier returns int
	# and would truncate a 2.5s duration to 2 (or 0.4s to 0). Read raw via
	# the dict so the HoT lasts exactly as long as the tooltip advertises.
	var heal_pct: float = float(consumable.stat_modifiers.get(&"heal_pct", 0))
	var heal_duration: float = float(consumable.stat_modifiers.get(&"heal_duration", 0.0))
	if heal_pct <= 0.0:
		return
	# Compute actual heal from percentage of max health.
	var heal_total: float = heal_pct * _host.max_health / 100.0
	if heal_duration < HOT_INTERVAL:
		# Instant heal — duration too short for even one tick.
		_host.heal(int(round(heal_total)))
		_hot_remain = 0.0
		_hot_per_tick = 0.0
		_hot_carry = 0.0
	else:
		# Start (or refresh) the HoT.
		var ticks := heal_duration / HOT_INTERVAL
		_hot_per_tick = heal_total / ticks
		_hot_remain = heal_duration
		_hot_tick_timer = HOT_INTERVAL
		_hot_carry = 0.0
	# Consume charge + start timers.
	_charges -= 1
	_use_cooldown = USE_COOLDOWN
	if _charges < MAX_CHARGES and _recharge_timer <= 0.0:
		_recharge_timer = RECHARGE_TIME


# ── Cleanup ───────────────────────────────────────────────────────────────────

func cleanup() -> void:
	_charges = MAX_CHARGES
	_recharge_timer = 0.0
	_use_cooldown = 0.0
	_hot_remain = 0.0
	_hot_per_tick = 0.0
	_hot_carry = 0.0
