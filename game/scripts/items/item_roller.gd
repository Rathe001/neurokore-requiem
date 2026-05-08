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

const RARITY_COLOR: Dictionary = {
	&"common": Color(1.00, 1.00, 1.00),
	&"magic":  Color(0.35, 0.55, 1.00),
	&"rare":   Color(0.70, 0.30, 1.00),
	&"unique": Color(0.75, 0.50, 0.25),
}

# Power budget multiplier per rarity tier. Higher rarity = more total budget.
const RARITY_BUDGET_MULT: Dictionary = {
	&"common": 1.0, &"magic": 1.15, &"rare": 1.3, &"unique": 1.5,
}


# Registry of weapon bases keyed by main_type. The roller picks one at random
# when generating a weapon, then rolls each stat range into the Item instance.
const WEAPON_BASE_PATHS: Dictionary = {
	"1H Weapon": [
		"res://resources/items/weapon_bases/melee_1h.tres",
		"res://resources/items/weapon_bases/ranged_1h.tres",
	],
	"2H Weapon": [
		"res://resources/items/weapon_bases/melee_2h.tres",
		"res://resources/items/weapon_bases/ranged_2h.tres",
	],
}

const OFFHAND_BASE_PATHS: Array[String] = [
	"res://resources/items/offhand_bases/buckler.tres",
	"res://resources/items/offhand_bases/shield_generator.tres",
	"res://resources/items/offhand_bases/active_shield.tres",
]

const GRENADE_BASE_PATHS: Array[String] = [
	"res://resources/items/grenade_bases/frag.tres",
	"res://resources/items/grenade_bases/incendiary.tres",
	"res://resources/items/grenade_bases/cluster.tres",
	"res://resources/items/grenade_bases/stun.tres",
]


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
	_apply_offhand_base(item, main_type, rng)
	_apply_grenade_base(item, main_type, rng)
	_apply_head_light_mod(item, main_type, item_level, rng)

	var affix_labels: Array[String] = []
	var prefix_count: int = RARITY_PREFIX_COUNT.get(rarity, 0)
	for _i in prefix_count:
		var affix := AffixTable.roll_prefix(main_type, item_level, rng)
		if affix != null:
			_apply_affix(item, affix)
			affix_labels.append(affix.label)
	var suffix_count: int = RARITY_SUFFIX_COUNT.get(rarity, 0)
	for _i in suffix_count:
		var affix := AffixTable.roll_suffix(main_type, item_level, rng)
		if affix != null:
			_apply_affix(item, affix)
			affix_labels.append(affix.label)

	# Universal secondary bonuses — every equippable item can roll +HP and +resource.
	_roll_universal_bonuses(item, item_level, rarity, rng)

	item.name_key = _build_name(main_type, item.sub_type, affix_labels)
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
	var affix_labels: Array[String] = []
	var prefix_count: int = RARITY_PREFIX_COUNT.get(rarity, 0)
	for _i in prefix_count:
		var affix := AffixTable.roll_prefix(main_type, item_level, rng)
		if affix != null:
			_apply_affix(item, affix)
			affix_labels.append(affix.label)
	var suffix_count: int = RARITY_SUFFIX_COUNT.get(rarity, 0)
	for _i in suffix_count:
		var affix := AffixTable.roll_suffix(main_type, item_level, rng)
		if affix != null:
			_apply_affix(item, affix)
			affix_labels.append(affix.label)
	_roll_universal_bonuses(item, item_level, rarity, rng)
	item.name_key = _build_name(main_type, item.sub_type, affix_labels)
	return item

func roll_random(item_level: int, rng: RandomNumberGenerator) -> Item:
	var rarity := _roll_rarity(rng)
	var pool := SlotRegistry.MAIN_TYPES
	var main_type: String = pool[rng.randi_range(0, pool.size() - 1)]
	return roll(main_type, item_level, rarity, rng)


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
		var paths: Array = WEAPON_BASE_PATHS.get(main_type, [])
		for path: String in paths:
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
	var dmin := int(round(rng.randf_range(base.damage_min_range.x, base.damage_min_range.y)))
	var dmax := int(round(rng.randf_range(base.damage_max_range.x, base.damage_max_range.y)))
	item.damage_min = mini(dmin, dmax)
	item.damage_max = maxi(dmin, dmax)
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


## Roll universal +HP and +resource bonuses. Every equippable item can get these.
## The amount scales with item level; chance scales with rarity.
func _roll_universal_bonuses(item: Item, item_level: int, rarity: StringName, rng: RandomNumberGenerator) -> void:
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

func _apply_affix(item: Item, affix: ItemAffix) -> void:
	for k in affix.stat_modifiers:
		var prior: int = int(item.stat_modifiers.get(k, 0))
		item.stat_modifiers[k] = prior + int(affix.stat_modifiers[k])

func _apply_weapon_base(item: Item, main_type: String, rng: RandomNumberGenerator) -> void:
	var paths: Array = WEAPON_BASE_PATHS.get(main_type, [])
	if paths.is_empty():
		return
	var path: String = paths[rng.randi_range(0, paths.size() - 1)]
	var base := load(path) as WeaponBase
	if base == null:
		push_warning("[ItemRoller] missing WeaponBase: %s" % path)
		return
	_apply_weapon_base_direct(item, base, rng)

func _apply_weapon_base_direct(item: Item, base: WeaponBase, rng: RandomNumberGenerator) -> void:
	item.weapon_base_id = base.id
	item.sub_type = base.display_name
	item.two_handed = base.two_handed
	item.fire_skill = base.fire_skill
	item.alt_fire_skill = base.alt_fire_skill
	var main_type := "2H Weapon" if base.two_handed else "1H Weapon"
	if item.glyph == SlotRegistry.glyph_for_type(main_type) and base.glyph != "":
		item.glyph = base.glyph
	# Damage roll: ensure max >= min so combat damage rolls aren't inverted.
	var dmin := int(round(rng.randf_range(base.damage_min_range.x, base.damage_min_range.y)))
	var dmax := int(round(rng.randf_range(base.damage_max_range.x, base.damage_max_range.y)))
	item.damage_min = mini(dmin, dmax)
	item.damage_max = maxi(dmin, dmax)
	item.attack_speed = rng.randf_range(base.attack_speed_range.x, base.attack_speed_range.y)
	item.crit_chance = rng.randf_range(base.crit_chance_range.x, base.crit_chance_range.y)
	item.accuracy = rng.randf_range(base.accuracy_range.x, base.accuracy_range.y)
	item.weapon_range = rng.randf_range(base.weapon_range_range.x, base.weapon_range_range.y)

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
	var dmin := int(round(rng.randf_range(base.damage_min_range.x, base.damage_min_range.y)))
	var dmax := int(round(rng.randf_range(base.damage_max_range.x, base.damage_max_range.y)))
	item.damage_min = mini(dmin, dmax)
	item.damage_max = maxi(dmin, dmax)
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


func _build_name(main_type: String, sub_type: String, affix_labels: Array[String]) -> String:
	var noun := sub_type if sub_type != "" else main_type
	if affix_labels.is_empty():
		return noun
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
