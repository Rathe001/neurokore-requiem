extends Node

## All prefix and suffix definitions for item generation.
##
## Usage:
##   AffixTable.get_prefixes("1H Weapon")  -> Array[ItemAffix]
##   AffixTable.get_suffixes("Chest Armor") -> Array[ItemAffix]
##   AffixTable.roll_prefix("1H Weapon", item_level, rng) -> ItemAffix or null
##   AffixTable.roll_suffix("1H Weapon", item_level, rng) -> ItemAffix or null
##
## item_types match Item.main_type strings exactly. An affix with an empty
## item_types list is universal and appears on every item type.

# ─────────────────────────────────────────────────────────────────────────────
# PREFIXES
# ─────────────────────────────────────────────────────────────────────────────

const PREFIXES: Array[Dictionary] = [
	# ── Weapon prefixes ──────────────────────────────────────────────────────
	{
		"id": &"searing",
		"label": "Searing",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "fire_damage_bonus": 10 },
		"min_item_level": 1,
		"weight": 100,
	},
	{
		"id": &"precise",
		"label": "Precise",
		"item_types": ["Head Armor"],
		"stat_modifiers": { "crit_chance_bonus": 5 },
		"min_item_level": 1,
		"weight": 100,
	},
	{
		"id": &"brutal",
		"label": "Brutal",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "base_damage_bonus": 8 },
		"min_item_level": 1,
		"weight": 100,
	},
	{
		"id": &"swift",
		"label": "Swift",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "cooldown_reduction": 10 },
		"min_item_level": 5,
		"weight": 80,
	},
	{
		"id": &"cryo",
		"label": "Cryo",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "cryo_damage_bonus": 10 },
		"min_item_level": 8,
		"weight": 70,
	},
	{
		"id": &"voltaic",
		"label": "Voltaic",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "electric_damage_bonus": 10 },
		"min_item_level": 8,
		"weight": 70,
	},
	{
		"id": &"toxic",
		"label": "Toxic",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "toxic_damage_bonus": 10 },
		"min_item_level": 8,
		"weight": 70,
	},
	{
		"id": &"honed",
		"label": "Honed",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "hit_chance_bonus": 6 },
		"min_item_level": 1,
		"weight": 90,
	},
	{
		"id": &"vicious",
		"label": "Vicious",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "crit_damage_bonus": 15 },
		"min_item_level": 5,
		"weight": 80,
	},
	{
		"id": &"rapid",
		"label": "Rapid",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "attack_speed_bonus": 8 },
		"min_item_level": 3,
		"weight": 80,
	},
	# ── Armor prefixes ───────────────────────────────────────────────────────
	{
		"id": &"hardened",
		"label": "Hardened",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor"],
		"stat_modifiers": { "damage_reduction": 6 },
		"min_item_level": 1,
		"weight": 100,
	},
	{
		"id": &"nimble",
		"label": "Nimble",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor", "Boots"],
		"stat_modifiers": { "move_speed_bonus": 5 },
		"min_item_level": 1,
		"weight": 90,
	},
	{
		"id": &"fortified",
		"label": "Fortified",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor", "Boots"],
		"stat_modifiers": { "max_health_bonus": 15 },
		"min_item_level": 1,
		"weight": 90,
	},
	{
		"id": &"insulated",
		"label": "Insulated",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor"],
		"stat_modifiers": { "electric_resistance": 8 },
		"min_item_level": 5,
		"weight": 70,
	},
	{
		"id": &"cryo_lined",
		"label": "Cryo-Lined",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor"],
		"stat_modifiers": { "cryo_resistance": 8 },
		"min_item_level": 5,
		"weight": 70,
	},
	{
		"id": &"hazmat",
		"label": "Hazmat",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor"],
		"stat_modifiers": { "toxic_resistance": 8 },
		"min_item_level": 5,
		"weight": 70,
	},
	# ── Gloves-only unarmed prefixes ─────────────────────────────────────────
	# These make unarmed viable when combined with the bare-fist fallback.
	# Spiked is the bread-and-butter damage boost; Concussive adds CC;
	# Shockwave gives AoE so unarmed can clear small packs.
	{
		"id": &"spiked",
		"label": "Spiked",
		"item_types": ["Gloves"],
		"stat_modifiers": { "unarmed_damage_bonus": 8 },
		"min_item_level": 1,
		"weight": 80,
	},
	{
		"id": &"concussive",
		"label": "Concussive",
		"item_types": ["Gloves"],
		"stat_modifiers": { "unarmed_stun_chance": 20 },
		"min_item_level": 5,
		"weight": 60,
	},
	{
		"id": &"shockwave",
		"label": "Shockwave",
		"item_types": ["Gloves"],
		"stat_modifiers": { "unarmed_aoe_radius": 3 },
		"min_item_level": 8,
		"weight": 50,
	},
	# ── Boots-only traction prefixes ─────────────────────────────────────────
	# Traction is the boots stat domain. Under the new per-surface curve
	# (k/(k+traction)), traction is open-ended — endgame boots can reach
	# 500+ from a level-scaled base roll alone. These flat-bonus affixes
	# stack on TOP of the base roll, gated by min_item_level so early
	# items don't get the bigger numbers.
	# A future affix-table expansion will add higher-tier traction
	# affixes (e.g. +200 at ilvl 200) to keep affix bonuses proportionally
	# meaningful at endgame.
	{
		"id": &"surefooted",
		"label": "Surefooted",
		"item_types": ["Boots"],
		"stat_modifiers": { "traction_bonus": 25 },
		"min_item_level": 1,
		"weight": 100,
	},
	{
		"id": &"iron_soled",
		"label": "Iron-Soled",
		"item_types": ["Boots"],
		"stat_modifiers": { "traction_bonus": 50 },
		"min_item_level": 25,
		"weight": 60,
	},
	{
		"id": &"mag_plated",
		"label": "Mag-Plated",
		"item_types": ["Boots"],
		"stat_modifiers": { "traction_bonus": 75 },
		"min_item_level": 50,
		"weight": 25,
	},
	# ── Grenade prefixes ────────────────────────────────────────────────────
	{
		"id": &"volatile",
		"label": "Volatile",
		"item_types": ["Grenade"],
		"stat_modifiers": { "damage_bonus_pct": 15 },
		"min_item_level": 1,
		"weight": 100,
	},
	{
		"id": &"wide_blast",
		"label": "Wide-Blast",
		"item_types": ["Grenade"],
		"stat_modifiers": { "blast_radius_bonus": 1.0 },
		"min_item_level": 3,
		"weight": 80,
	},
	# ── Backpack prefixes ────────────────────────────────────────────────────
	{
		"id": &"spacious",
		"label": "Spacious",
		"item_types": ["Backpack"],
		"stat_modifiers": { "inventory_bonus": 2 },
		"min_item_level": 1,
		"weight": 100,
	},
	{
		"id": &"reinforced_pack",
		"label": "Reinforced",
		"item_types": ["Backpack"],
		"stat_modifiers": { "inventory_bonus": 1, "max_health_bonus": 10 },
		"min_item_level": 5,
		"weight": 70,
	},
	# ── Sustain prefixes ─────────────────────────────────────────────────────
	{
		"id": &"hardened",
		"label": "Hardened",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor", "Boots"],
		"stat_modifiers": { "barrier_on_kill": 5 },
		"min_item_level": 1,
		"weight": 70,
	},
]

