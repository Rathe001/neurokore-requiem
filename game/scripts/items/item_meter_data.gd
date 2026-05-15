class_name ItemMeterData
extends RefCounted

# Computes visual meter-bar data for ALL item tooltips. For weapons,
# delegates to WeaponMeterData. For armor, boots, grenades, and
# consumables, computes type-specific bars normalized to the archetype
# range — the bar itself shows the range of possible rolls for this
# item type + rarity.
#
# All bars show RAW rolled values (not decayed). A "Quality" bar at
# the top of every item shows the item-level effectiveness (0–125%).
#
# Armor slots always show a consistent set of bars (Defense + HP +
# Resource) regardless of what actually rolled, so two items of the
# same type can be compared bar-by-bar at a glance.
#
# Public API:
#   ItemMeterData.compute(item) -> Array[WeaponMeterData.MeterBar]
#   ItemMeterData.has_meters(item) -> bool

# ── Grenade cross-archetype ranges (for cooldown/cost bars) ───────────────
# These are fixed per archetype (not rolled), so we normalize across all types.
const GRENADE_CD_LO := 4.0   # Fastest grenade (frag)
const GRENADE_CD_HI := 6.0   # Slowest grenade (cluster)
const GRENADE_COST_LO := 8.0   # Cheapest grenade (frag)
const GRENADE_COST_HI := 12.0  # Most expensive grenade (cluster)

# ── Grenade base cache (lazy-loaded on first grenade compute) ──────────────

static var _grenade_bases: Dictionary = {}  # StringName id -> GrenadeBase
static var _grenade_ranges_built: bool = false


static func _ensure_grenade_ranges() -> void:
	if _grenade_ranges_built:
		return
	_grenade_ranges_built = true
	for path: String in ItemRoller.GRENADE_BASE_PATHS:
		var base := load(path) as GrenadeBase
		if base != null:
			_grenade_bases[base.id] = base


# ── Public API ─────────────────────────────────────────────────────────────

static func compute(item: Item) -> Array[WeaponMeterData.MeterBar]:
	if item == null:
		return []
	var is_weapon: bool = item.main_type == "1H Weapon" or item.main_type == "2H Weapon"
	var stat_bars: Array[WeaponMeterData.MeterBar]
	if is_weapon and item.weapon_base_id != &"":
		stat_bars = WeaponMeterData.compute(item)
		# Append affix modifier bars (fire dmg, resource on hit, etc.)
		# Exclude weapon signature stats — already shown as dedicated bars.
		var weapon_exclude: Dictionary = {}
		for key: StringName in WeaponMeterData._SIG_DISPLAY:
			weapon_exclude[key] = true
		_append_modifier_bars(item, stat_bars, item.effective_multiplier(), weapon_exclude)
	else:
		match item.main_type:
			"Head Armor", "Chest Armor", "Gloves", "Leg Armor":
				stat_bars = _compute_armor(item)
			"Boots":
				stat_bars = _compute_boots(item)
			"Grenade":
				stat_bars = _compute_grenade(item)
			"Consumable":
				stat_bars = _compute_consumable(item)
			"Offhand":
				stat_bars = _compute_offhand(item)
			_:
				return []
	return stat_bars


## Returns true when this item type produces meter bars.
static func has_meters(item: Item) -> bool:
	if item == null:
		return false
	if (item.main_type == "1H Weapon" or item.main_type == "2H Weapon") and item.weapon_base_id != &"":
		return true
	return item.main_type in [
		"Head Armor", "Chest Armor", "Gloves", "Leg Armor",
		"Boots", "Grenade", "Consumable", "Offhand",
	]


# ── Modifier bar definitions — every stat_modifier key gets a meter ───────
# Keys already handled by dedicated bars (DR on armor, speed on boots, etc.)
# are excluded per compute function via the `exclude` set.
# "lo"/"hi" define the bar's normalization range. "fmt" is the number format.
# "pct": true means the raw value is a percentage. "decays": true means it
# scales with effective_multiplier. "inverse": true means lower = better.

