extends Node

# Item generator implementing the model in docs/design/item-architecture.md.
#
# Each item is rolled against a power budget determined by item level and rarity.
# Budget is spent across: base stats (slot domain), affix rolls, and universal
# bonuses (+HP, +resource). Behavior mods are not yet implemented — the mod
# field is reserved for future work.
#
# Public API:
#   roll(main_type, item_level, rarity, rng) -> Item
#   roll_random(item_level, rng) -> Item    (random main_type + weighted rarity)

const ILVL_EARLY_MAX: int = 33
const ILVL_MID_MAX: int = 66

const RARITY_WEIGHTS: Dictionary = {
	&"common": 80,
	&"magic":  14,
	&"rare":    5,
	&"unique":  1,
}

const RARITY_PREFIX_COUNT: Dictionary = {
	&"common": 0, &"magic": 1, &"rare": 1, &"unique": 1,
}
const RARITY_SUFFIX_COUNT: Dictionary = {
	&"common": 0, &"magic": 0, &"rare": 1, &"unique": 1,
}

## Rarity palette — shared by inventory glyphs, ground floating labels,
## drag previews, and tooltip name labels (via prototype_tooltip's
## _rarity_color, which mirrors these values). Keep all four entries in
## sync if any one is retuned. D2-standard palette: white common,
## blue magic, yellow rare, orange unique.
const RARITY_COLOR: Dictionary = {
	&"common": Color(0.95, 0.95, 0.95),
	&"magic":  Color(0.55, 0.75, 1.00),
	&"rare":   Color(1.00, 0.85, 0.35),
	&"unique": Color(1.00, 0.60, 0.20),
}

# Power budget multiplier per rarity tier. Higher rarity = more total budget.
const RARITY_BUDGET_MULT: Dictionary = {
	&"common": 1.0, &"magic": 1.15, &"rare": 1.3, &"unique": 1.5,
}


# Registry of weapon bases keyed by main_type, with per-base drop weights.
# Picker normalizes weights at roll time, so the numbers are relative — bump
# a base's weight to make it appear more often without rebalancing the rest.
# All bases at 1.0 = uniform within their main_type pool. Per-archetype
# absolute drop rate is equalised at the main_type layer below: 1H Weapon
# carries weight 3 (matching its 3 bases), 2H carries weight 5 (matching
# its 5 bases), so every weapon archetype lands at the same absolute
# probability per random drop regardless of which pool it lives in.
const WEAPON_BASE_DROPS: Dictionary = {
	"1H Weapon": [
		{"path": "res://resources/items/weapon_bases/melee_1h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/ranged_1h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/smg_1h.tres", "weight": 1.0},
	],
	"2H Weapon": [
		{"path": "res://resources/items/weapon_bases/melee_2h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/ranged_2h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/lmg_2h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/sniper_2h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/rpg_2h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/shotgun_2h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/accelerator_2h.tres", "weight": 1.0},
		{"path": "res://resources/items/weapon_bases/taser_2h.tres", "weight": 1.0},
	],
}

# Main-type weights for roll_random. Weapon main_types carry weight equal
# to their pool size so each weapon archetype lands at the same absolute
# probability per drop as every armor slot — without this, 2H bases were
# diluted across 5 archetypes (2.2% each) while 1H bases were diluted
# across 3 (3.7% each). With these weights everything sits at ~6.7% per
# random drop and a full set of 8 weapon archetypes shows up within the
# first ~15 random drops. Armor / backpack / grenade keep weight 1 each.
const MAIN_TYPE_WEIGHTS: Dictionary = {
	"1H Weapon": 3.0,
	"2H Weapon": 8.0,
	"Head Armor": 1.0,
	"Chest Armor": 1.0,
	"Gloves": 1.0,
	"Leg Armor": 1.0,
	"Boots": 1.0,
	"Backpack": 1.0,
	"Grenade": 1.0,
}

const OFFHAND_BASE_PATHS: Array[String] = [
	"res://resources/items/offhand_bases/shield_generator.tres",
	"res://resources/items/offhand_bases/active_shield.tres",
]

const GRENADE_BASE_PATHS: Array[String] = [
	"res://resources/items/grenade_bases/frag.tres",
	"res://resources/items/grenade_bases/incendiary.tres",
	"res://resources/items/grenade_bases/cluster.tres",
	"res://resources/items/grenade_bases/stun.tres",
]

