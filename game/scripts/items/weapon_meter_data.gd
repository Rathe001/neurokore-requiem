class_name WeaponMeterData
extends RefCounted

# Static utility that computes visual meter-bar data for weapon tooltips.
# Each bar is normalized to [0,1] within the archetype+rarity range — the
# bar itself IS the range of possible rolls for this weapon type. Values
# below 0 (from item-level decay) are clamped and flagged as decayed.
#
# Public API:
#   WeaponMeterData.compute(item) -> Array[MeterBar]

# ── Return type ─────────────────────────────────────────────────────────────

class MeterBar:
	var id: StringName
	var label: String
	var value: float          # Normalized [0,1] in archetype range
	var decayed_value: float = -1.0  # Normalized [0,1] effective value after decay; -1 = no decay
	var boosted_value: float = -1.0  # Normalized [0,1] effective value when boosted; -1 = no boost
	var number_text: String   # Formatted raw value for shift-overlay

# ── Bar IDs ─────────────────────────────────────────────────────────────────

const BAR_POWER_ST := &"power_st"
const BAR_FIRE_RATE := &"fire_rate"
const BAR_CAPACITY := &"capacity"
const BAR_RELOAD := &"reload"

const BAR_ORDER: Array[StringName] = [
	BAR_POWER_ST, BAR_FIRE_RATE,
	BAR_CAPACITY, BAR_RELOAD,
]
const BAR_LABELS: Dictionary = {
	BAR_POWER_ST: "Power",
	BAR_FIRE_RATE: "Fire Rate",
	BAR_CAPACITY: "Capacity",
	BAR_RELOAD: "Reload",
}

# Signature stat display config: label, format string, whether it's a percentage
# value, whether it decays with effective_multiplier, and whether lower is better.
const _SIG_DISPLAY: Dictionary = {
	&"blast_radius_bonus": { "label": "Blast",       "fmt": "+%d m",    "pct": false, "decays": false },
	&"pellet_count":       { "label": "Pellets",     "fmt": "%d",       "pct": false, "decays": false },
	&"spread_angle":       { "label": "Spread",      "fmt": "%d°",      "pct": false, "decays": false, "inverse": true },
	&"penetration":        { "label": "Penetrate",   "fmt": "%d",       "pct": false, "decays": false },
	&"headshot_bonus":     { "label": "Headshot",    "fmt": "+%.1f%%",  "pct": true,  "decays": true },
	&"chain_retention":    { "label": "Chain Ret.",   "fmt": "%.1f%%",   "pct": true,  "decays": true },
	&"chain_targets":      { "label": "Chains",      "fmt": "%d",       "pct": false, "decays": false },
	&"ramp_speed":         { "label": "Ramp",        "fmt": "+%.1f%%",  "pct": true,  "decays": true },
	&"bleed_damage":       { "label": "Bleed",       "fmt": "%d/tick",  "pct": false, "decays": true },
	&"impact_radius":      { "label": "Impact",      "fmt": "%d m",     "pct": false, "decays": false },
	&"sustained_bonus":    { "label": "Sustained",   "fmt": "+%.1f%%",  "pct": true,  "decays": true },
	&"ricochet_chance":    { "label": "Ricochet",    "fmt": "%.1f%%",   "pct": true,  "decays": true },
	&"overcharge_chance":  { "label": "Overcharge",  "fmt": "%.1f%%",   "pct": true,  "decays": true },
}

# ── Weapon base paths (mirrors ItemRoller.WEAPON_BASE_DROPS) ────────────────