# ─────────────────────────────────────────────────────────────────────────────
# SUFFIXES
# ─────────────────────────────────────────────────────────────────────────────

const SUFFIXES: Array[Dictionary] = [
	# ── Weapon suffixes ──────────────────────────────────────────────────────
	{
		"id": &"of_the_marksman",
		"label": "of the Marksman",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "range_bonus": 8 },
		"min_item_level": 1,
		"weight": 90,
	},
	{
		"id": &"of_devastation",
		"label": "of Devastation",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "knockback_bonus": 12 },
		"min_item_level": 1,
		"weight": 90,
	},
	{
		"id": &"of_efficiency",
		"label": "of Efficiency",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "resource_cost_reduction": 10 },
		"min_item_level": 5,
		"weight": 80,
	},
	{
		"id": &"of_the_leech",
		"label": "of the Leech",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "lifesteal_percent": 3 },
		"min_item_level": 10,
		"weight": 60,
	},
	{
		"id": &"of_perforation",
		"label": "of Perforation",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "armor_penetration": 8 },
		"min_item_level": 8,
		"weight": 70,
	},
	# ── Grenade suffixes ─────────────────────────────────────────────────────
	{
		"id": &"of_concussion",
		"label": "of Concussion",
		"item_types": ["Grenade"],
		"stat_modifiers": { "knockback_bonus": 3 },
		"min_item_level": 1,
		"weight": 90,
	},
	{
		"id": &"of_shrapnel",
		"label": "of Shrapnel",
		"item_types": ["Grenade"],
		"stat_modifiers": { "crit_chance_bonus": 0.08 },
		"min_item_level": 5,
		"weight": 80,
	},
	# ── Armor suffixes ───────────────────────────────────────────────────────
	{
		"id": &"of_the_bear",
		"label": "of the Bear",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor", "Boots", "Backpack"],
		"stat_modifiers": { "carry_capacity_bonus": 10 },
		"min_item_level": 1,
		"weight": 90,
	},
	{
		"id": &"of_resilience",
		"label": "of Resilience",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor"],
		"stat_modifiers": { "elemental_resistance": 6 },
		"min_item_level": 5,
		"weight": 80,
	},
	{
		"id": &"of_the_vault",
		"label": "of the Vault",
		"item_types": ["Head Armor", "Chest Armor", "Gloves", "Leg Armor", "Boots"],
		"stat_modifiers": { "max_health_bonus": 10 },
		"min_item_level": 1,
		"weight": 90,
	},
	{
		"id": &"of_renewal",
		"label": "of Renewal",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "resource_on_hit": 2 },
		"min_item_level": 5,
		"weight": 75,
	},
	# ── Sustain suffixes ─────────────────────────────────────────────────────
	{
		"id": &"of_vitality",
		"label": "of Vitality",
		"item_types": ["1H Weapon", "2H Weapon", "Head Armor", "Chest Armor", "Gloves", "Leg Armor", "Boots"],
		"stat_modifiers": { "life_on_kill": 5 },
		"min_item_level": 1,
		"weight": 85,
	},
	{
		"id": &"of_the_parasite",
		"label": "of the Parasite",
		"item_types": ["1H Weapon", "2H Weapon"],
		"stat_modifiers": { "life_on_kill": 8 },
		"min_item_level": 8,
		"weight": 60,
	},
]