const MODIFIER_BAR_DEFS: Dictionary = {
	# Elemental damage (weapon affixes)
	&"fire_damage_bonus":      { "label": "Fire Dmg",   "fmt": "+%d",     "lo": 1,  "hi": 15 },
	&"cryo_damage_bonus":      { "label": "Cryo Dmg",   "fmt": "+%d",     "lo": 1,  "hi": 15 },
	&"electric_damage_bonus":  { "label": "Elec Dmg",   "fmt": "+%d",     "lo": 1,  "hi": 15 },
	&"toxic_damage_bonus":     { "label": "Toxic Dmg",  "fmt": "+%d",     "lo": 1,  "hi": 15 },
	# Core combat
	&"base_damage_bonus":      { "label": "+Damage",    "fmt": "+%d",     "lo": 1,  "hi": 12 },
	&"resource_on_hit":        { "label": "Res/Hit",    "fmt": "+%d",     "lo": 1,  "hi": 4 },
	&"crit_chance_bonus":      { "label": "+Crit",      "fmt": "+%.1f%%", "lo": 1,  "hi": 10, "pct": true },
	&"crit_damage_bonus":      { "label": "+Crit Dmg",  "fmt": "+%d%%",   "lo": 1,  "hi": 20 },
	&"attack_speed_bonus":     { "label": "+Speed",     "fmt": "+%d%%",   "lo": 1,  "hi": 12 },
	&"hit_chance_bonus":       { "label": "+Accuracy",  "fmt": "+%d",     "lo": 1,  "hi": 8 },
	&"cooldown_reduction":     { "label": "CDR",        "fmt": "+%d%%",   "lo": 1,  "hi": 15 },
	&"lifesteal_percent":      { "label": "Lifesteal",  "fmt": "%d%%",    "lo": 1,  "hi": 5 },
	&"armor_penetration":      { "label": "Armor Pen",  "fmt": "+%d%%",   "lo": 1,  "hi": 12 },
	&"damage_bonus_pct":       { "label": "+Dmg %",     "fmt": "+%d%%",   "lo": 1,  "hi": 20 },
	# Sustain / utility
	&"resource_cost_reduction":{ "label": "Cost Red",   "fmt": "+%d%%",   "lo": 1,  "hi": 15 },
	&"knockback_bonus":        { "label": "Knockback",  "fmt": "+%d",     "lo": 1,  "hi": 15 },
	&"range_bonus":            { "label": "+Range",     "fmt": "+%d",     "lo": 1,  "hi": 12 },
	&"carry_capacity_bonus":   { "label": "Carry Cap",  "fmt": "+%d",     "lo": 1,  "hi": 15 },
	&"inventory_bonus":        { "label": "Inv Slots",  "fmt": "+%d",     "lo": 1,  "hi": 4 },
	# Resistances
	&"electric_resistance":    { "label": "Elec Res",   "fmt": "+%d%%",   "lo": 1,  "hi": 12 },
	&"cryo_resistance":        { "label": "Cryo Res",   "fmt": "+%d%%",   "lo": 1,  "hi": 12 },
	&"toxic_resistance":       { "label": "Toxic Res",  "fmt": "+%d%%",   "lo": 1,  "hi": 12 },
	&"elemental_resistance":   { "label": "All Res",    "fmt": "+%d%%",   "lo": 1,  "hi": 8 },
	# Gloves-specific
	&"unarmed_damage_bonus":   { "label": "Unarmed",    "fmt": "+%d",     "lo": 1,  "hi": 12 },
	&"unarmed_stun_chance":    { "label": "Stun %",     "fmt": "+%d%%",   "lo": 5,  "hi": 30 },
	&"unarmed_aoe_radius":     { "label": "Unarmd AoE", "fmt": "+%d m",  "lo": 1,  "hi": 5 },
	# Grenade bonus
	&"blast_radius_bonus":     { "label": "+Blast",     "fmt": "+%.1f m", "lo": 0.5, "hi": 3.0 },
}