const _BASE_PATHS: Array[String] = [
	"res://resources/items/weapon_bases/melee_1h.tres",
	"res://resources/items/weapon_bases/ranged_1h.tres",
	"res://resources/items/weapon_bases/smg_1h.tres",
	"res://resources/items/weapon_bases/melee_2h.tres",
	"res://resources/items/weapon_bases/ranged_2h.tres",
	"res://resources/items/weapon_bases/lmg_2h.tres",
	"res://resources/items/weapon_bases/sniper_2h.tres",
	"res://resources/items/weapon_bases/rpg_2h.tres",
	"res://resources/items/weapon_bases/shotgun_2h.tres",
	"res://resources/items/weapon_bases/accelerator_2h.tres",
	"res://resources/items/weapon_bases/taser_2h.tres",
]

const _RARITIES: Array[StringName] = [&"common", &"magic", &"rare", &"unique"]

# ── Precomputed archetype ranges ──────────────────────────────────────────
# Built once on first compute() call.
# _arch_ranges[base_id][rarity][bar_id] = Vector2(floor, ceil).

static var _arch_ranges: Dictionary = {}
static var _base_cache: Dictionary = {}
static var _ranges_built: bool = false


static func _get_base(path: String) -> WeaponBase:
	if _base_cache.has(path):
		return _base_cache[path]
	var base := load(path) as WeaponBase
	if base != null:
		_base_cache[path] = base
	return base


static func _ensure_ranges_built() -> void:
	if _ranges_built:
		return
	_ranges_built = true

	for path: String in _BASE_PATHS:
		var base := _get_base(path)
		if base == null:
			continue
		_arch_ranges[base.id] = {}
		for rarity: StringName in _RARITIES:
			_arch_ranges[base.id][rarity] = _compute_archetype_range(base, rarity)


# Compute the theoretical floor and ceil of each bar for a given base+rarity.
# Floor = all rolls at minimum. Ceil = all rolls at maximum × rarity budget.
static func _compute_archetype_range(base: WeaponBase, rarity: StringName) -> Dictionary:
	var budget: float = float(ItemRoller.RARITY_BUDGET_MULT.get(rarity, 1.0))
	var result: Dictionary = {}

	# ── Damage bounds ───────────────────────────────────────────────────
	var dmin_lo := base.damage_min_range.x * budget
	var dmin_hi := base.damage_min_range.y * budget
	var dmax_lo := base.damage_max_range.x * budget
	var dmax_hi := base.damage_max_range.y * budget
	var avg_lo := (dmin_lo + dmax_lo) * 0.5
	var avg_hi := (dmin_hi + dmax_hi) * 0.5

	# ── Fire rate bounds ────────────────────────────────────────────────
	var spd_lo := base.attack_speed_range.x
	var spd_hi := base.attack_speed_range.y
	var skill: Skill = base.fire_skill
	var fr_lo := spd_lo
	var fr_hi := spd_hi
	var pellet_lo := 1
	var pellet_hi := 1
	var dmg_mult := 1.0
	var is_channel := false

	if skill != null:
		pellet_lo = maxi(1, skill.pellet_count)
		pellet_hi = pellet_lo
		dmg_mult = maxf(0.01, skill.damage_multiplier)
		if skill.active_kind == Skill.ActiveKind.CHANNEL_BEAM:
			is_channel = true
			var interval := maxf(skill.channel_tick_interval, 0.05)
			fr_lo = 1.0 / interval
			fr_hi = fr_lo
		elif skill.cooldown > 0.0:
			fr_lo = spd_lo / skill.cooldown
			fr_hi = spd_hi / skill.cooldown

	# Add weapon signature pellet_count (additive with skill)
	var sigs: Array = ItemRoller.WEAPON_SIGNATURE_STATS.get(base.id, [])
	for sig: Dictionary in sigs:
		if sig["key"] == &"pellet_count":
			var sig_lo: int = sig["base"].x
			var sig_hi: int = int(round(float(sig["base"].y) * budget))
			pellet_lo += sig_lo
			pellet_hi += sig_hi

	# ── Crit (base 15% for all weapons with 0 intrinsic crit) ──────────
	var crit := 0.15
	var crit_mult := 1.5
	var crit_factor := 1.0 + crit * (crit_mult - 1.0)

	# ── Power (ST) ──────────────────────────────────────────────────────
	if is_channel:
		var per_tick := float(skill.damage)
		var dps_val := per_tick * fr_lo * crit_factor
		result[BAR_POWER_ST] = Vector2(dps_val, dps_val)
	else:
		var dps_lo := avg_lo * float(pellet_lo) * dmg_mult * fr_lo * crit_factor
		var dps_hi := avg_hi * float(pellet_hi) * dmg_mult * fr_hi * crit_factor
		result[BAR_POWER_ST] = Vector2(dps_lo, dps_hi)

	# ── Fire Rate ───────────────────────────────────────────────────────
	result[BAR_FIRE_RATE] = Vector2(fr_lo, fr_hi)

	# ── Capacity ────────────────────────────────────────────────────────
	if base.ammo_capacity_range.y > 0:
		var ammo_lo := float(base.ammo_capacity_range.x) * budget
		var ammo_hi := float(base.ammo_capacity_range.y) * budget
		result[BAR_CAPACITY] = Vector2(ammo_lo, ammo_hi)
	elif skill != null and skill.resource_cost > 0:
		var eff := 100.0 / float(maxi(1, skill.resource_cost))
		result[BAR_CAPACITY] = Vector2(eff, eff)
	else:
		# Melee / zero-cost — high efficiency
		result[BAR_CAPACITY] = Vector2(100.0, 100.0)

	# ── Reload ──────────────────────────────────────────────────────────
	if base.reload_time > 0.0:
		var inv := 1.0 / base.reload_time
		result[BAR_RELOAD] = Vector2(inv, inv)
	else:
		# Non-ammo weapons get a sentinel — bar is hidden for them
		result[BAR_RELOAD] = Vector2(-1.0, -1.0)

	return result


