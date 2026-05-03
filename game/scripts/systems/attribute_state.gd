extends Node

# Moral attribute stats. See docs/design/attribute-system.md.
# Rollable stats (ort/ing/amb/dev/opt/cla) are set by equipment + class scaling.
# Soul and Interface are derived: average of their origin's three kore stats.
#
# "Kore" terminology: stats that share an origin (the Analog kore stats are
# ORT/ING/AMB; the Cyborg kore stats are DEV/OPT/CLA). Named for the game's
# title — your character has a "kore," and stats matching it scale you up.
# Stats from the opposite kore are "opposing" and create distortion.

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

# Kore stats per origin — the three rollable stats native to that origin.
const ANALOG_KORE_STATS: Array[StringName] = [&"ort", &"ing", &"amb"]
const CYBORG_KORE_STATS: Array[StringName] = [&"dev", &"opt", &"cla"]

# All specialized class definitions in one place — avoids sync bugs when
# adding classes. Add presentational fields here too (glyph for placeholder
# portraits, i18n keys for label + backstory) so spec_select / character
# panels read from a single source instead of carrying parallel dicts.
const CLASS_DEFINITIONS: Dictionary = {
	&"count":       {&"stat": &"ort", &"origin": &"analog", &"glyph": "G", &"label_key": &"STARTUP_PICK_ANALOG_COUNT", &"backstory_key": &"STARTUP_BACKSTORY_COUNT"},
	&"survivalist": {&"stat": &"ing", &"origin": &"analog", &"glyph": "S", &"label_key": &"STARTUP_PICK_ANALOG_SURVIVALIST", &"backstory_key": &"STARTUP_BACKSTORY_SURVIVALIST"},
	&"enculted":    {&"stat": &"amb", &"origin": &"analog", &"glyph": "E", &"label_key": &"STARTUP_PICK_ANALOG_ENCULTED",    &"backstory_key": &"STARTUP_BACKSTORY_ENCULTED"},
	&"forged":      {&"stat": &"dev", &"origin": &"cyborg", &"glyph": "F", &"label_key": &"STARTUP_PICK_CYBORG_FORGED",      &"backstory_key": &"STARTUP_BACKSTORY_FORGED"},
	&"automaton":   {&"stat": &"opt", &"origin": &"cyborg", &"glyph": "A", &"label_key": &"STARTUP_PICK_CYBORG_AUTOMATON",   &"backstory_key": &"STARTUP_BACKSTORY_AUTOMATON"},
	&"polymath":    {&"stat": &"cla", &"origin": &"cyborg", &"glyph": "P", &"label_key": &"STARTUP_PICK_CYBORG_POLYMATH",    &"backstory_key": &"STARTUP_BACKSTORY_POLYMATH"},
}