# Stat keys covered by meters — union of dedicated bar keys + MODIFIER_BAR_DEFS.
# Tooltip skips these in text stat display.
const METERED_MODIFIER_KEYS: Dictionary = {
	# Dedicated bars (armor/boots/offhand/consumable)
	&"damage_reduction": true,
	&"move_speed_bonus": true,
	&"traction_bonus": true,
	&"max_health_bonus": true,
	&"max_resource_bonus": true,
	&"life_on_kill": true,
	&"barrier_on_kill": true,
	&"shield_pool_bonus": true,
	&"shield_dr_bonus": true,
	&"shield_cd_reduction": true,
	&"shield_duration_bonus": true,
	&"heal_pct": true,
	&"heal_duration": true,
	# MODIFIER_BAR_DEFS keys
	&"fire_damage_bonus": true,
	&"cryo_damage_bonus": true,
	&"electric_damage_bonus": true,
	&"toxic_damage_bonus": true,
	&"base_damage_bonus": true,
	&"resource_on_hit": true,
	&"crit_chance_bonus": true,
	&"crit_damage_bonus": true,
	&"attack_speed_bonus": true,
	&"hit_chance_bonus": true,
	&"cooldown_reduction": true,
	&"lifesteal_percent": true,
	&"armor_penetration": true,
	&"damage_bonus_pct": true,
	&"resource_cost_reduction": true,
	&"knockback_bonus": true,
	&"range_bonus": true,
	&"carry_capacity_bonus": true,
	&"inventory_bonus": true,
	&"electric_resistance": true,
	&"cryo_resistance": true,
	&"toxic_resistance": true,
	&"elemental_resistance": true,
	&"unarmed_damage_bonus": true,
	&"unarmed_stun_chance": true,
	&"unarmed_aoe_radius": true,
	&"blast_radius_bonus": true,
}


# ── Armor (DR slots: Head, Chest, Gloves, Legs) ───────────────────────────
# Always shows: Defense, HP, Resource — even if HP/Resource didn't roll
# (empty bar). This ensures consistent bar layout for comparison.

static func _compute_armor(item: Item) -> Array[WeaponMeterData.MeterBar]:
	var bars: Array[WeaponMeterData.MeterBar] = []
	var budget: float = float(ItemRoller.RARITY_BUDGET_MULT.get(item.rarity, 1.0))
	var mult := item.effective_multiplier()

	# Defense (damage_reduction) — ilvl-derived range, rarity-curved + budget-scaled
	var raw_dr: int = int(item.stat_modifiers.get(&"damage_reduction", 0))
	var dr_center := int(round(float(item.item_level) * 0.3))
	var dr_lo := float(maxi(1, dr_center - 1))
	var dr_hi := float(maxi(2, dr_center + 1)) * budget
	dr_hi = minf(dr_hi, float(ItemRoller.DR_PER_PIECE_CAP))
	var dr_bar := _make_bar(&"defense", "Defense", float(raw_dr), dr_lo, dr_hi, raw_dr > 0, "%.0f%%")
	_apply_scaling(dr_bar, float(raw_dr), mult, dr_lo, dr_hi)
	bars.append(dr_bar)

	# HP (max_health_bonus) — ilvl-derived range, rarity-curved + budget-scaled
	var raw_hp: int = int(item.stat_modifiers.get(&"max_health_bonus", 0))
	var hp_lo := float(maxi(1, int(round(float(item.item_level) * 0.4))))
	var hp_hi := float(maxi(2, int(round(3.0 + float(item.item_level) * 0.6)))) * budget
	var hp_bar := _make_bar(&"hp", "HP", float(raw_hp), hp_lo, hp_hi, raw_hp > 0, "+%d")
	_apply_scaling(hp_bar, float(raw_hp), mult, hp_lo, hp_hi)
	bars.append(hp_bar)

	# Resource (max_resource_bonus) — ilvl-derived range, rarity-curved + budget-scaled
	var raw_res: int = int(item.stat_modifiers.get(&"max_resource_bonus", 0))
	var res_lo := float(maxi(1, int(round(float(item.item_level) * 0.25))))
	var res_hi := float(maxi(2, int(round(2.0 + float(item.item_level) * 0.4)))) * budget
	var res_bar := _make_bar(&"resource", "Resource", float(raw_res), res_lo, res_hi, raw_res > 0, "+%d")
	_apply_scaling(res_bar, float(raw_res), mult, res_lo, res_hi)
	bars.append(res_bar)

	# Sustain (life_on_kill, barrier_on_kill) — optional, only shown when rolled
	_append_sustain_bars(item, bars, mult)

	# Affix stats as meters (resistances, etc.)
	_append_modifier_bars(item, bars, mult, {
		&"damage_reduction": true, &"max_health_bonus": true,
		&"max_resource_bonus": true, &"life_on_kill": true, &"barrier_on_kill": true,
	})

	return bars


