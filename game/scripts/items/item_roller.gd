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

const MAIN_TYPES: Array[String] = [
	"1H Weapon", "2H Weapon", "Offhand",
	"Head Armor", "Chest Armor", "Gloves", "Boots",
	"Belt", "Mainboard", "Backpack", "Optics",
]

const TYPE_TO_SLOT: Dictionary = {
	"1H Weapon":   &"weapon",
	"2H Weapon":   &"weapon",
	"Offhand":     &"offhand",
	"Head Armor":  &"head",
	"Chest Armor": &"chest",
	"Gloves":      &"gloves",
	"Boots":       &"boots",
	"Belt":        &"belt",
	"Mainboard":   &"mainboard",
	"Backpack":    &"backpack",
	"Optics":      &"optics",
}

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
	&"common": Color(0.75, 0.75, 0.75),
	&"magic":  Color(0.30, 0.55, 1.00),
	&"rare":   Color(1.00, 0.85, 0.30),
	&"unique": Color(0.85, 0.45, 1.00),
}

const TYPE_GLYPH: Dictionary = {
	"1H Weapon":   "†",
	"2H Weapon":   "‡",
	"Offhand":     "◊",
	"Head Armor":  "▲",
	"Chest Armor": "▣",
	"Gloves":      "Ψ",
	"Boots":       "⌐",
	"Belt":        "═",
	"Mainboard":   "⌬",
	"Backpack":    "▤",
	"Optics":      "✦",
}

# Registry of weapon bases keyed by main_type. The roller picks one at random
# when generating a weapon, then rolls each stat range into the Item instance.
const WEAPON_BASE_PATHS: Dictionary = {
	"1H Weapon": [
		"res://resources/items/weapon_bases/melee_1h.tres",
	],
	"2H Weapon": [
		"res://resources/items/weapon_bases/melee_2h.tres",
	],
}

# Optics variants. One of these is rolled when main_type == "Optics" so each
# light item carries the right type, range, energy, and color to actually work
# when equipped. Probability is uniform — friends-mode demo wants visibility.
const OPTICS_VARIANTS: Array[Dictionary] = [
	{
		"name": "Flashlight",
		"glyph": "✸",
		"light_type": Item.LightType.DIRECTIONAL,
		"range": 12.0,
		"energy_range": Vector2(2.0, 3.0),
		"color": Color(1.0, 0.95, 0.85),
	},
	{
		"name": "Lantern",
		"glyph": "◉",
		"light_type": Item.LightType.RADIANT,
		"range": 6.0,
		"energy_range": Vector2(1.5, 2.2),
		"color": Color(1.0, 0.85, 0.6),
	},
	{
		"name": "Phased Surveillance Radar",
		"glyph": "◎",
		"light_type": Item.LightType.SCANNER,
		"range": 12.0,
		"energy_range": Vector2(0.0, 0.0),
		"color": Color(0.5, 1.0, 1.0),
	},
	{
		"name": "UV Light",
		"glyph": "❉",
		"light_type": Item.LightType.UV,
		"range": 5.0,
		"energy_range": Vector2(1.2, 1.8),
		"color": Color(0.6, 0.4, 1.0),
	},
]

func roll(main_type: String, item_level: int, rarity: StringName, rng: RandomNumberGenerator) -> Item:
	var item := Item.new()
	item.main_type = main_type
	item.kind = TYPE_TO_SLOT.get(main_type, &"")
	item.rarity = rarity
	item.id = StringName("rolled_%d_%d" % [item_level, rng.randi()])
	item.glyph = TYPE_GLYPH.get(main_type, "?")
	item.glyph_color = RARITY_COLOR.get(rarity, Color.WHITE)
	item.stat_modifiers = {}

	if main_type == "2H Weapon":
		item.two_handed = true

	_apply_weapon_base(item, main_type, rng)
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
	for s: StringName in _pick_class_stats(slot_count, rng):
		var value := _class_stat_value(item_level, rng)
		item.stat_modifiers[s] = int(item.stat_modifiers.get(s, 0)) + value

	item.name_key = _build_name(main_type, item.sub_type, affix_labels)
	return item

func roll_random(item_level: int, rng: RandomNumberGenerator) -> Item:
	var rarity := _roll_rarity(rng)
	var main_type: String = MAIN_TYPES[rng.randi_range(0, MAIN_TYPES.size() - 1)]
	return roll(main_type, item_level, rarity, rng)

func _class_slot_count(item_level: int, rng: RandomNumberGenerator) -> int:
	if item_level <= ILVL_EARLY_MAX:
		return 1
	if item_level <= ILVL_MID_MAX:
		return rng.randi_range(1, 2)
	return rng.randi_range(1, 3)

func _pick_class_stats(count: int, _rng: RandomNumberGenerator) -> Array[StringName]:
	var pool: Array[StringName] = []
	for s: StringName in AttributeState.ROLLABLE_STATS:
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
	item.weapon_base_id = base.id
	item.two_handed = base.two_handed
	item.fire_skill = base.fire_skill
	item.alt_fire_skill = base.alt_fire_skill
	if item.glyph == TYPE_GLYPH.get(main_type, "?") and base.glyph != "":
		item.glyph = base.glyph
	# Damage roll: ensure max >= min so combat damage rolls aren't inverted.
	var dmin := int(round(rng.randf_range(base.damage_min_range.x, base.damage_min_range.y)))
	var dmax := int(round(rng.randf_range(base.damage_max_range.x, base.damage_max_range.y)))
	item.damage_min = mini(dmin, dmax)
	item.damage_max = maxi(dmin, dmax)
	item.attack_speed = rng.randf_range(base.attack_speed_range.x, base.attack_speed_range.y)
	item.crit_chance = rng.randf_range(base.crit_chance_range.x, base.crit_chance_range.y)
	item.accuracy = rng.randf_range(base.accuracy_range.x, base.accuracy_range.y)

func _apply_optics_variant(item: Item, main_type: String, rng: RandomNumberGenerator) -> void:
	if main_type != "Optics":
		return
	var variant: Dictionary = OPTICS_VARIANTS[rng.randi_range(0, OPTICS_VARIANTS.size() - 1)]
	item.light_type = variant["light_type"]
	item.light_range = variant["range"]
	var energy_range: Vector2 = variant["energy_range"]
	item.light_energy = rng.randf_range(energy_range.x, energy_range.y)
	item.light_color = variant["color"]
	item.sub_type = variant["name"]
	item.glyph = variant["glyph"]

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