# Per-armor-slot icon paths. Armor has one icon per slot (not per model
# name), so this maps main_type → fixed path instead of slugifying the
# randomly rolled sub_type.
const ARMOR_ICON_BY_TYPE: Dictionary = {
	"Head Armor":  "res://assets/ui/items/armor/head1.png",
	"Chest Armor": "res://assets/ui/items/armor/chest1.png",
	"Gloves":      "res://assets/ui/items/armor/hands1.png",
	"Leg Armor":   "res://assets/ui/items/armor/legs1.png",
	"Boots":       "res://assets/ui/items/armor/feet.png",
	"Backpack":    "res://assets/ui/items/armor/backpack1.png",
}


# Per-armor-slot model names — picked at roll time and stored on
# item.sub_type so the drop reads as "Vest" / "Overcoat" / "Shirt"
# instead of the generic archetype "Chest Armor". Same affix and
# flavor-prefix logic in _build_name handles the rest, so a magic
# rare drop becomes "Vicious Carbon Vest" instead of "Vicious Chest
# Armor". Pools intentionally mix mundane near-future ("Vest", "Cap")
# with corp / tactical ("Hardsuit", "Headset", "Greaves") to match the
# cyberpunk + body-horror tone without leaning too far either way.
const ARMOR_MODEL_NAMES: Dictionary = {
	"Head Armor": ["Helmet", "Hood", "Visor", "Cap", "Headset", "Mask", "Goggles"],
	"Chest Armor": ["Vest", "Overcoat", "Shirt", "Jacket", "Hardsuit", "Plate Rig", "Trenchcoat", "Tunic"],
	"Gloves": ["Gloves", "Gauntlets", "Mitts", "Hand Wraps", "Knuckle Guards", "Cuffs"],
	"Leg Armor": ["Greaves", "Cargo Pants", "Trousers", "Leggings", "Chaps", "Britches", "Cargos"],
	"Boots": ["Boots", "Stompers", "Treads", "Sneakers", "Footguards", "Slip-ons"],
	"Backpack": ["Pack", "Rucksack", "Satchel", "Duffel", "Knapsack", "Sling Bag"],
}


func roll(main_type: String, item_level: int, rarity: StringName, rng: RandomNumberGenerator) -> Item:
	var item := Item.new()
	item.main_type = main_type
	item.kind = SlotRegistry.slot_for_type(main_type)
	item.rarity = rarity
	item.item_level = item_level
	item.id = StringName("rolled_%d_%d" % [item_level, rng.randi()])
	item.glyph = SlotRegistry.glyph_for_type(main_type)
	item.glyph_color = RARITY_COLOR.get(rarity, Color.WHITE)
	item.stat_modifiers = {}

	if main_type == "2H Weapon":
		item.two_handed = true
	if main_type == "Backpack":
		item.stat_modifiers[&"inventory_bonus"] = 4

	_apply_weapon_base(item, main_type, rng)
	_roll_weapon_signature(item, rarity, rng)
	_apply_offhand_base(item, main_type, rng)
	_apply_grenade_base(item, main_type, rng)
	_apply_armor_model_name(item, main_type, rng)
	_apply_head_light_mod(item, main_type, item_level, rng)
	_apply_icon_path(item)

	var affix_labels: Array[String] = []
	var prefix_count: int = RARITY_PREFIX_COUNT.get(rarity, 0)
	for _i in prefix_count:
		var affix := AffixTable.roll_prefix(main_type, item_level, rng)
		if affix != null and _apply_affix(item, affix):
			affix_labels.append(affix.label)
	var suffix_count: int = RARITY_SUFFIX_COUNT.get(rarity, 0)
	for _i in suffix_count:
		var affix := AffixTable.roll_suffix(main_type, item_level, rng)
		if affix != null and _apply_affix(item, affix):
			affix_labels.append(affix.label)

	# Base damage reduction on defensive armor pieces (Head/Chest/Gloves/Legs).
	_roll_armor_defense(item, item_level, rarity, rng)

	# Universal secondary bonuses — every equippable item can roll +HP and +resource.
	_roll_universal_bonuses(item, item_level, rarity, rng)

	item.name_key = _build_name(main_type, item.sub_type, affix_labels, rng, item.model_name)
	return item

