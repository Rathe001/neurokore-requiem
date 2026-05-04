extends Node

# Item generator implementing the model in docs/design/item-architecture.md.
#
# Two independent slot systems:
#   - Combat affixes: prefix/suffix pool, count gated by rarity.
#   - Class attribute stat slots: separate, count gated by item level.
#
# Public API:
#   roll(main_type, item_level, rarity, rng) -> Item
#   roll_random(item_level, rng) -> Item    (random main_type + weighted rarity)

const ILVL_EARLY_MAX: int = 33
const ILVL_MID_MAX: int = 66

const RARITY_WEIGHTS: Dictionary = {
	&"common": 60,
	&"magic":  25,
	&"rare":   12,
	&"unique":  3,
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

const GRENADE_BASE_PATHS: Array[String] = [
	"res://resources/items/grenade_bases/frag.tres",
	"res://resources/items/grenade_bases/incendiary.tres",
	"res://resources/items/grenade_bases/cluster.tres",
	"res://resources/items/grenade_bases/stun.tres",
]

# Optics variants — loaded from individual .tres files at _ready into
# `_optics_variants`. Adding a new optic = author a new .tres in the optics
# directory and add its path here. Per-variant tunables (range, energy,
# colour, glyph) live in the editor; this file only handles dispatch.
const OPTICS_VARIANT_PATHS: Array[String] = [
	"res://resources/items/optics/flashlight.tres",
	"res://resources/items/optics/lantern.tres",
	"res://resources/items/optics/scanner.tres",
	"res://resources/items/optics/uv_light.tres",
]
var _optics_variants: Array[OpticsVariant] = []


func _ready() -> void:
	for path in OPTICS_VARIANT_PATHS:
		var v := load(path) as OpticsVariant
		if v == null:
			push_warning("[ItemRoller] Optics variant at %s isn't an OpticsVariant; skipping." % path)
			continue
		_optics_variants.append(v)

func roll(main_type: String, item_level: int, rarity: StringName, rng: RandomNumberGenerator, class_stat_pool: Array[StringName] = []) -> Item:
	var item := Item.new()
	item.main_type = main_type
	item.kind = SlotRegistry.slot_for_type(main_type)
	item.rarity = rarity
	item.id = StringName("rolled_%d_%d" % [item_level, rng.randi()])
	item.glyph = SlotRegistry.glyph_for_type(main_type)
	item.glyph_color = RARITY_COLOR.get(rarity, Color.WHITE)
	item.stat_modifiers = {}

	if main_type == "2H Weapon":
		item.two_handed = true
	# Backpacks always grant their base bag bonus regardless of affix roll —
	# without this floor a "Backpack" item could roll with zero slots when
	# none of its prefixes happen to be inventory_bonus, which makes the
	# pickup useless. Affixes layer on top via stat_modifiers[&"inventory_bonus"].
	if main_type == "Backpack":
		item.stat_modifiers[&"inventory_bonus"] = 8

	_apply_weapon_base(item, main_type, rng)
	_apply_grenade_base(item, main_type, rng)
	_apply_optics_variant(item, main_type, rng)

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

	var slot_count := _class_slot_count(item_level, rng)
	for s: StringName in _pick_class_stats(slot_count, rng, class_stat_pool):
		var value := _class_stat_value(item_level, rng)
		item.stat_modifiers[s] = int(item.stat_modifiers.get(s, 0)) + value

	item.name_key = _build_name(main_type, item.sub_type, affix_labels)
	return item

func roll_from_base(base: WeaponBase, item_level: int, rarity: StringName, rng: RandomNumberGenerator, class_stat_pool: Array[StringName] = []) -> Item:
	var main_type := "2H Weapon" if base.two_handed else "1H Weapon"
	var item := Item.new()
	item.main_type = main_type
	item.kind = SlotRegistry.slot_for_type(main_type)
	item.rarity = rarity
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
	var slot_count := _class_slot_count(item_level, rng)
	for s: StringName in _pick_class_stats(slot_count, rng, class_stat_pool):
		var value := _class_stat_value(item_level, rng)
		item.stat_modifiers[s] = int(item.stat_modifiers.get(s, 0)) + value
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

func _class_slot_count(item_level: int, rng: RandomNumberGenerator) -> int:
	if item_level <= ILVL_EARLY_MAX:
		return 1
	if item_level <= ILVL_MID_MAX:
		return rng.randi_range(1, 2)
	return rng.randi_range(1, 3)

func _pick_class_stats(count: int, _rng: RandomNumberGenerator, pool_override: Array[StringName] = []) -> Array[StringName]:
	# Default pool is all rollable stats (any item can roll any class
	# attribute slot). Callers that want a constrained pool — e.g. the
	# starter weapon kit constraining to the player's kore stats — pass
	# pool_override; an empty override falls back to the full pool.
	var pool: Array[StringName] = []
	var source: Array[StringName] = pool_override if not pool_override.is_empty() else AttributeState.ROLLABLE_STATS
	for s: StringName in source:
		pool.append(s)
	pool.shuffle()
	var picked: Array[StringName] = []
	for i in mini(count, pool.size()):
		picked.append(pool[i])
	return picked

# ilvl 1  -> ~5, ilvl 50 -> ~22, ilvl 100 -> ~40.
func _class_stat_value(item_level: int, rng: RandomNumberGenerator) -> int:
	var base := 5.0 + float(item_level) * 0.35
	return int(round(base + rng.randf_range(-2.0, 2.0)))

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

func _apply_optics_variant(item: Item, main_type: String, rng: RandomNumberGenerator) -> void:
	if main_type != "Recon" or _optics_variants.is_empty():
		return
	var variant := _optics_variants[rng.randi_range(0, _optics_variants.size() - 1)]
	_assign_optics_variant(item, variant, rng)

func _assign_optics_variant(item: Item, variant: OpticsVariant, rng: RandomNumberGenerator) -> void:
	item.light_type = variant.light_type
	item.light_range = variant.light_range
	item.light_energy = rng.randf_range(variant.light_energy_min, variant.light_energy_max)
	item.light_color = variant.light_color
	# sub_type is the bucket label ("Radar", "Flashlight"); display_name
	# is the marketing string used in the rolled item name. Fall back to
	# display_name when sub_type isn't set so legacy variants still render.
	item.sub_type = variant.sub_type if variant.sub_type != "" else variant.display_name
	item.glyph = variant.glyph

# Returns one Optics item per declared variant (Flashlight, Lantern, Scanner,
# UV) at the given item level. Used by the starter chest so the player can
# sample every light type without depending on a random roll.
func roll_one_per_optics_variant(item_level: int, rng: RandomNumberGenerator) -> Array[Item]:
	var out: Array[Item] = []
	for variant in _optics_variants:
		var item := Item.new()
		item.main_type = "Recon"
		item.kind = SlotRegistry.slot_for_type("Recon")
		item.rarity = &"common"
		item.id = StringName("starter_recon_%d_%d" % [item_level, rng.randi()])
		item.glyph_color = RARITY_COLOR.get(&"common", Color.WHITE)
		item.stat_modifiers = {}
		_assign_optics_variant(item, variant, rng)
		item.name_key = _build_name("Recon", item.sub_type, [] as Array[String])
		out.append(item)
	return out

func _build_name(main_type: String, sub_type: String, affix_labels: Array[String]) -> String:
	# Sub-type (e.g. "Flashlight" for Optics) is more descriptive than the
	# bucket name when set, so prefer it as the noun in the rolled name.
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
