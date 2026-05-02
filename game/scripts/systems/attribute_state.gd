extends Node

# Moral attribute stats. See docs/design/attribute-system.md.
# Rollable stats (ort/ing/amb/dev/opt/cla) are set by equipment + class scaling.
# Soul and Interface are derived: average of their origin's three team stats.

signal stats_changed

# Accent colors per stat — match class theme resources (attribute-system.md § Attribute Colors)
const STAT_COLORS: Dictionary = {
	&"soul": Color(0.65, 0.45, 0.25, 1.0),
	&"itf":  Color(0.3,  0.85, 1.0,  1.0),
	&"ort":  Color(0.95, 0.92, 0.8,  1.0),
	&"dev":  Color(0.9,  0.25, 0.2,  1.0),
	&"opt":  Color(0.55, 0.78, 0.85, 1.0),
	&"ing":  Color(0.7,  0.85, 0.35, 1.0),
	&"cla":  Color(0.95, 0.9,  0.3,  1.0),
	&"amb":  Color(0.78, 0.35, 0.85, 1.0),
}

# i18n keys for display labels
const STAT_I18N: Dictionary = {
	&"soul": &"STAT_SOUL",
	&"itf":  &"STAT_INTERFACE",
	&"ort":  &"STAT_ORTHODOXY",
	&"dev":  &"STAT_DEVIATION",
	&"opt":  &"STAT_OPTIMIZATION",
	&"ing":  &"STAT_INGENUITY",
	&"cla":  &"STAT_CLARITY",
	&"amb":  &"STAT_AMBITION",
}

# Stat shorthands for compact display
const STAT_SHORT: Dictionary = {
	&"soul": "SOU",
	&"itf":  "ITF",
	&"ort":  "ORT",
	&"dev":  "DEV",
	&"opt":  "OPT",
	&"ing":  "ING",
	&"cla":  "CLA",
	&"amb":  "AMB",
}

# Display order for UI — Analog origin (left col), Cyborg origin (right col)
const ANALOG_STATS: Array[StringName] = [&"soul", &"ort", &"ing", &"amb"]
const CYBORG_STATS: Array[StringName] = [&"itf", &"dev", &"opt", &"cla"]

# Rollable stats (all 6, in fixed order)
const ROLLABLE_STATS: Array[StringName] = [&"ort", &"ing", &"amb", &"dev", &"opt", &"cla"]

# Team stats per origin
const ANALOG_TEAM_STATS: Array[StringName] = [&"ort", &"ing", &"amb"]
const CYBORG_TEAM_STATS: Array[StringName] = [&"dev", &"opt", &"cla"]

# All specialized class definitions in one place — avoids sync bugs when adding classes.
# Keys: spec_id → { stat: primary_stat, origin: origin_id }
const CLASS_DEFINITIONS: Dictionary = {
	&"count":  {&"stat": &"ort", &"origin": &"analog"},
	&"survivalist": {&"stat": &"ing", &"origin": &"analog"},
	&"enculted":   {&"stat": &"amb", &"origin": &"analog"},
	&"forged":     {&"stat": &"dev", &"origin": &"cyborg"},
	&"automaton":  {&"stat": &"opt", &"origin": &"cyborg"},
	&"polymath":   {&"stat": &"cla", &"origin": &"cyborg"},
}

# Direct nemesis pairs — positional opposites across the two origins (flavor + UI distinction only).
const NEMESIS_STAT: Dictionary = {
	&"ort": &"dev", &"dev": &"ort",
	&"ing": &"opt", &"opt": &"ing",
	&"amb": &"cla", &"cla": &"amb",
}

# Roman numeral tier labels — shared across all UI that displays tiers.
const TIER_ROMAN: Array[String] = ["I", "II", "III"]
const TIER_COUNT := 3

# Relationship accent colors — used by talents panel, tooltip, and any future UI.
# primary = own class stat, team = same origin, opp_team = opposite origin, opposing = nemesis stat.
const RELATIONSHIP_COLORS: Dictionary = {
	&"primary":  Color(0.25, 1.0,  0.35, 1.0),
	&"team":     Color(0.15, 0.38, 0.18, 1.0),
	&"opp_team": Color(0.95, 0.80, 0.15, 1.0),
	&"opposing": Color(0.85, 0.18, 0.18, 1.0),
}