# ── Public API ──────────────────────────────────────────────────────────────

static func compute(item: Item) -> Array[MeterBar]:
	_ensure_ranges_built()

	var bars: Array[MeterBar] = []
	if item == null or item.weapon_base_id == &"":
		return bars

	var base_id := item.weapon_base_id
	var rarity := item.rarity if item.rarity != &"" else &"common"
	var arch: Dictionary = _arch_ranges.get(base_id, {}).get(rarity, {})
	if arch.is_empty():
		return bars

	# Compute raw values for this specific item
	var raw: Dictionary = _compute_item_values(item)
	var mult := item.effective_multiplier()
	# Power bars scale with effective_multiplier (damage-based).
	# Fire rate, capacity, reload are raw stats and don't scale.

	for bar_id: StringName in BAR_ORDER:
		# Skip reload bar for non-ammo weapons
		if bar_id == BAR_RELOAD and not item.is_bullet_weapon():
			continue
		var a: Vector2 = arch.get(bar_id, Vector2(0, 1))
		var raw_val: float = raw.get(bar_id, 0.0)
		# Skip bars with sentinel values
		if a.x < 0.0:
			continue
		# Skip bars with no rollable variance (fixed values)
		if absf(a.y - a.x) < 0.01:
			continue

		var bar := MeterBar.new()
		bar.id = bar_id
		bar.label = BAR_LABELS.get(bar_id, "")
		bar.value = _normalize(raw_val, a.x, a.y)
		bar.number_text = _format_value(bar_id, raw_val)
		# Decay/boost overlay for damage-based bars only
		if bar_id == BAR_POWER_ST:
			if mult < 1.0:
				bar.decayed_value = _normalize(raw_val * mult, a.x, a.y)
			elif mult > 1.0:
				bar.boosted_value = _normalize(raw_val * mult, a.x, a.y)
		bars.append(bar)

	# ── Signature stat bars (archetype-specific: ricochet, bleed, etc.) ──
	_append_signature_bars(item, bars, mult)

	return bars


# ── Signature stat bars ────────────────────────────────────────────────────