# ── Boots ──────────────────────────────────────────────────────────────────
# Always shows: Speed, Traction, HP, Resource.

static func _compute_boots(item: Item) -> Array[WeaponMeterData.MeterBar]:
	var bars: Array[WeaponMeterData.MeterBar] = []
	var budget: float = float(ItemRoller.RARITY_BUDGET_MULT.get(item.rarity, 1.0))
	var mult := item.effective_multiplier()

	# Move Speed — guaranteed base, raw value; scales with ilvl
	var raw_spd: int = int(item.stat_modifiers.get(&"move_speed_bonus", 0))
	var spd_lo := clampf(1.0 * budget, 1.0, 12.0)
	var spd_hi := clampf(8.0 * budget, 1.0, 12.0)
	var spd_bar := _make_bar(&"move_spd", "Speed", float(raw_spd), spd_lo, spd_hi, raw_spd > 0, "+%.0f%%")
	_apply_scaling(spd_bar, float(raw_spd), mult, spd_lo, spd_hi)
	bars.append(spd_bar)

	# Traction — guaranteed base, raw value; does NOT scale (feel stat)
	var raw_trac: int = int(item.stat_modifiers.get(&"traction_bonus", 0))
	var trac_lo := clampf(5.0 * budget, 5.0, 60.0)
	var trac_hi := clampf(40.0 * budget, 5.0, 60.0)
	bars.append(_make_bar(&"traction", "Traction", float(raw_trac), trac_lo, trac_hi, raw_trac > 0, "%d"))

	# HP (max_health_bonus) — ilvl-derived range, rarity-curved + budget-scaled
	var raw_hp: int = int(item.stat_modifiers.get(&"max_health_bonus", 0))
	var hp_lo := float(maxi(1, int(round(float(item.item_level) * 0.4))))
	var hp_hi := float(maxi(2, int(round(3.0 + float(item.item_level) * 0.6)))) * budget
	var hp_bar := _make_bar(&"hp", "HP", float(raw_hp), hp_lo, hp_hi, raw_hp > 0, "+%d")
	_apply_scaling(hp_bar, float(raw_hp), mult, hp_lo, hp_hi)
	bars.append(hp_bar)

	# Resource (max_resource_bonus) — ilvl-derived range, rarity-curved + budget-scaled
	var raw_res: int = int(item.stat_modifiers.get(&"max_resource_bonus", 0))
	var res_lo := float(maxi(1, int(round(float(item.item_level) * 0.25))))
	var res_hi := float(maxi(2, int(round(2.0 + float(item.item_level) * 0.4)))) * budget
	var res_bar := _make_bar(&"resource", "Resource", float(raw_res), res_lo, res_hi, raw_res > 0, "+%d")
	_apply_scaling(res_bar, float(raw_res), mult, res_lo, res_hi)
	bars.append(res_bar)

	# Sustain (life_on_kill, barrier_on_kill) — optional, only shown when rolled
	_append_sustain_bars(item, bars, mult)

	# Affix stats as meters
	_append_modifier_bars(item, bars, mult, {
		&"move_speed_bonus": true, &"traction_bonus": true,
		&"max_health_bonus": true, &"max_resource_bonus": true,
		&"life_on_kill": true, &"barrier_on_kill": true,
	})

	return bars


# ── Grenade ────────────────────────────────────────────────────────────────