# ─────────────────────────────────────────────────────────────────────────────
# Runtime cache — built once on first access. Affixes are also pre-bucketed
# by item_type so roll_*/get_* avoid a full-pool scan; with N affixes and M
# rolls per drop, this turns the inner cost from O(N) to O(applicable).
# Universal affixes (empty item_types) live in a separate bucket and are
# unioned into every type-specific result.
# ─────────────────────────────────────────────────────────────────────────────

var _prefixes: Array[ItemAffix] = []
var _suffixes: Array[ItemAffix] = []
var _prefixes_by_type: Dictionary = {}
var _suffixes_by_type: Dictionary = {}
var _prefixes_universal: Array[ItemAffix] = []
var _suffixes_universal: Array[ItemAffix] = []
var _ready_called := false

func _ready() -> void:
	_build_cache()

func _build_cache() -> void:
	if _ready_called:
		return
	_ready_called = true
	for d in PREFIXES:
		var a := _dict_to_affix(d, ItemAffix.Kind.PREFIX)
		_prefixes.append(a)
		_index_affix(a, _prefixes_by_type, _prefixes_universal)
	for d in SUFFIXES:
		var a := _dict_to_affix(d, ItemAffix.Kind.SUFFIX)
		_suffixes.append(a)
		_index_affix(a, _suffixes_by_type, _suffixes_universal)

func _index_affix(a: ItemAffix, by_type: Dictionary, universal: Array[ItemAffix]) -> void:
	if a.item_types.is_empty():
		universal.append(a)
		return
	for t: String in a.item_types:
		if not by_type.has(t):
			by_type[t] = []
		var bucket: Array = by_type[t]
		bucket.append(a)

func _dict_to_affix(d: Dictionary, kind: ItemAffix.Kind) -> ItemAffix:
	var a := ItemAffix.new()
	a.id = d.get("id", &"")
	a.label = d.get("label", "")
	a.kind = kind
	a.item_types = Array(d.get("item_types", []), TYPE_STRING, "", null)
	# Normalise stat_modifier keys to StringName. Dict literals in this file
	# use plain "string" keys for readability, but downstream readers
	# (Item.get_modifier, AttributeState, prototype_tooltip) all index by
	# StringName — and Dictionary treats String and StringName as distinct
	# keys, so a string-keyed entry would silently never match.
	var raw: Dictionary = d.get("stat_modifiers", {})
	var normalised: Dictionary = {}
	for k in raw:
		normalised[StringName(k)] = raw[k]
	a.stat_modifiers = normalised
	a.min_item_level = d.get("min_item_level", 1)
	a.weight = d.get("weight", 100)
	return a

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## All prefixes valid for item_type at item_level.
func get_prefixes(item_type: String, item_level: int = 1) -> Array[ItemAffix]:
	_build_cache()
	return _filter_buckets(_prefixes_by_type, _prefixes_universal, item_type, item_level)

## All suffixes valid for item_type at item_level.
func get_suffixes(item_type: String, item_level: int = 1) -> Array[ItemAffix]:
	_build_cache()
	return _filter_buckets(_suffixes_by_type, _suffixes_universal, item_type, item_level)

## Weighted random prefix roll. Returns null if the pool is empty.
func roll_prefix(item_type: String, item_level: int, rng: RandomNumberGenerator) -> ItemAffix:
	return _weighted_pick(get_prefixes(item_type, item_level), rng)

## Weighted random suffix roll. Returns null if the pool is empty.
func roll_suffix(item_type: String, item_level: int, rng: RandomNumberGenerator) -> ItemAffix:
	return _weighted_pick(get_suffixes(item_type, item_level), rng)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _filter_buckets(by_type: Dictionary, universal: Array[ItemAffix], item_type: String, item_level: int) -> Array[ItemAffix]:
	var out: Array[ItemAffix] = []
	var typed: Array = by_type.get(item_type, [])
	for a: ItemAffix in typed:
		if a.min_item_level <= item_level:
			out.append(a)
	for a in universal:
		if a.min_item_level <= item_level:
			out.append(a)
	return out

func _weighted_pick(pool: Array[ItemAffix], rng: RandomNumberGenerator) -> ItemAffix:
	if pool.is_empty():
		return null
	var total := 0
	for a in pool:
		total += a.weight
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for a in pool:
		acc += a.weight
		if roll < acc:
			return a
	return pool[-1]