# The two origin classes — same shape as CLASS_DEFINITIONS but no `stat` (origin
# classes use derived Soul/Interface, not a primary rolled stat). UI iterates
# this when offering origin selection (character creation, spec overlay).
const ORIGIN_DEFINITIONS: Dictionary = {
	&"analog": {&"glyph": "H", &"label_key": &"STARTUP_PICK_ANALOG", &"backstory_key": &"STARTUP_BACKSTORY_ANALOG"},
	&"cyborg": {&"glyph": "C", &"label_key": &"STARTUP_PICK_CYBORG", &"backstory_key": &"STARTUP_BACKSTORY_CYBORG"},
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
# primary = own class stat, kore = same origin, opp_kore = opposite origin, opposing = nemesis stat.
const RELATIONSHIP_COLORS: Dictionary = {
	&"primary":  Color(0.25, 1.0,  0.35, 1.0),
	&"kore":     Color(0.15, 0.38, 0.18, 1.0),
	&"opp_kore": Color(0.95, 0.80, 0.15, 1.0),
	&"opposing": Color(0.85, 0.18, 0.18, 1.0),
}

# Tier unlock thresholds (3 tiers): stat's share of total rollable stats.
#
# All thresholds are multiples of 33% — the simplest mental model: every
# tier costs another third of your stat budget. Reachable patterns are
# exactly three: 3-only (99% in one stat), 2-1 (66% + 33%), or 1-1-1
# (33% × 3). T3 is true all-in by design.
#
# Specialized classes:
#   TIERS_OWN           — own primary stat (T3 reachable at 99%)
#   TIERS_KORE_SPEC     — same-origin (kore) stats (T1/T2 reachable; T3 unreachable
#                         in practice since 66% + 99% own > 100%)
#   TIERS_OPPOSING_SPEC — opposite-origin stats (UNAVAILABLE — all sentinels)
#
# Origin classes (Analog / Cyborg):
#   TIERS_KORE_ORIGIN     — own origin's kore stats (same 33/66 ladder)
#   TIERS_OPPOSING_ORIGIN — opposite-origin stats (T1 dabble at 33%)
#
# >100% threshold (e.g. 1.01) is the "structurally unreachable" sentinel —
# the get_unlocked_tier loop never satisfies it because no stat can exceed
# 100% of the total. UI special-cases the sentinel to render those tiers
# as "unavailable" with a class-restriction tooltip rather than "locked".
# See docs/design/attribute-system.md § Breakpoints.
const TIERS_OWN:               Array[float] = [0.33, 0.66, 0.99]
const TIERS_KORE_SPEC:         Array[float] = [0.33, 0.66, 1.01]
const TIERS_OPPOSING_SPEC:     Array[float] = [1.01, 1.01, 1.01]
const TIERS_KORE_ORIGIN:       Array[float] = [0.33, 0.66, 1.01]
const TIERS_OPPOSING_ORIGIN:   Array[float] = [0.33, 1.01, 1.01]

# Talent tree node dimensions — 8 nodes per tier means 24 per class tree.
# With 20 talent points, even a fully committed build can't fill one tree.
const TALENT_NODES_PER_TIER := 8

# Origin class balance tier caps. Indexed 1–3. Single "no stat ≥ X" cap
# per tier — replaces the prior kore/opposing split because the simpler
# rule reads better and produces the same shape of incentive (don't let
# any one stat dominate). T3 lands exactly at perfect 33+33+33 balance.
const ORIGIN_TIER_CAPS: Array[float] = [
	0.0,   # index 0 — unused placeholder
	0.66,  # tier 1: no stat ≥ 66% (almost any non-extreme build)
	0.50,  # tier 2: no stat ≥ 50% (no single stat dominates)
	0.33,  # tier 3: no stat ≥ 33% (perfect 1-1-1 spread, exactly at cap)
]

# Kore nodes: 3-tier tree unlocked by combined kore stat share.
const KORE_NODE_TIER_COUNT := 3
const KORE_NODE_NODES_PER_TIER := 4
const KORE_NODE_THRESHOLDS: Array[float] = [0.20, 0.35, 0.50]

# ── Main-stat scaling (HP / Resource / Damage) ───────────────────────────────
# The player's "main stat" — the spec's primary stat for specialised classes,
# the origin's derived stat (Soul / Interface) for origin classes — is the
# ONLY stat that directly grants HP / resource / damage bonuses. Secondary
# stat investments are for unlocking perk tiers via the % allocation system,
# not for stat-stick stacking. Origin classes still get their derived stat
# scaling from their kore stats via Soul/Interface = avg(kore), so spreading
# investment across kore stats DOES contribute to HP/resource — just
# averaged through the derived stat instead of weighted.
#
# 1% damage per main-stat point gives roughly D2-shaped scaling: a fully-
# geared character lands in the +50–100% range.
const DAMAGE_PER_MAIN_STAT_PCT: float = 0.01

# How many bonus HP / resource-max each main-stat point grants.
const HP_PER_MAIN_STAT: float = 2.0
const RESOURCE_PER_MAIN_STAT: float = 1.0

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

## Returns the relationship of a stat to the given class: &"primary", &"kore", or &"opposing".
func get_stat_relationship(stat_id: StringName, class_id: StringName, spec_id: StringName) -> StringName:
	if spec_id != &"":
		if get_spec_stat(spec_id) == stat_id:
			return &"primary"
		return &"kore" if stat_id in get_kore_stats_for_origin(get_spec_origin(spec_id)) else &"opposing"
	# Origin class: no primary stat
	return &"kore" if stat_id in get_kore_stats_for_origin(class_id) else &"opposing"

## Returns the threshold array for unlocking each tier of a stat's tree.
## Branches on (origin vs specialized) × (own / kore / opposing). Sentinel
## thresholds (> 1.0) mark structurally unreachable tiers — UI renders them
## as "unavailable" with a class-restriction tooltip.
func get_tier_thresholds(stat_id: StringName, class_id: StringName, spec_id: StringName) -> Array[float]:
	if spec_id == &"":
		# Origin: no primary stat. Own kore stats cap at T2; opposing stats
		# cap at T1 so cross-aligned dabbling is possible but limited.
		if stat_id in get_kore_stats_for_origin(class_id):
			return TIERS_KORE_ORIGIN
		return TIERS_OPPOSING_ORIGIN
	# Specialized: own → T3, kore → T2, opposing → unavailable.
	match get_stat_relationship(stat_id, class_id, spec_id):
		&"primary": return TIERS_OWN
		&"kore":    return TIERS_KORE_SPEC
	return TIERS_OPPOSING_SPEC

## Returns the currently unlocked tier (0–3) for a stat tree given class context.
##
## Tiers stack additively across the budget — reaching T3 in one tree no longer
## zeroes the others, so specialized classes can land 3-1-1 or 3-2-0 patterns.
## Specialized classes are auto-granted T1 of their primary perk so class
## identity reads even before any stat investment. Origin classes are capped
## at T2 implicitly via the unreachable T3 threshold in TIERS_KORE_ORIGIN.
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
## Single rule: no stat may meet or exceed ORIGIN_TIER_CAPS[tier] — applies
## uniformly to kore and opposing stats (the prior split was complexity for
## no benefit). class_id is unused now that we don't need to distinguish
## kore from opposing stats — kept in the signature for caller stability.
func get_origin_tier(_class_id: StringName) -> int:
	var pcts := get_all_stat_pcts()
	var max_pct := 0.0
	for s in ROLLABLE_STATS:
		max_pct = maxf(max_pct, pcts.get(s, 0.0))
	for tier in range(TIER_COUNT, 0, -1):
		if max_pct < ORIGIN_TIER_CAPS[tier]:
			return tier
	return 0

## Returns the unlocked kore-nodes tier (0–3) based on combined kore stat share.
func get_kore_nodes_tier(class_id: StringName, spec_id: StringName) -> int:
	var origin: StringName = get_spec_origin(spec_id) if spec_id != &"" else class_id
	return get_kore_nodes_tier_for_origin(origin)

## Returns the unlocked kore-nodes tier (0–3) for a specific origin, regardless of player class.
func get_kore_nodes_tier_for_origin(origin: StringName) -> int:
	var pcts := get_all_stat_pcts()
	var combined := 0.0
	for s in get_kore_stats_for_origin(origin):
		combined += pcts.get(s, 0.0)
	var unlocked := 0
	for i in KORE_NODE_THRESHOLDS.size():
		if combined >= KORE_NODE_THRESHOLDS[i]:
			unlocked = i + 1
	return unlocked

func get_kore_stats_for_origin(origin: StringName) -> Array[StringName]:
	return ANALOG_KORE_STATS if origin == &"analog" else CYBORG_KORE_STATS

func get_opposing_stats_for_origin(origin: StringName) -> Array[StringName]:
	return CYBORG_KORE_STATS if origin == &"analog" else ANALOG_KORE_STATS

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

## Sort priority for stat relationship: primary(0) > kore(1) > opp_kore(2) > nemesis(3).
## Used to order segments in summary bars consistently across all UI.
func get_stat_rel_priority(stat_id: StringName, class_id: StringName, spec_id: StringName) -> int:
	var rel := get_stat_relationship(stat_id, class_id, spec_id)
	if rel == &"primary": return 0
	if rel == &"kore":    return 1
	var my_stat := get_spec_stat(spec_id)
	if my_stat != &"" and NEMESIS_STAT.get(my_stat, &"") == stat_id: return 3
	return 2

## Returns the RELATIONSHIP_COLORS key for a stat given class context.
## Distinguishes nemesis (&"opposing") from generic opposing-origin (&"opp_kore").
func get_stat_rel_color_key(stat_id: StringName, class_id: StringName, spec_id: StringName) -> StringName:
	var rel := get_stat_relationship(stat_id, class_id, spec_id)
	if rel == &"primary": return &"primary"
	if rel == &"kore":    return &"kore"
	var my_stat := get_spec_stat(spec_id)
	if my_stat != &"" and NEMESIS_STAT.get(my_stat, &"") == stat_id: return &"opposing"
	return &"opp_kore"

## Returns a BBCode-formatted scaling hint for a class/spec, used by selection UI.
## Stat names are wrapped in [color] tags matching their STAT_COLORS.
func get_scaling_hint(class_id: StringName, spec_id: StringName) -> String:
	var _colored := func(stat_id: StringName) -> String:
		var key: StringName = STAT_I18N.get(stat_id, &"")
		var label: String = tr(key) if key != &"" else String(stat_id).capitalize()
		var col: Color = STAT_COLORS.get(stat_id, Color.WHITE)
		return "[color=#%s]%s[/color]" % [col.to_html(false), label]

	if spec_id == &"":
		var origin_kore := get_kore_stats_for_origin(class_id)
		var origin_kore_names: Array[String] = []
		for s in origin_kore:
			origin_kore_names.append(_colored.call(s))
		var derived_stat: StringName = &"soul" if class_id == &"analog" else &"itf"
		var derived: String = _colored.call(derived_stat)
		return "HP, resource, and damage scale with %s (average of %s). Other stats unlock perk tiers." % [
			derived, ", ".join(origin_kore_names)]

	var primary: StringName = get_spec_stat(spec_id)
	var origin: StringName = get_spec_origin(spec_id)
	var kore := get_kore_stats_for_origin(origin)

	var kore_names: Array[String] = []
	for s in kore:
		if s != primary:
			kore_names.append(_colored.call(s))

	return "HP, resource, and damage scale with %s. Same-origin stats (%s) unlock supplementary perks." % [
		_colored.call(primary), " and ".join(kore_names)]

## Value of the player's main stat — the spec's primary stat for specialised
## classes, the origin's derived Soul/Interface for origin classes (which is
## the average of the origin's three kore stats, so spreading investment
## across kore stats DOES contribute to the main stat — just averaged).
## Drives bonus HP, resource, and damage. Secondary stat investments matter
## only for unlocking perk tiers via the % allocation system.
func get_main_stat_value(class_id: StringName, spec_id: StringName) -> int:
	var stat_id := get_class_main_stat_id(class_id, spec_id)
	if stat_id == &"":
		return 0
	return get_stat(stat_id)

## Bonus HP granted by the player's main stat for the given class context.
func get_stat_bonus_hp(class_id: StringName, spec_id: StringName) -> int:
	return int(float(get_main_stat_value(class_id, spec_id)) * HP_PER_MAIN_STAT)

## Bonus resource-pool max granted by the player's main stat for the given class context.
func get_stat_bonus_resource(class_id: StringName, spec_id: StringName) -> int:
	return int(float(get_main_stat_value(class_id, spec_id)) * RESOURCE_PER_MAIN_STAT)

func _avg3(a: int, b: int, c: int) -> int:
	return int(round((a + b + c) / 3.0))