static func _append_signature_bars(item: Item, bars: Array[MeterBar], mult: float) -> void:
	var sigs: Array = ItemRoller.WEAPON_SIGNATURE_STATS.get(item.weapon_base_id, [])
	if sigs.is_empty():
		return
	var budget: float = float(ItemRoller.RARITY_BUDGET_MULT.get(item.rarity, 1.0))
	for sig: Dictionary in sigs:
		var key: StringName = sig["key"]
		var raw_int: int = int(item.stat_modifiers.get(key, 0))
		if raw_int == 0:
			continue
		var disp: Dictionary = _SIG_DISPLAY.get(key, {})
		if disp.is_empty():
			continue
		var base_range: Vector2i = sig["base"]
		var cap: float = float(sig.get("cap", 9999))
		var is_inverse: bool = sig.get("inverse", false)
		# Archetype range: floor is base.x * budget, ceil is base.y * budget (capped).
		# For inverse stats (lower = better), we flip so floor < ceil for normalization.
		var range_lo: float
		var range_hi: float
		if is_inverse:
			# Inverse: budget divides instead of multiplies, lower = better.
			range_hi = float(base_range.x) / budget  # best (lowest)
			range_lo = float(base_range.y)            # worst (highest)
		else:
			range_lo = float(base_range.x) * budget
			range_hi = minf(float(base_range.y) * budget, cap)
		# Skip zero-variance
		if absf(range_hi - range_lo) < 0.01:
			continue

		var raw_val: float = float(raw_int)
		var bar := MeterBar.new()
		bar.id = key
		bar.label = disp["label"]
		if is_inverse:
			# Inverse: lower raw = better = higher bar fill
			bar.value = _normalize(range_lo + range_hi - raw_val, range_lo, range_hi)
		else:
			bar.value = _normalize(raw_val, range_lo, range_hi)
		# Format number text
		if disp.get("pct", false):
			bar.number_text = disp["fmt"] % raw_val
		else:
			bar.number_text = disp["fmt"] % raw_int
		# Decay/boost overlay for combat-power sig stats
		if disp.get("decays", false):
			var scaled_val := raw_val * mult
			if mult < 1.0:
				if is_inverse:
					bar.decayed_value = _normalize(range_lo + range_hi - scaled_val, range_lo, range_hi)
				else:
					bar.decayed_value = _normalize(scaled_val, range_lo, range_hi)
			elif mult > 1.0:
				if is_inverse:
					bar.boosted_value = _normalize(range_lo + range_hi - scaled_val, range_lo, range_hi)
				else:
					bar.boosted_value = _normalize(scaled_val, range_lo, range_hi)
		bars.append(bar)


# ── Per-item value computation ──────────────────────────────────────────────

static func _compute_item_values(item: Item) -> Dictionary:
	var result: Dictionary = {}

	# Resolve fire skill from weapon base
	var skill := _resolve_item_fire_skill(item)
	var spd := item.attack_speed

	# ── Crit factor (raw, no decay) ─────────────────────────────────────
	var crit: float = item.crit_chance if item.crit_chance > 0.0 else 0.15
	var crit_factor := 1.0 + crit * (1.5 - 1.0)

	# ── Fire rate ───────────────────────────────────────────────────────
	var fire_rate := spd
	var is_channel := false
	var pellet_count := 1
	var dmg_mult := 1.0

	if skill != null:
		pellet_count = maxi(1, skill.pellet_count)
		dmg_mult = maxf(0.01, skill.damage_multiplier)
		if skill.active_kind == Skill.ActiveKind.CHANNEL_BEAM:
			is_channel = true
			fire_rate = 1.0 / maxf(skill.channel_tick_interval, 0.05)
		elif skill.cooldown > 0.0:
			fire_rate = spd / skill.cooldown

	# Add weapon signature pellet_count
	var sig_pellets: int = item.get_modifier(&"pellet_count")
	if sig_pellets > 0:
		pellet_count += sig_pellets

	result[BAR_FIRE_RATE] = fire_rate

	# ── Power (ST) — uses raw damage (no decay; Quality bar handles that)
	if is_channel:
		var per_tick := float(skill.damage)
		result[BAR_POWER_ST] = per_tick * fire_rate * crit_factor
	else:
		var avg_dmg := float(item.damage_min + item.damage_max) * 0.5
		result[BAR_POWER_ST] = avg_dmg * float(pellet_count) * dmg_mult * fire_rate * crit_factor

	# ── Capacity ────────────────────────────────────────────────────────
	if item.is_bullet_weapon():
		result[BAR_CAPACITY] = float(item.ammo_max)
	elif skill != null and skill.resource_cost > 0:
		result[BAR_CAPACITY] = 100.0 / float(maxi(1, skill.resource_cost))
	else:
		result[BAR_CAPACITY] = 100.0

	# ── Reload ──────────────────────────────────────────────────────────
	if item.reload_time > 0.0:
		result[BAR_RELOAD] = 1.0 / item.reload_time
	else:
		result[BAR_RELOAD] = -1.0

	return result