static func _compute_grenade(item: Item) -> Array[WeaponMeterData.MeterBar]:
	_ensure_grenade_ranges()
	var bars: Array[WeaponMeterData.MeterBar] = []
	var base: GrenadeBase = _grenade_bases.get(item.weapon_base_id, null)
	if base == null:
		return bars
	var budget: float = float(ItemRoller.RARITY_BUDGET_MULT.get(item.rarity, 1.0))
	var mult := item.effective_multiplier()

	# Damage (avg) — raw values, rarity-scaled via budget; decays
	if item.damage_max > 0:
		var raw_avg := float(item.damage_min + item.damage_max) * 0.5
		var arch_lo := (base.damage_min_range.x + base.damage_max_range.x) * 0.5 * budget
		var arch_hi := (base.damage_min_range.y + base.damage_max_range.y) * 0.5 * budget
		var bar := WeaponMeterData.MeterBar.new()
		bar.id = &"damage"
		bar.label = "Damage"
		bar.value = _normalize(raw_avg, arch_lo, arch_hi)
		bar.number_text = "%d\u2013%d" % [item.damage_min, item.damage_max]
		_apply_scaling(bar, raw_avg, mult, arch_lo, arch_hi)
		bars.append(bar)

	# Blast Radius — no rarity budget scaling, does NOT decay (feel stat)
	if item.blast_radius > 0.0:
		var bar := WeaponMeterData.MeterBar.new()
		bar.id = &"blast"
		bar.label = "Blast"
		bar.value = _normalize(item.blast_radius, base.blast_radius_range.x, base.blast_radius_range.y)
		bar.number_text = "%.1f m" % item.blast_radius
		bars.append(bar)

	# Crit — raw value, no rarity budget scaling, does NOT decay
	if item.crit_chance > 0.0:
		var bar := WeaponMeterData.MeterBar.new()
		bar.id = &"crit"
		bar.label = "Crit"
		bar.value = _normalize(item.crit_chance, base.crit_chance_range.x, base.crit_chance_range.y)
		bar.number_text = "%.1f%%" % (item.crit_chance * 100.0)
		bars.append(bar)

	# Cooldown — from fire_skill, fixed per archetype. Inverted: lower = better.
	# Range across all grenades: 4.0s (frag) to 6.0s (cluster).
	if base.fire_skill != null and base.fire_skill.cooldown > 0.0:
		var cd := base.fire_skill.cooldown
		var bar := WeaponMeterData.MeterBar.new()
		bar.id = &"cooldown"
		bar.label = "Cooldown"
		# Invert: low cooldown = high bar fill (good)
		bar.value = _normalize(GRENADE_CD_HI + GRENADE_CD_LO - cd, GRENADE_CD_LO, GRENADE_CD_HI)
		bar.number_text = "%.1fs" % cd
		bars.append(bar)

	# Resource Cost — from fire_skill, fixed per archetype. Inverted: lower = better.
	# Range across all grenades: 8 (frag) to 12 (cluster).
	if base.fire_skill != null and base.fire_skill.resource_cost > 0:
		var cost := float(base.fire_skill.resource_cost)
		var bar := WeaponMeterData.MeterBar.new()
		bar.id = &"res_cost"
		bar.label = "Cost"
		# Invert: low cost = high bar fill (good)
		bar.value = _normalize(GRENADE_COST_HI + GRENADE_COST_LO - cost, GRENADE_COST_LO, GRENADE_COST_HI)
		bar.number_text = "%d" % int(cost)
		bars.append(bar)

	# Affix stats as meters (damage_bonus_pct, blast_radius_bonus, knockback, etc.)
	var mult := item.effective_multiplier()
	_append_modifier_bars(item, bars, mult, {})

	return bars


# ── Consumable ─────────────────────────────────────────────────────────────