func roll_from_base(base: WeaponBase, item_level: int, rarity: StringName, rng: RandomNumberGenerator) -> Item:
	var main_type := "2H Weapon" if base.two_handed else "1H Weapon"
	var item := Item.new()
	item.main_type = main_type
	item.kind = SlotRegistry.slot_for_type(main_type)
	item.rarity = rarity
	item.item_level = item_level
	item.id = StringName("rolled_%d_%d" % [item_level, rng.randi()])
	item.glyph = SlotRegistry.glyph_for_type(main_type)
	item.glyph_color = RARITY_COLOR.get(rarity, Color.WHITE)
	item.stat_modifiers = {}
	if base.two_handed:
		item.two_handed = true
	_apply_weapon_base_direct(item, base, rng)
	_roll_weapon_signature(item, rarity, rng)
	var affix_labels: Array[String] = []
	var prefix_count: int = RARITY_PREFIX_COUNT.get(rarity, 0)
	for _i in prefix_count:
		var affix := AffixTable.roll_prefix(main_type, item_level, rng)
		if affix != null and _apply_affix(item, affix):
			affix_labels.append(affix.label)
	var suffix_count: int = RARITY_SUFFIX_COUNT.get(rarity, 0)
	for _i in suffix_count:
		var affix := AffixTable.roll_suffix(main_type, item_level, rng)
		if affix != null and _apply_affix(item, affix):
			affix_labels.append(affix.label)
	_roll_universal_bonuses(item, item_level, rarity, rng)
	_apply_icon_path(item)
	item.name_key = _build_name(main_type, item.sub_type, affix_labels, rng, item.model_name)
	return item

func roll_random(item_level: int, rng: RandomNumberGenerator) -> Item:
	var rarity := _roll_rarity(rng)
	var main_type := _pick_weighted_main_type(rng)
	return roll(main_type, item_level, rarity, rng)