# ── Resolve fire skill (same cache pattern as tooltip) ──────────────────────

static var _skill_cache: Dictionary = {}

static func _resolve_item_fire_skill(item: Item) -> Skill:
	if item == null or item.weapon_base_id == &"":
		return null
	if _skill_cache.has(item.weapon_base_id):
		return _skill_cache[item.weapon_base_id]
	var path := "res://resources/items/weapon_bases/%s.tres" % item.weapon_base_id
	if not ResourceLoader.exists(path):
		return null
	var base := load(path) as WeaponBase
	if base == null:
		return null
	_skill_cache[item.weapon_base_id] = base.fire_skill
	return base.fire_skill


# ── Helpers ─────────────────────────────────────────────────────────────────

static func _normalize(val: float, lo: float, hi: float) -> float:
	if hi <= lo:
		return 0.5
	return clampf((val - lo) / (hi - lo), 0.0, 1.0)


static func _format_value(bar_id: StringName, val: float) -> String:
	match bar_id:
		BAR_POWER_ST:
			return "%.1f" % val
		BAR_FIRE_RATE:
			return "%.1f/s" % val
		BAR_CAPACITY:
			return "%d" % int(val)
		BAR_RELOAD:
			if val > 0.0:
				return "%.1fs" % (1.0 / val)
			return ""
	return "%.1f" % val


# ── DPS computation (shared with tooltip) ───────────────────────────────────
# The tooltip can call this instead of duplicating the formula.

static func compute_single_dps(item: Item) -> float:
	var skill := _resolve_item_fire_skill(item)
	var spd := item.attack_speed
	var crit: float = item.effective_crit_chance() if item.crit_chance > 0.0 else 0.15
	var crit_factor := 1.0 + crit * (1.5 - 1.0)
	var multistrike_factor: float = PerkState.expected_multistrike()

	var pellet_count := 1
	var dmg_mult := 1.0
	var fire_rate := spd

	if skill != null:
		pellet_count = maxi(1, skill.pellet_count)
		dmg_mult = maxf(0.01, skill.damage_multiplier)
		if skill.active_kind == Skill.ActiveKind.CHANNEL_BEAM:
			var interval := maxf(skill.channel_tick_interval, 0.05)
			var per_tick := float(skill.damage)
			return per_tick * (1.0 / interval) * crit_factor * multistrike_factor
		if skill.cooldown > 0.0:
			fire_rate = spd / skill.cooldown

	# Add weapon signature pellet_count
	var sig_pellets: int = item.get_modifier(&"pellet_count")
	if sig_pellets > 0:
		pellet_count += sig_pellets

	var avg_dmg := float(item.effective_damage_min() + item.effective_damage_max()) * 0.5
	return avg_dmg * float(pellet_count) * dmg_mult * fire_rate * crit_factor * multistrike_factor