# Tier unlock thresholds (3 tiers): stat's share of total rollable stats.
#
# Specialized classes (auto-granted T1 of their primary perk regardless of
# allocation; can chase T3 of own + supplementary perks of others — 3-1-1 or
# 3-2-0 are the reachable patterns):
#   TIERS_OWN      — own primary stat
#   TIERS_TEAM     — same-origin team stats
#   TIERS_OPPOSING — opposite-origin stats (kept hard for build flavour)
#
# Origin classes (Analog / Cyborg) trade T3 ceiling for breadth: lower team
# thresholds + a hard T2 cap let them spread to 2-2-1 across all three of
# their origin's stats. The T3 entry in TIERS_TEAM_ORIGIN is set to 1.01
# (>100% = unreachable by construction) so the cap falls out naturally
# without special-casing it inside get_unlocked_tier.
# See docs/design/attribute-system.md § Breakpoints.
const TIERS_OWN:         Array[float] = [0.12, 0.25, 0.40]
const TIERS_TEAM:        Array[float] = [0.25, 0.40, 0.55]
const TIERS_OPPOSING:    Array[float] = [0.40, 0.55, 0.70]
const TIERS_TEAM_ORIGIN: Array[float] = [0.20, 0.35, 1.01]

# Talent tree node dimensions — 8 nodes per tier means 24 per class tree.
# With 20 talent points, even a fully committed build can't fill one tree.
const TALENT_NODES_PER_TIER := 8

# Origin class balance tier caps. Indexed 1–3. Each entry is [max_any_team_pct, max_any_opposing_pct].
# Tier N requires: no team stat >= max_any_team_pct AND no opposing stat >= max_any_opposing_pct.
# Tier 0 is the fallback (any stat too dominant → all balance perks lost).
const ORIGIN_TIER_CAPS: Array[Array] = [
	[],           # index 0 — unused placeholder
	[0.55, 0.45], # tier 1: almost free
	[0.40, 0.30], # tier 2: intentional balance
	[0.30, 0.20], # tier 3: tight spread — aspirational
]

# Team nodes: 3-tier tree unlocked by combined team stat share.
const TEAM_NODE_TIER_COUNT := 3
const TEAM_NODE_NODES_PER_TIER := 4
const TEAM_NODE_THRESHOLDS: Array[float] = [0.20, 0.35, 0.50]

# Outgoing player damage scales with the class's main stat. 1% per point gives
# us roughly D2-shaped scaling for the playtest: a fully-geared character lands
# in the +50–100% range. Tuning lives here so combat balance stays in one file.
const DAMAGE_PER_MAIN_STAT_PCT: float = 0.01

# ── HP / Resource scaling from stats ─────────────────────────────────────────
# Contribution weights per stat relationship when computing HP and resource
# bonuses. Primary stat contributes most; opposing stat is heavily penalised.
const STAT_WEIGHT_PRIMARY:  float = 1.0
const STAT_WEIGHT_TEAM:     float = 0.25
const STAT_WEIGHT_OPPOSING: float = 0.10

# How many bonus HP / resource-max each weighted stat point grants.
const HP_PER_WEIGHTED_STAT: float = 2.0
const RESOURCE_PER_WEIGHTED_STAT: float = 1.0

# ── Stat values ───────────────────────────────────────────────────────────────

var ort: int = 0
var ing: int = 0
var amb: int = 0
var dev: int = 0
var opt: int = 0
var cla: int = 0

var soul: int:
	get:
		return _avg3(ort, ing, amb)

var itf: int:
	get:
		return _avg3(dev, opt, cla)

