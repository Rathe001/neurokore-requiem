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
	&"gentleman":  {&"stat": &"ort", &"origin": &"analog"},
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
const TIER_ROMAN: Array[String] = ["I", "II", "III", "IV", "V"]

# Relationship accent colors — used by talents panel, tooltip, and any future UI.
# primary = own class stat, team = same origin, opp_team = opposite origin, opposing = nemesis stat.
const RELATIONSHIP_COLORS: Dictionary = {
	&"primary":  Color(0.25, 1.0,  0.35, 1.0),
	&"team":     Color(0.15, 0.38, 0.18, 1.0),
	&"opp_team": Color(0.95, 0.80, 0.15, 1.0),
	&"opposing": Color(0.85, 0.18, 0.18, 1.0),
}

# Tier unlock thresholds: stat's share of total rollable stats required for each tier 1–5.
# Primary stat unlocks much more easily — class identity should feel immediate.
# Team stats use standard thresholds; opposing stats are hardest to unlock.
# See docs/design/attribute-system.md § Breakpoints.
const TIERS_OWN:      Array[float] = [0.12, 0.25, 0.40, 0.55, 0.72]
const TIERS_TEAM:     Array[float] = [0.20, 0.40, 0.60, 0.75, 0.90]
const TIERS_OPPOSING: Array[float] = [0.30, 0.50, 0.70, 0.85, 0.95]

# Origin class balance tier caps. Indexed 1–5. Each entry is [max_any_team_pct, max_any_opposing_pct].
# Tier N requires: no team stat >= max_any_team_pct AND no opposing stat >= max_any_opposing_pct.
# Tier 0 is the fallback (any stat too dominant → all balance perks lost).
const ORIGIN_TIER_CAPS: Array[Array] = [
	[],           # index 0 — unused placeholder
	[0.55, 0.45], # tier 1: almost free
	[0.45, 0.35], # tier 2: spread gearing
	[0.35, 0.25], # tier 3: moderate
	[0.30, 0.20], # tier 4: demanding
	[0.25, 0.15], # tier 5: near-perfect balance
]

# Team nodes: 5-tier tree unlocked by combined team stat share.
const TEAM_NODE_THRESHOLDS: Array[float] = [0.20, 0.35, 0.50, 0.65, 0.80]

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

## Returns the 5-element threshold array for unlocking each tier of a stat's tree.
func get_tier_thresholds(stat_id: StringName, class_id: StringName, spec_id: StringName) -> Array[float]:
	match get_stat_relationship(stat_id, class_id, spec_id):
		&"primary": return TIERS_OWN
		&"team":    return TIERS_TEAM
	return TIERS_OPPOSING

## Returns the currently unlocked tier (0–5) for a stat tree given class context.
func get_unlocked_tier(stat_id: StringName, class_id: StringName, spec_id: StringName) -> int:
	var pct := get_stat_pct(stat_id)
	var thresholds := get_tier_thresholds(stat_id, class_id, spec_id)
	var unlocked := 0
	for i in 5:
		if pct >= thresholds[i]:
			unlocked = i + 1
	return unlocked

## Returns the balance tier (0–5) for an origin class (Analog/Cyborg).
## Higher = tighter stat balance; perk perks are maintained up to the returned tier.
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
	for tier in range(5, 0, -1):
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

func _avg3(a: int, b: int, c: int) -> int:
	return int(round((a + b + c) / 3.0))