static func _compute_consumable(item: Item) -> Array[WeaponMeterData.MeterBar]:
	var bars: Array[WeaponMeterData.MeterBar] = []
	var raw_heal: float = float(item.stat_modifiers.get(&"heal_pct", 0))
	if raw_heal <= 0.0:
		return bars
	var budget: float = float(ItemRoller.RARITY_BUDGET_MULT.get(item.rarity, 1.0))
	var mult := item.effective_multiplier()
	# Heal % — rolled 50–150 with curve + budget_mult
	var heal_lo := 50.0
	var heal_hi := 150.0 * budget
	var heal_bar := _make_bar(&"heal", "Heal", raw_heal, heal_lo, heal_hi, raw_heal > 0.0, "%d%%")
	_apply_scaling(heal_bar, raw_heal, mult, heal_lo, heal_hi)
	bars.append(heal_bar)
	# Heal Duration — rolled 0–5s with budget_mult; 0 = instant
	var raw_dur: float = float(item.stat_modifiers.get(&"heal_duration", 0.0))
	var dur_lo := 0.0
	var dur_hi := 5.0 * budget
	bars.append(_make_bar(&"heal_dur", "Duration", raw_dur, dur_lo, dur_hi, raw_dur > 0.0, "%.1fs"))
	# Charges — rolled 2–7 with budget_mult
	var raw_charges := float(item.max_charges)
	var charges_lo := 2.0
	var charges_hi := 7.0 * budget
	bars.append(_make_bar(&"charges", "Charges", raw_charges, charges_lo, charges_hi, item.max_charges > 0, "%d"))
	# Recharge Time — rolled 20–45s, inverse (lower = better), divided by budget_mult
	var raw_recharge := item.recharge_time
	if raw_recharge > 0.0:
		var rech_lo := 20.0 / budget  # best (fastest)
		var rech_hi := 45.0           # worst (slowest)
		var inv_bar := WeaponMeterData.MeterBar.new()
		inv_bar.id = &"recharge"
		inv_bar.label = "Recharge"
		# Invert: lower raw = better = higher bar fill
		inv_bar.value = _normalize(rech_lo + rech_hi - raw_recharge, rech_lo, rech_hi)
		inv_bar.number_text = "%.0fs" % raw_recharge
		bars.append(inv_bar)
	return bars


# ── Offhand / Shield ─────────────────────────────────────────────────────
# Shield bonus stats are rolled onto stat_modifiers on top of the Skill's
# base values. Bars show TOTAL values (base + bonus). SHIELD_BUFF shows
# DR, pool, duration, cooldown. SHIELD_HOLD shows pool, cooldown only.

static func _compute_offhand(item: Item) -> Array[WeaponMeterData.MeterBar]:
	var bars: Array[WeaponMeterData.MeterBar] = []
	var sk: Skill = item.fire_skill
	if sk == null or sk.active_kind == Skill.ActiveKind.NONE:
		return bars
	var budget: float = float(ItemRoller.RARITY_BUDGET_MULT.get(item.rarity, 1.0))

	# Shield Pool — base + bonus, rolled 15–50
	var raw_pool_bonus: int = int(item.stat_modifiers.get(&"shield_pool_bonus", 0))
	var total_pool := sk.shield_pool + raw_pool_bonus
	var pool_lo := float(sk.shield_pool + 15)
	var pool_hi := float(sk.shield_pool) + 50.0 * budget
	bars.append(_make_bar(&"shield_pool", "Shield", float(total_pool), pool_lo, pool_hi, raw_pool_bonus > 0, "%d"))

	# Damage Reduction — SHIELD_BUFF only; base + bonus (%), rolled 5–25
	if sk.active_kind == Skill.ActiveKind.SHIELD_BUFF:
		var raw_dr_bonus: int = int(item.stat_modifiers.get(&"shield_dr_bonus", 0))
		var total_dr := sk.damage_reduction * 100.0 + float(raw_dr_bonus)
		var dr_lo := sk.damage_reduction * 100.0 + 5.0
		var dr_hi := sk.damage_reduction * 100.0 + 25.0 * budget
		bars.append(_make_bar(&"shield_dr", "DR", total_dr, dr_lo, dr_hi, raw_dr_bonus > 0, "%.0f%%"))

	# Duration — SHIELD_BUFF only; base + bonus (s), rolled 30–120
	if sk.active_kind == Skill.ActiveKind.SHIELD_BUFF:
		var raw_dur_bonus: int = int(item.stat_modifiers.get(&"shield_duration_bonus", 0))
		var total_dur := sk.duration + float(raw_dur_bonus)
		var dur_lo := sk.duration + 30.0
		var dur_hi := sk.duration + 120.0 * budget
		bars.append(_make_bar(&"shield_dur", "Duration", total_dur, dur_lo, dur_hi, raw_dur_bonus > 0, "%ds"))

	# Cooldown Reduction — inverse: lower cooldown = better; rolled 5–20%
	var raw_cdr: int = int(item.stat_modifiers.get(&"shield_cd_reduction", 0))
	if raw_cdr > 0:
		var effective_cd := sk.cooldown * (1.0 - float(raw_cdr) / 100.0)
		var cd_best := sk.cooldown * (1.0 - 20.0 * budget / 100.0)
		var cd_worst := sk.cooldown * (1.0 - 5.0 / 100.0)
		var cd_bar := WeaponMeterData.MeterBar.new()
		cd_bar.id = &"shield_cd"
		cd_bar.label = "Cooldown"
		# Invert: lower cooldown = higher bar fill
		cd_bar.value = _normalize(cd_best + cd_worst - effective_cd, cd_best, cd_worst)
		cd_bar.number_text = "%.1fs" % effective_cd
		bars.append(cd_bar)
	else:
		bars.append(_make_bar(&"shield_cd", "Cooldown", 0.0, 0.0, 1.0, false, ""))

	# Sustain (life_on_kill, barrier_on_kill) — offhands go through universal bonuses
	var mult := item.effective_multiplier()
	_append_sustain_bars(item, bars, mult)

	# Affix stats as meters
	_append_modifier_bars(item, bars, mult, {
		&"shield_pool_bonus": true, &"shield_dr_bonus": true,
		&"shield_cd_reduction": true, &"shield_duration_bonus": true,
		&"life_on_kill": true, &"barrier_on_kill": true,
	})

	return bars