func _ready() -> void:
	for stat in ROLLABLE_STATS:
		assert(stat in STAT_COLORS, "AttributeState: missing STAT_COLORS entry for '%s'" % stat)
		assert(stat in STAT_I18N,   "AttributeState: missing STAT_I18N entry for '%s'" % stat)
		assert(stat in STAT_SHORT,  "AttributeState: missing STAT_SHORT entry for '%s'" % stat)
	InventoryState.equipment_changed.connect(func(_slot: StringName) -> void: _recompute_from_equipment())
	_recompute_from_equipment()

func _recompute_from_equipment() -> void:
	var totals: Dictionary = {&"ort": 0, &"ing": 0, &"amb": 0, &"dev": 0, &"opt": 0, &"cla": 0}
	for item in InventoryState.equipment.values():
		if item == null:
			continue
		for stat_id in item.stat_modifiers:
			if totals.has(stat_id):
				totals[stat_id] += int(item.stat_modifiers[stat_id])
	ort = totals[&"ort"]
	ing = totals[&"ing"]
	amb = totals[&"amb"]
	dev = totals[&"dev"]
	opt = totals[&"opt"]
	cla = totals[&"cla"]
	stats_changed.emit()

func get_stat(id: StringName) -> int:
	match id:
		&"soul": return soul
		&"itf":  return itf
		&"ort":  return ort
		&"ing":  return ing
		&"amb":  return amb
		&"dev":  return dev
		&"opt":  return opt
		&"cla":  return cla
	return 0

func set_stat(id: StringName, value: int) -> void:
	match id:
		&"ort": ort = value
		&"ing": ing = value
		&"amb": amb = value
		&"dev": dev = value
		&"opt": opt = value
		&"cla": cla = value
		_: return
	stats_changed.emit()

# ── Calculation engine ────────────────────────────────────────────────────────

## Returns a rollable stat's share of total rollable stats (0.0–1.0).
func get_stat_pct(stat_id: StringName) -> float:
	var total := 0
	for s in ROLLABLE_STATS:
		total += get_stat(s)
	if total == 0:
		return 0.0
	return float(get_stat(stat_id)) / float(total)

## Returns all rollable stat percentages: { stat_id: float }.
func get_all_stat_pcts() -> Dictionary:
	var total := 0
	for s in ROLLABLE_STATS:
		total += get_stat(s)
	var result: Dictionary = {}
	for s in ROLLABLE_STATS:
		result[s] = float(get_stat(s)) / maxf(float(total), 1.0)
	return result

## Returns the relationship of a stat to the given class: &"primary", &"team", or &"opposing".
func get_stat_relationship(stat_id: StringName, class_id: StringName, spec_id: StringName) -> StringName:
	if spec_id != &"":
		if get_spec_stat(spec_id) == stat_id:
			return &"primary"
		return &"team" if stat_id in get_team_stats_for_origin(get_spec_origin(spec_id)) else &"opposing"
	# Origin class: no primary stat
	return &"team" if stat_id in get_team_stats_for_origin(class_id) else &"opposing"

## Returns the threshold array for unlocking each tier of a stat's tree.
## Origin classes get a separate, lower team-stat table with the T3 slot
## sentinel'd to >100% so they can never unlock T3.
func get_tier_thresholds(stat_id: StringName, class_id: StringName, spec_id: StringName) -> Array[float]:
	if spec_id == &"":
		# Origin: no primary stat. Team stats use the breadth-friendly origin
		# table; opposing stats stay on the standard hard table so cross-origin
		# investment is still expensive.
		if stat_id in get_team_stats_for_origin(class_id):
			return TIERS_TEAM_ORIGIN
		return TIERS_OPPOSING
	match get_stat_relationship(stat_id, class_id, spec_id):
		&"primary": return TIERS_OWN
		&"team":    return TIERS_TEAM
	return TIERS_OPPOSING