# Weighted main-type picker. Iterates SlotRegistry.MAIN_TYPES (the
# canonical eligible list) and applies weights from MAIN_TYPE_WEIGHTS.
# Falls back to weight 1 for anything not explicitly weighted, so adding
# a new main_type to SlotRegistry doesn't break the picker — it just
# defaults to neutral weight until tuned here.
func _pick_weighted_main_type(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for mt: String in SlotRegistry.MAIN_TYPES:
		total += float(MAIN_TYPE_WEIGHTS.get(mt, 1.0))
	if total <= 0.0:
		return SlotRegistry.MAIN_TYPES[0]
	var roll_val := rng.randf() * total
	var accum := 0.0
	for mt: String in SlotRegistry.MAIN_TYPES:
		accum += float(MAIN_TYPE_WEIGHTS.get(mt, 1.0))
		if roll_val < accum:
			return mt
	return SlotRegistry.MAIN_TYPES[SlotRegistry.MAIN_TYPES.size() - 1]


## Parse a debug loadout string like "Grenade:frag" or "1H Weapon:ranged_1h"
## and return a rolled Item. Format: "MainType" or "MainType:base_id".
## Offhand entries with a skill name (e.g. "Offhand:active_shield") load
## the skill .tres directly and build a hand-constructed offhand.
func roll_debug_entry(entry: String, item_level: int, rng: RandomNumberGenerator) -> Item:
	var parts := entry.split(":", true, 1)
	var main_type := parts[0].strip_edges()
	var base_id := parts[1].strip_edges() if parts.size() > 1 else ""
	# Grenade with specific base.
	if main_type == "Grenade" and base_id != "":
		for path in GRENADE_BASE_PATHS:
			var base := load(path) as GrenadeBase
			if base != null and base.id == StringName(base_id):
				return _roll_grenade_from_base(base, item_level, rng)
		push_warning("[ItemRoller] unknown grenade base_id: %s" % base_id)
		return roll(main_type, item_level, &"common", rng)
	# Weapon with specific base.
	if (main_type == "1H Weapon" or main_type == "2H Weapon") and base_id != "":
		var drops: Array = WEAPON_BASE_DROPS.get(main_type, [])
		for drop: Dictionary in drops:
			var path := String(drop.get("path", ""))
			var base := load(path) as WeaponBase
			if base != null and base.id == StringName(base_id):
				return roll_from_base(base, item_level, &"common", rng)
		push_warning("[ItemRoller] unknown weapon base_id: %s" % base_id)
		return roll(main_type, item_level, &"common", rng)
	# Offhand with a skill name — load the skill .tres directly.
	if main_type == "Offhand" and base_id != "":
		var skill_path := "res://resources/skills/%s.tres" % base_id
		if ResourceLoader.exists(skill_path):
			var sk := load(skill_path) as Skill
			if sk != null:
				return _make_debug_offhand(sk, base_id)
		push_warning("[ItemRoller] unknown offhand skill: %s" % base_id)
	# Fallback — roll a random item of this type.
	return roll(main_type, item_level, &"common", rng)


func _roll_grenade_from_base(base: GrenadeBase, item_level: int, rng: RandomNumberGenerator) -> Item:
	var item := Item.new()
	item.main_type = "Grenade"
	item.kind = SlotRegistry.slot_for_type("Grenade")
	item.rarity = &"common"
	item.item_level = item_level
	item.id = StringName("debug_grenade_%d" % rng.randi())
	item.glyph = SlotRegistry.glyph_for_type("Grenade")
	item.glyph_color = RARITY_COLOR.get(&"common", Color.WHITE)
	item.stat_modifiers = {}
	item.weapon_base_id = base.id
	item.sub_type = base.display_name
	item.fire_skill = base.fire_skill
	if base.glyph != "":
		item.glyph = base.glyph
	_roll_damage(item, base, rng)
	item.crit_chance = rng.randf_range(base.crit_chance_range.x, base.crit_chance_range.y)
	item.blast_radius = rng.randf_range(base.blast_radius_range.x, base.blast_radius_range.y)
	item.name_key = base.display_name
	return item


func _make_debug_offhand(skill: Skill, label: String) -> Item:
	var item := Item.new()
	item.id = StringName("debug_offhand_%s" % label)
	item.kind = &"offhand"
	item.main_type = "Offhand"
	item.sub_type = skill.display_name
	item.glyph = SlotRegistry.glyph_for_type("Offhand")
	item.glyph_color = Color(0.85, 0.95, 0.85, 1.0)
	item.rarity = &"common"
	item.name_key = skill.display_name
	item.fire_skill = skill
	return item


## Per-archetype signature stat — the one number that defines the weapon's
## mechanical identity beyond the universal damage/speed/accuracy envelope.
## Stored in stat_modifiers so SaveManager, network serialization, and the
## effectiveness decay system all handle them automatically.
##   "key"  — stat_modifiers key
##   "base" — (min, max) before rarity scaling
##   "cap"  — optional hard ceiling (e.g. chain_retention can't exceed 95%)
## Per-archetype signature stats — each weapon base maps to one or more
## stats that define its mechanical identity. Each entry is an Array of
## stat definitions so archetypes like the Shotgun can roll both pellet
## count AND spread angle.
##   "key"     — stat_modifiers key
##   "base"    — (min, max) before rarity scaling
##   "cap"     — optional hard ceiling
##   "inverse" — true = lower is better; divides by rarity_mult instead
const WEAPON_SIGNATURE_STATS: Dictionary = {
	&"rpg_2h": [
		{ "key": &"blast_radius_bonus", "base": Vector2i(0, 3) },
	],
	&"shotgun_2h": [
		{ "key": &"pellet_count",  "base": Vector2i(7, 9) },
		{ "key": &"spread_angle",  "base": Vector2i(30, 45), "inverse": true },
	],
	&"ranged_2h": [
		{ "key": &"penetration", "base": Vector2i(1, 2) },
	],
	&"sniper_2h": [
		{ "key": &"headshot_bonus", "base": Vector2i(25, 50) },
	],
	&"taser_2h": [
		{ "key": &"chain_retention", "base": Vector2i(75, 85), "cap": 95 },
	],
	&"accelerator_2h": [
		{ "key": &"ramp_speed", "base": Vector2i(25, 60) },
	],
	&"melee_1h": [
		{ "key": &"bleed_damage", "base": Vector2i(2, 5) },
	],
	&"melee_2h": [
		{ "key": &"impact_radius", "base": Vector2i(2, 4) },
	],
	&"lmg_2h": [
		{ "key": &"sustained_bonus", "base": Vector2i(8, 18) },
	],
	&"smg_1h": [
		{ "key": &"ricochet_chance", "base": Vector2i(5, 12), "cap": 20 },
	],
	&"ranged_1h": [
		{ "key": &"overcharge_chance", "base": Vector2i(8, 15), "cap": 25 },
	],
}


## Roll the weapon's archetype-specific signature stats. Values scale with
## rarity via the same budget multiplier used for affix rolls. Stats marked
## "inverse" (lower = better, like spread_angle) divide by the multiplier
## instead. The effectiveness decay system handles level-based scaling
## automatically when combat code reads via get_effective_modifier.
func _roll_weapon_signature(item: Item, rarity: StringName, rng: RandomNumberGenerator) -> void:
	var sigs: Array = WEAPON_SIGNATURE_STATS.get(item.weapon_base_id, [])
	if sigs.is_empty():
		return
	var mult: float = float(RARITY_BUDGET_MULT.get(rarity, 1.0))
	for sig: Dictionary in sigs:
		var base_range: Vector2i = sig["base"]
		var base_val := rng.randi_range(base_range.x, base_range.y)
		var final_val: int
		if sig.get("inverse", false):
			final_val = int(round(float(base_val) / mult))
		else:
			final_val = int(round(float(base_val) * mult))
		var cap: int = int(sig.get("cap", 9999))
		item.stat_modifiers[sig["key"]] = mini(final_val, cap)


## Armor types that roll base damage_reduction. Only these 4 slots participate
## in the DR/resistance system — Boots get traction instead, Backpack gets
## inventory/HP.
const DR_ARMOR_TYPES: Array[String] = ["Head Armor", "Chest Armor", "Gloves", "Leg Armor"]

## Per-piece DR cap. Total cap is 4× this (one per DR armor slot).
const DR_PER_PIECE_CAP: int = 10

## Base DR scales with ilvl (0.3 per level) and rarity. A common ilvl 10 piece
## gets ~3% DR; a unique ilvl 30 piece gets ~14% (clamped to 10). With 4 slots
## of unique ilvl 30 gear you'd hit 40% total before effectiveness decay kicks
## in, which is the intended ceiling at that tier.
func _roll_armor_defense(item: Item, item_level: int, rarity: StringName, rng: RandomNumberGenerator) -> void:
	if item.main_type not in DR_ARMOR_TYPES:
		return
	var budget_mult: float = float(RARITY_BUDGET_MULT.get(rarity, 1.0))
	var base_dr := int(round(float(item_level) * 0.3 * budget_mult))
	# Small random variance ±1 so same-ilvl same-rarity pieces aren't identical.
	base_dr += rng.randi_range(-1, 1)
	base_dr = clampi(base_dr, 1, DR_PER_PIECE_CAP)
	var prior: int = int(item.stat_modifiers.get(&"damage_reduction", 0))
	item.stat_modifiers[&"damage_reduction"] = mini(prior + base_dr, DR_PER_PIECE_CAP)


## Roll universal +HP and +resource bonuses. Every equippable item can get these.
## The amount scales with item level; chance scales with rarity.
func _roll_universal_bonuses(item: Item, item_level: int, rarity: StringName, rng: RandomNumberGenerator) -> void:
	# Weapons skip universal HP / resource bonuses entirely — those are
	# incidental "vitality" stats that belong on armor and backpacks,
	# not on a weapon. A sword shouldn't roll +15 Max Health any more
	# than a chestpiece should roll +8 Damage. Weapons get their power
	# from the prefix/suffix tables (damage, crit, attack-speed, etc.)
	# and from their base weapon stats (damage_min/max, accuracy, etc).
	if item.main_type == "1H Weapon" or item.main_type == "2H Weapon":
		return
	var bonus_chance: float = 0.3
	match rarity:
		&"magic": bonus_chance = 0.5
		&"rare": bonus_chance = 0.7
		&"unique": bonus_chance = 0.9
	var hp_base := 3.0 + float(item_level) * 0.5
	var res_base := 2.0 + float(item_level) * 0.3
	if rng.randf() < bonus_chance:
		var hp := int(round(hp_base + rng.randf_range(-2.0, 2.0)))
		if hp > 0:
			item.stat_modifiers[&"max_health_bonus"] = int(item.stat_modifiers.get(&"max_health_bonus", 0)) + hp
	if rng.randf() < bonus_chance:
		var res := int(round(res_base + rng.randf_range(-1.0, 1.0)))
		if res > 0:
			item.stat_modifiers[&"max_resource_bonus"] = int(item.stat_modifiers.get(&"max_resource_bonus", 0)) + res


func _roll_rarity(rng: RandomNumberGenerator) -> StringName:
	var total := 0
	for r: StringName in RARITY_WEIGHTS:
		total += int(RARITY_WEIGHTS[r])
	var pick := rng.randi_range(0, total - 1)
	var acc := 0
	for r: StringName in RARITY_WEIGHTS:
		acc += int(RARITY_WEIGHTS[r])
		if pick < acc:
			return r
	return &"common"

## Applies the affix's stat_modifiers to the item, filtering out any
## stats that don't make sense for this specific item. Returns true if
## at least one stat actually applied — caller uses the return value
## to decide whether to add the affix's label to the item name (a
## skipped-entirely affix shouldn't show up as a prefix/suffix in the
## item's display name either).
func _apply_affix(item: Item, affix: ItemAffix) -> bool:
	var applied_any := false
	for k in affix.stat_modifiers:
		if not _stat_applies_to_item(item, k):
			continue
		var prior: int = int(item.stat_modifiers.get(k, 0))
		item.stat_modifiers[k] = prior + int(affix.stat_modifiers[k])
		applied_any = true
	return applied_any


# Per-stat eligibility check — drops stats from an affix when they're
# meaningless on the rolled item. The item-types filter on the affix
# table itself handles broad gating (weapon vs armor); this layer
# handles sub-type quirks like "bullet weapons don't pay resource."
func _stat_applies_to_item(item: Item, stat_id: StringName) -> bool:
	# resource_cost_reduction does nothing on bullet weapons — they
	# burn ammo, not the resource pool. The "of Efficiency" suffix
	# would otherwise read as a useful weapon stat the player can't
	# actually benefit from.
	if stat_id == &"resource_cost_reduction" and item.is_bullet_weapon():
		return false
	return true

# Roll the item's damage min/max from the base's damage_min_range and
# damage_max_range. Both WeaponBase and GrenadeBase expose those same
# two Vector2 fields, so the parameter is typed as Resource and duck-
# typed inside — typing as WeaponBase specifically would reject
# legitimate GrenadeBase calls from _roll_grenade_from_base.
# mini/maxi reorder so a max-roll under a min-roll doesn't invert.
func _roll_damage(item: Item, base: Resource, rng: RandomNumberGenerator) -> void:
	var dmin: int = int(round(rng.randf_range(base.damage_min_range.x, base.damage_min_range.y)))
	var dmax: int = int(round(rng.randf_range(base.damage_max_range.x, base.damage_max_range.y)))
	item.damage_min = mini(dmin, dmax)
	item.damage_max = maxi(dmin, dmax)

func _apply_weapon_base(item: Item, main_type: String, rng: RandomNumberGenerator) -> void:
	var drops: Array = WEAPON_BASE_DROPS.get(main_type, [])
	var path := _pick_weighted_path(drops, rng)
	if path == "":
		return
	var base := load(path) as WeaponBase
	if base == null:
		push_warning("[ItemRoller] missing WeaponBase: %s" % path)
		return
	_apply_weapon_base_direct(item, base, rng)


# Pick a path from a [{path, weight}] list weighted by the `weight` field.
# Returns "" on an empty list. Total weight is summed each call (not cached)
# because the drop list is short — keeping the picker stateless avoids
# invalidation when weights are tuned at runtime later.
func _pick_weighted_path(drops: Array, rng: RandomNumberGenerator) -> String:
	if drops.is_empty():
		return ""
	var total := 0.0
	for drop: Dictionary in drops:
		total += float(drop.get("weight", 1.0))
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	var accum := 0.0
	for drop: Dictionary in drops:
		accum += float(drop.get("weight", 1.0))
		if roll < accum:
			return String(drop.get("path", ""))
	# Fallback for floating-point edge case at the boundary.
	return String(drops[drops.size() - 1].get("path", ""))

func _apply_weapon_base_direct(item: Item, base: WeaponBase, rng: RandomNumberGenerator) -> void:
	item.weapon_base_id = base.id
	item.sub_type = base.display_name
	item.two_handed = base.two_handed
	item.fire_skill = base.fire_skill
	item.alt_fire_skill = base.alt_fire_skill
	var main_type := "2H Weapon" if base.two_handed else "1H Weapon"
	if item.glyph == SlotRegistry.glyph_for_type(main_type) and base.glyph != "":
		item.glyph = base.glyph
	_roll_damage(item, base, rng)
	item.attack_speed = rng.randf_range(base.attack_speed_range.x, base.attack_speed_range.y)
	item.crit_chance = rng.randf_range(base.crit_chance_range.x, base.crit_chance_range.y)
	item.accuracy = rng.randf_range(base.accuracy_range.x, base.accuracy_range.y)
	item.weapon_range = rng.randf_range(base.weapon_range_range.x, base.weapon_range_range.y)
	# Bullet weapons: roll an ammo capacity in the base's range and start
	# the magazine full. Energy weapons leave ammo_max == 0 and skip the
	# reload mechanic entirely.
	if base.ammo_capacity_range.y > 0:
		var lo: int = mini(base.ammo_capacity_range.x, base.ammo_capacity_range.y)
		var hi: int = maxi(base.ammo_capacity_range.x, base.ammo_capacity_range.y)
		item.ammo_max = rng.randi_range(maxi(1, lo), maxi(1, hi))
		item.ammo_current = item.ammo_max
		item.reload_time = base.reload_time
	# Damage-type resolution — pool first (random roll, e.g. Accelerator),
	# then fixed type (e.g. Taser is always electric). Empty for both
	# leaves damage_type at default neutral.
	if base.damage_type_pool.size() > 0:
		var idx := rng.randi_range(0, base.damage_type_pool.size() - 1)
		item.damage_type = base.damage_type_pool[idx]
	elif base.damage_type != &"":
		item.damage_type = base.damage_type
	# Model-name roll — pick one invented identity from the base's pool
	# so two drops of the same archetype read as different items in the
	# world. Empty pool leaves model_name blank and the display name
	# falls back to sub_type (the archetype's display_name).
	if base.model_names.size() > 0:
		var midx := rng.randi_range(0, base.model_names.size() - 1)
		item.model_name = base.model_names[midx]

# Pick a per-slot armor name from ARMOR_MODEL_NAMES and store it on
# item.sub_type. Display name resolution then uses sub_type as the
# noun (no model_name pool for armor — the slot name IS the variant)
# so a magic chest drop reads as "Vicious Vest" instead of "Vicious
# Chest Armor". Skipped for non-armor main_types and for armor slots
# missing from the pool dictionary (defensive — keeps roll() working
# if a new slot is added without updating the pool yet).
func _apply_armor_model_name(item: Item, main_type: String, rng: RandomNumberGenerator) -> void:
	if not ARMOR_MODEL_NAMES.has(main_type):
		return
	var pool: Array = ARMOR_MODEL_NAMES[main_type]
	if pool.is_empty():
		return
	item.sub_type = String(pool[rng.randi_range(0, pool.size() - 1)])


# Resolve the item's icon path. Armor uses ARMOR_ICON_BY_TYPE (one icon
# per slot); weapons, grenades, and offhands use sub_type → kebab-case
# slug. Skipped silently when no matching file exists so the item falls
# back to glyph rendering.
func _apply_icon_path(item: Item) -> void:
	if item == null:
		return
	var resolved := resolve_icon_path(item)
	if resolved != "":
		item.icon_path = resolved


## Public resolver — given an item's current weapon_base_id / sub_type /
## model_name, return the icon path that *would* be assigned at roll time.
## Returns "" when nothing matches. Used both by the roller (at item
## creation) and by SaveManager (to backfill icon_path on legacy saves
## that predate the icon system). Single source of truth for the slug
## rule keeps roll-time and load-time in lockstep.
func resolve_icon_path(item: Item) -> String:
	if item == null:
		return ""
	# Armor pieces have one icon per slot, not per model name.
	var armor_path: String = ARMOR_ICON_BY_TYPE.get(item.main_type, "")
	if armor_path != "":
		if ResourceLoader.exists(armor_path):
			return armor_path
		return ""
	# Weapons, offhands, and grenades use a slug from sub_type.
	# Slug rules: lowercase, spaces and underscores → hyphens.
	# "Laser Pistol" → "laser-pistol", "Frag Grenade" → "frag-grenade".
	# Weapons and grenades live in weapons/, offhands in armor/.
	if item.sub_type == "":
		return ""
	var slug: String = item.sub_type.to_lower().replace(" ", "-").replace("_", "-")
	var is_weapon: bool = item.main_type in ["1H Weapon", "2H Weapon", "Grenade"]
	var folder: String = "weapons" if is_weapon else "armor"
	# Try {slug}1.png first (most icons), then {slug}.png (shotgun, etc.).
	var path: String = "res://assets/ui/items/%s/%s1.png" % [folder, slug]
	if ResourceLoader.exists(path):
		return path
	path = "res://assets/ui/items/%s/%s.png" % [folder, slug]
	if ResourceLoader.exists(path):
		return path
	return ""


func _apply_offhand_base(item: Item, main_type: String, rng: RandomNumberGenerator) -> void:
	if main_type != "Offhand":
		return
	if OFFHAND_BASE_PATHS.is_empty():
		return
	var path: String = OFFHAND_BASE_PATHS[rng.randi_range(0, OFFHAND_BASE_PATHS.size() - 1)]
	var base := load(path) as OffhandBase
	if base == null:
		push_warning("[ItemRoller] missing OffhandBase: %s" % path)
		return
	item.sub_type = base.display_name
	item.fire_skill = base.fire_skill
	if base.glyph != "":
		item.glyph = base.glyph

func _apply_grenade_base(item: Item, main_type: String, rng: RandomNumberGenerator) -> void:
	if main_type != "Grenade":
		return
	if GRENADE_BASE_PATHS.is_empty():
		return
	var path: String = GRENADE_BASE_PATHS[rng.randi_range(0, GRENADE_BASE_PATHS.size() - 1)]
	var base := load(path) as GrenadeBase
	if base == null:
		push_warning("[ItemRoller] missing GrenadeBase: %s" % path)
		return
	item.weapon_base_id = base.id
	item.sub_type = base.display_name
	item.fire_skill = base.fire_skill
	if base.glyph != "":
		item.glyph = base.glyph
	_roll_damage(item, base, rng)
	item.crit_chance = rng.randf_range(base.crit_chance_range.x, base.crit_chance_range.y)
	item.blast_radius = rng.randf_range(base.blast_radius_range.x, base.blast_radius_range.y)

## Head armor rolls a light mod. Most helmets get a flashlight; rarer mods
## (scanner, UV) appear at higher item levels. Light stats scale with level.
const LIGHT_MOD_POOL: Array[Dictionary] = [
	{"mod": Item.LightMod.FLASHLIGHT, "weight": 50, "min_ilvl": 1},
	{"mod": Item.LightMod.RADIANT,    "weight": 30, "min_ilvl": 1},
	{"mod": Item.LightMod.SCANNER,    "weight": 15, "min_ilvl": 15},
	{"mod": Item.LightMod.UV,         "weight": 10, "min_ilvl": 25},
]

func _apply_head_light_mod(item: Item, main_type: String, item_level: int, rng: RandomNumberGenerator) -> void:
	if main_type != "Head Armor":
		return
	var eligible: Array[Dictionary] = []
	var total_weight := 0
	for entry: Dictionary in LIGHT_MOD_POOL:
		if item_level < int(entry["min_ilvl"]):
			continue
		eligible.append(entry)
		total_weight += int(entry["weight"])
	if eligible.is_empty():
		return
	var pick := rng.randi_range(0, total_weight - 1)
	var acc := 0
	var chosen: Dictionary = eligible[0]
	for entry: Dictionary in eligible:
		acc += int(entry["weight"])
		if pick < acc:
			chosen = entry
			break
	item.light_mod = chosen["mod"] as Item.LightMod
	item.light_energy = rng.randf_range(2.0, 3.5)
	item.light_range = rng.randf_range(12.0, 18.0)
	match item.light_mod:
		Item.LightMod.UV:
			item.light_color = Color(0.6, 0.2, 1.0)
		Item.LightMod.SCANNER:
			item.light_color = Color(0.2, 1.0, 0.4)
		_:
			item.light_color = Color.WHITE


# Flavor adjectives applied to common-rarity items that rolled zero
# affixes. Purely cosmetic — no stat impact, no gameplay meaning. The
# point is so two whites dropped side-by-side ("Sledgehammer" /
# "Sledgehammer") read as different items in the world. Rarity color
# (grey for common) still does the actual quality signal; this just
# breaks the visual repetition. Pool intentionally stays "low quality"
# in tone so it doesn't muddle the rarity ladder — magic items and
# above use real stat-affix prefixes which sound more impressive.
const COMMON_FLAVOR_ADJECTIVES: Array[String] = [
	"Worn", "Battered", "Old", "Plain", "Crude", "Salvaged",
	"Standard", "Stock", "Spartan", "Bare", "Basic", "Refurbished",
	"Issue-Grade", "Generic", "Mundane", "Unmarked",
]


func _build_name(main_type: String, sub_type: String, affix_labels: Array[String], rng: RandomNumberGenerator = null, model_name: String = "") -> String:
	# Noun precedence: rolled model name (e.g. "MK-7 Voidcaster") wins
	# over the archetype's display_name ("SMG"). Falls back to main_type
	# for items without a sub_type at all (rare edge case).
	var noun := main_type
	if model_name != "":
		noun = model_name
	elif sub_type != "":
		noun = sub_type
	if affix_labels.is_empty():
		# Common-rarity drop with no affixes — give it a flavor adjective
		# so it doesn't share its name with every other white of the same
		# base. RNG nullable to keep callers that don't need determinism
		# (debug spawners, tests) working without threading an RNG.
		var idx: int
		if rng != null:
			idx = rng.randi_range(0, COMMON_FLAVOR_ADJECTIVES.size() - 1)
		else:
			idx = randi() % COMMON_FLAVOR_ADJECTIVES.size()
		return "%s %s" % [COMMON_FLAVOR_ADJECTIVES[idx], noun]
	var prefixes: Array[String] = []
	var suffixes: Array[String] = []
	for label in affix_labels:
		if label.begins_with("of "):
			suffixes.append(label)
		else:
			prefixes.append(label)
	var parts: Array[String] = []
	parts.append_array(prefixes)
	parts.append(noun)
	parts.append_array(suffixes)
	return " ".join(parts)