# ── Sustain bars (shared by armor + boots + offhands) ────────────────────
# life_on_kill and barrier_on_kill are universal sustain rolls that can
# appear on any equipment. Only shown when rolled (> 0).
# Ranges derived from ilvl, scaled by rarity budget_mult via _rarity_rolli.

static func _append_sustain_bars(item: Item, bars: Array[WeaponMeterData.MeterBar], mult: float) -> void:
	var budget: float = float(ItemRoller.RARITY_BUDGET_MULT.get(item.rarity, 1.0))
	var raw_lok: int = int(item.stat_modifiers.get(&"life_on_kill", 0))
	if raw_lok > 0:
		var lok_lo := float(maxi(1, int(round(float(item.item_level) * 0.2))))
		var lok_hi := float(maxi(2, int(round(2.0 + float(item.item_level) * 0.4)))) * budget
		var lok_bar := _make_bar(&"life_on_kill", "Life/Kill", float(raw_lok), lok_lo, lok_hi, true, "+%d")
		_apply_scaling(lok_bar, float(raw_lok), mult, lok_lo, lok_hi)
		bars.append(lok_bar)

	var raw_bok: int = int(item.stat_modifiers.get(&"barrier_on_kill", 0))
	if raw_bok > 0:
		var bok_lo := float(maxi(1, int(round(float(item.item_level) * 0.15))))
		var bok_hi := float(maxi(1, int(round(1.0 + float(item.item_level) * 0.25)))) * budget
		var bok_bar := _make_bar(&"barrier_on_kill", "Barrier/Kill", float(raw_bok), bok_lo, bok_hi, true, "+%d")
		_apply_scaling(bok_bar, float(raw_bok), mult, bok_lo, bok_hi)
		bars.append(bok_bar)


# ── Helpers ────────────────────────────────────────────────────────────────

## Apply decay/boost overlay to a bar based on effective_multiplier.
## Only modifies bars with rolled values (raw > 0).
static func _apply_scaling(bar: WeaponMeterData.MeterBar, raw: float, mult: float, lo: float, hi: float) -> void:
	if raw <= 0.0 or is_equal_approx(mult, 1.0):
		return
	if mult < 1.0:
		bar.decayed_value = _normalize(raw * mult, lo, hi)
	else:
		bar.boosted_value = _normalize(raw * mult, lo, hi)


static func _normalize(val: float, lo: float, hi: float) -> float:
	if hi <= lo:
		return 0.5
	return clampf((val - lo) / (hi - lo), 0.0, 1.0)