## Returns the currently unlocked tier (0–3) for a stat tree given class context.
##
## Tiers stack additively across the budget — reaching T3 in one tree no longer
## zeroes the others, so specialized classes can land 3-1-1 or 3-2-0 patterns.
## Specialized classes are auto-granted T1 of their primary perk so class
## identity reads even before any stat investment. Origin classes are capped
## at T2 implicitly via the unreachable T3 threshold in TIERS_TEAM_ORIGIN.
func get_unlocked_tier(stat_id: StringName, class_id: StringName, spec_id: StringName) -> int:
	var pct := get_stat_pct(stat_id)
	var thresholds := get_tier_thresholds(stat_id, class_id, spec_id)
	var unlocked := 0
	for i in TIER_COUNT:
		if pct >= thresholds[i]:
			unlocked = i + 1
	if spec_id != &"" and stat_id == get_spec_stat(spec_id):
		unlocked = maxi(unlocked, 1)
	return unlocked

## Returns the balance tier (0–3) for an origin class (Analog/Cyborg).
## Higher = tighter stat balance; perks are maintained up to the returned tier.
func get_origin_tier(class_id: StringName) -> int:
	var pcts := get_all_stat_pcts()
	var team := get_team_stats_for_origin(class_id)
	var opposing := get_opposing_stats_for_origin(class_id)
	var max_team := 0.0
	for s in team:
		max_team = maxf(max_team, pcts.get(s, 0.0))
	var max_opp := 0.0
	for s in opposing:
		max_opp = maxf(max_opp, pcts.get(s, 0.0))
	for tier in range(TIER_COUNT, 0, -1):
		var caps: Array = ORIGIN_TIER_CAPS[tier]
		if max_team < caps[0] and max_opp < caps[1]:
			return tier
	return 0

## Returns the unlocked team-nodes tier (0–3) based on combined team stat share.
func get_team_nodes_tier(class_id: StringName, spec_id: StringName) -> int:
	var origin: StringName = get_spec_origin(spec_id) if spec_id != &"" else class_id
	return get_team_nodes_tier_for_origin(origin)

## Returns the unlocked team-nodes tier (0–3) for a specific origin, regardless of player class.
func get_team_nodes_tier_for_origin(origin: StringName) -> int:
	var pcts := get_all_stat_pcts()
	var combined := 0.0
	for s in get_team_stats_for_origin(origin):
		combined += pcts.get(s, 0.0)
	var unlocked := 0
	for i in TEAM_NODE_THRESHOLDS.size():
		if combined >= TEAM_NODE_THRESHOLDS[i]:
			unlocked = i + 1
	return unlocked

func get_team_stats_for_origin(origin: StringName) -> Array[StringName]:
	return ANALOG_TEAM_STATS if origin == &"analog" else CYBORG_TEAM_STATS

func get_opposing_stats_for_origin(origin: StringName) -> Array[StringName]:
	return CYBORG_TEAM_STATS if origin == &"analog" else ANALOG_TEAM_STATS

## Returns the primary stat for a specialized class, or &"" for origin classes.
func get_spec_stat(spec_id: StringName) -> StringName:
	return CLASS_DEFINITIONS.get(spec_id, {}).get(&"stat", &"")

## Returns the player's main stat for combat scaling.
## Specialized classes use their primary stat; origin classes use the derived
## origin stat (analog → soul, cyborg → itf).
func get_class_main_stat_id(class_id: StringName, spec_id: StringName) -> StringName:
	if spec_id != &"":
		return get_spec_stat(spec_id)
	if class_id == &"analog":
		return &"soul"
	if class_id == &"cyborg":
		return &"itf"
	return &""

## Outgoing damage multiplier from the player's main stat. 1.0 means no bonus;
## 1.5 means +50% damage. Multiply weapon-rolled damage by this value before
## crit/perk modifiers in the player's damage path.
func get_player_damage_mult(class_id: StringName, spec_id: StringName) -> float:
	var stat_id := get_class_main_stat_id(class_id, spec_id)
	if stat_id == &"":
		return 1.0
	return 1.0 + float(get_stat(stat_id)) * DAMAGE_PER_MAIN_STAT_PCT

## Returns the origin (&"analog" or &"cyborg") for a specialized class spec_id.
func get_spec_origin(spec_id: StringName) -> StringName:
	return CLASS_DEFINITIONS.get(spec_id, {}).get(&"origin", &"analog")

## Sort priority for stat relationship: primary(0) > team(1) > opp_team(2) > nemesis(3).
## Used to order segments in summary bars consistently across all UI.
func get_stat_rel_priority(stat_id: StringName, class_id: StringName, spec_id: StringName) -> int:
	var rel := get_stat_relationship(stat_id, class_id, spec_id)
	if rel == &"primary": return 0
	if rel == &"team":    return 1
	var my_stat := get_spec_stat(spec_id)
	if my_stat != &"" and NEMESIS_STAT.get(my_stat, &"") == stat_id: return 3
	return 2

## Returns the RELATIONSHIP_COLORS key for a stat given class context.
## Distinguishes nemesis (&"opposing") from generic opposing-origin (&"opp_team").
func get_stat_rel_color_key(stat_id: StringName, class_id: StringName, spec_id: StringName) -> StringName:
	var rel := get_stat_relationship(stat_id, class_id, spec_id)
	if rel == &"primary": return &"primary"
	if rel == &"team":    return &"team"
	var my_stat := get_spec_stat(spec_id)
	if my_stat != &"" and NEMESIS_STAT.get(my_stat, &"") == stat_id: return &"opposing"
	return &"opp_team"

## Returns a BBCode-formatted scaling hint for a class/spec, used by selection UI.
## Stat names are wrapped in [color] tags matching their STAT_COLORS.
func get_scaling_hint(class_id: StringName, spec_id: StringName) -> String:
	var _colored := func(stat_id: StringName) -> String:
		var key: StringName = STAT_I18N.get(stat_id, &"")
		var label: String = tr(key) if key != &"" else String(stat_id).capitalize()
		var col: Color = STAT_COLORS.get(stat_id, Color.WHITE)
		return "[color=#%s]%s[/color]" % [col.to_html(false), label]

	if spec_id == &"":
		var origin_team := get_team_stats_for_origin(class_id)
		var origin_team_names: Array[String] = []
		for s in origin_team:
			origin_team_names.append(_colored.call(s))
		var derived_stat: StringName = &"soul" if class_id == &"analog" else &"itf"
		var derived: String = _colored.call(derived_stat)
		return "Scales with %s (average of %s). Rewards balanced investment across all three." % [
			derived, ", ".join(origin_team_names)]

	var primary: StringName = get_spec_stat(spec_id)
	var origin: StringName = get_spec_origin(spec_id)
	var team := get_team_stats_for_origin(origin)
	var nemesis: StringName = NEMESIS_STAT.get(primary, &"")

	var team_names: Array[String] = []
	for s in team:
		if s != primary:
			team_names.append(_colored.call(s))

	return "Scales with %s. Benefits from %s. Weak against %s." % [
		_colored.call(primary), " and ".join(team_names), _colored.call(nemesis)]

## Returns the contribution-weighted sum of all rollable stats for the given
## class context. Primary stat counts fully, team stats partially, opposing
## stats minimally. Used to derive bonus HP and resource pool size.
func get_weighted_stat_total(class_id: StringName, spec_id: StringName) -> float:
	var total := 0.0
	for stat_id in ROLLABLE_STATS:
		var value := float(get_stat(stat_id))
		if value <= 0.0:
			continue
		var rel := get_stat_relationship(stat_id, class_id, spec_id)
		match rel:
			&"primary": total += value * STAT_WEIGHT_PRIMARY
			&"team":    total += value * STAT_WEIGHT_TEAM
			_:          total += value * STAT_WEIGHT_OPPOSING
	return total

## Bonus HP granted by current stats for the given class context.
func get_stat_bonus_hp(class_id: StringName, spec_id: StringName) -> int:
	return int(get_weighted_stat_total(class_id, spec_id) * HP_PER_WEIGHTED_STAT)

## Bonus resource-pool max granted by current stats for the given class context.
func get_stat_bonus_resource(class_id: StringName, spec_id: StringName) -> int:
	return int(get_weighted_stat_total(class_id, spec_id) * RESOURCE_PER_WEIGHTED_STAT)

func _avg3(a: int, b: int, c: int) -> int:
	return int(round((a + b + c) / 3.0))