# ── Generic modifier bars (affix stats → meters) ─────────────────────────
# Iterates item.stat_modifiers and creates a bar for any key present in
# MODIFIER_BAR_DEFS that isn't in the exclude set (already shown as a
# dedicated bar). Called at the end of every _compute_* function.

static func _append_modifier_bars(
	item: Item, bars: Array[WeaponMeterData.MeterBar],
	mult: float, exclude: Dictionary
) -> void:
	for key: StringName in item.stat_modifiers:
		if exclude.has(key):
			continue
		var def: Dictionary = MODIFIER_BAR_DEFS.get(key, {})
		if def.is_empty():
			continue
		var raw_val: float = float(item.stat_modifiers[key])
		if raw_val == 0.0:
			continue
		var lo: float = float(def["lo"])
		var hi: float = float(def["hi"])
		var bar := _make_bar(key, def["label"], raw_val, lo, hi, true, def["fmt"])
		# Combat power stats decay with effective_multiplier
		if def.get("decays", false) and not is_equal_approx(mult, 1.0):
			if mult < 1.0:
				bar.decayed_value = _normalize(raw_val * mult, lo, hi)
			else:
				bar.boosted_value = _normalize(raw_val * mult, lo, hi)
		bars.append(bar)


## Build a MeterBar with "not rolled" vs "rolled" distinction.
## If was_rolled is false, value is 0 and number_text is empty (empty bar).
static func _make_bar(
	id: StringName, label: String, raw_val: float,
	arch_lo: float, arch_hi: float, was_rolled: bool, fmt: String
) -> WeaponMeterData.MeterBar:
	var bar := WeaponMeterData.MeterBar.new()
	bar.id = id
	bar.label = label
	if not was_rolled:
		bar.value = 0.0
		bar.number_text = ""
	else:
		bar.value = _normalize(raw_val, arch_lo, arch_hi)
		bar.number_text = fmt % raw_val
	return bar


# ── Comparison merge — union of both items' bar IDs ──────────────────────
# When Shift is held, both hovered and equipped items should show the same
# set of bars so the user can see at a glance what's missing from each.
# Missing bars show as empty (value=0, no number_text).

static func merge_for_comparison(
	hovered_bars: Array[WeaponMeterData.MeterBar],
	equipped_bars: Array[WeaponMeterData.MeterBar]
) -> Array:  # Returns [merged_hovered, merged_equipped]
	# Collect union of all bar IDs in order (hovered first, then any equipped-only)
	var ordered_ids: Array[StringName] = []
	var hovered_by_id: Dictionary = {}
	for bar: WeaponMeterData.MeterBar in hovered_bars:
		if not ordered_ids.has(bar.id):
			ordered_ids.append(bar.id)
		hovered_by_id[bar.id] = bar
	var equipped_by_id: Dictionary = {}
	for bar: WeaponMeterData.MeterBar in equipped_bars:
		if not ordered_ids.has(bar.id):
			ordered_ids.append(bar.id)
		equipped_by_id[bar.id] = bar
	# Build merged arrays — placeholder for missing bars
	var merged_hovered: Array[WeaponMeterData.MeterBar] = []
	var merged_equipped: Array[WeaponMeterData.MeterBar] = []
	for id: StringName in ordered_ids:
		if hovered_by_id.has(id):
			merged_hovered.append(hovered_by_id[id])
		else:
			# Find the label from the equipped bar
			var ref: WeaponMeterData.MeterBar = equipped_by_id[id]
			var placeholder := WeaponMeterData.MeterBar.new()
			placeholder.id = id
			placeholder.label = ref.label
			placeholder.value = 0.0
			placeholder.number_text = ""
			merged_hovered.append(placeholder)
		if equipped_by_id.has(id):
			merged_equipped.append(equipped_by_id[id])
		else:
			var ref: WeaponMeterData.MeterBar = hovered_by_id[id]
			var placeholder := WeaponMeterData.MeterBar.new()
			placeholder.id = id
			placeholder.label = ref.label
			placeholder.value = 0.0
			placeholder.number_text = ""
			merged_equipped.append(placeholder)
	return [merged_hovered, merged_equipped]
