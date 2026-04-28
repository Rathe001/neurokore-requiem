extends Node

signal equipment_changed(slot: StringName)
signal inventory_changed(index: int)
signal capacity_changed
signal items_overflowed(overflow: Array[Item])

# Prototype: full visibility — every test item is shown without needing a backpack.
const BASE_INVENTORY_SIZE := 40
const MAX_INVENTORY_SIZE := 40
const MAX_UTILITY_SLOTS := 4

# Test items follow the item-architecture model: each carries only its rolled
# class stats (no splash). Solo-equipping a tier-N single-stat item lands that
# stat exactly on its tier threshold (matches AttributeState.TIERS_OWN).
const TIER_PCTS: Array[int] = [12, 25, 40, 55, 72]

const TEST_SLOTS: Array[StringName] = [
	&"head", &"optics", &"backpack", &"weapon", &"chest",
	&"offhand", &"gloves", &"belt", &"boots",
]

const TIER_RARITIES: Array[StringName] = [&"common", &"magic", &"rare", &"unique", &"unique"]

# Mid-game showcase: each pair gets T2 on both stats (25% + 25%).
const DUAL_STAT_PAIRS: Array = [
	[&"dev", &"ort"],
	[&"opt", &"cla"],
	[&"ing", &"amb"],
	[&"dev", &"opt"],
	[&"ort", &"ing"],
	[&"amb", &"cla"],
]

# Late-game showcase: each trio gets T1 on all three (12% + 12% + 12%).
const TRIPLE_STAT_TRIOS: Array = [
	[&"dev", &"opt", &"cla"],
	[&"ort", &"ing", &"amb"],
	[&"ort", &"dev", &"opt"],
]

var equipment: Dictionary = {}
var inventory: Array[Item] = []

func _ready() -> void:
	inventory.resize(MAX_INVENTORY_SIZE)
	var idx := 0
	for stat: StringName in AttributeState.ROLLABLE_STATS:
		for tier_idx in 5:
			var slot := TEST_SLOTS[idx % TEST_SLOTS.size()]
			inventory[idx] = _make_test_item(stat, tier_idx + 1, slot)
			idx += 1
	for pair: Array in DUAL_STAT_PAIRS:
		var slot := TEST_SLOTS[idx % TEST_SLOTS.size()]
		inventory[idx] = _make_multi_stat_item(pair, 2, slot)
		idx += 1
	for trio: Array in TRIPLE_STAT_TRIOS:
		var slot := TEST_SLOTS[idx % TEST_SLOTS.size()]
		inventory[idx] = _make_multi_stat_item(trio, 1, slot)
		idx += 1
	equipment[&"weapon"] = _make_starter_weapon()

func get_equipped(slot: StringName) -> Item:
	return equipment.get(slot, null)

func get_inventory_item(index: int) -> Item:
	if index < 0 or index >= inventory.size():
		return null
	return inventory[index]

func is_two_handed_equipped() -> bool:
	var weapon: Item = equipment.get(&"weapon", null)
	return weapon != null and weapon.two_handed

func set_equipped(slot: StringName, item: Item) -> void:
	var is_backpack := slot == &"backpack"
	var is_belt := slot == &"belt"
	var old_inv_cap := get_inventory_capacity() if is_backpack else 0
	var old_util_cap := get_utility_capacity() if is_belt else 0

	if item == null:
		equipment.erase(slot)
	else:
		equipment[slot] = item
	equipment_changed.emit(slot)

	var overflow: Array[Item] = []

	# 2H weapon displaces offhand.
	if slot == &"weapon" and item != null and item.two_handed:
		var displaced: Item = equipment.get(&"offhand", null)
		if displaced != null:
			equipment.erase(&"offhand")
			equipment_changed.emit(&"offhand")
			if not add_to_inventory(displaced):
				overflow.append(displaced)

	if is_belt:
		var new_util_cap := get_utility_capacity()
		for i in range(new_util_cap + 1, old_util_cap + 1):
			var uid := StringName("utility_%d" % i)
			var displaced: Item = equipment.get(uid, null)
			if displaced != null:
				equipment.erase(uid)
				equipment_changed.emit(uid)
				if not add_to_inventory(displaced):
					overflow.append(displaced)
		capacity_changed.emit()

	if is_backpack:
		var new_inv_cap := get_inventory_capacity()
		for i in range(new_inv_cap, old_inv_cap):
			if inventory[i] != null:
				overflow.append(inventory[i])
				inventory[i] = null
				inventory_changed.emit(i)
		capacity_changed.emit()

	if not overflow.is_empty():
		items_overflowed.emit(overflow)

func add_to_inventory(item: Item) -> bool:
	var cap := get_inventory_capacity()
	for i in cap:
		if inventory[i] == null:
			inventory[i] = item
			inventory_changed.emit(i)
			return true
	return false

func set_inventory_item(index: int, item: Item) -> void:
	if index < 0 or index >= inventory.size():
		return
	inventory[index] = item
	inventory_changed.emit(index)

func get_inventory_capacity() -> int:
	var pack: Item = equipment.get(&"backpack", null)
	var bonus := 0
	if pack != null:
		bonus = pack.inventory_bonus
	return min(BASE_INVENTORY_SIZE + bonus, MAX_INVENTORY_SIZE)

func get_utility_capacity() -> int:
	var belt: Item = equipment.get(&"belt", null)
	if belt == null:
		return 0
	return clamp(belt.utility_slots, 0, MAX_UTILITY_SLOTS)

# ── Test items ────────────────────────────────────────────────────────────────

func _make_starter_weapon() -> Item:
	var item := Item.new()
	item.id = &"starter_weapon"
	item.kind = &"weapon"
	item.main_type = "Weapon"
	item.sub_type = "Starter"
	item.glyph = "/"
	item.glyph_color = Color(0.85, 0.90, 1.00)
	item.rarity = &"common"
	item.name_key = "Training Blade"
	item.two_handed = false
	item.fire_skill = load("res://resources/skills/basic_attack.tres") as Skill
	return item

func _make_test_item(stat: StringName, tier: int, slot: StringName) -> Item:
	var short: String = AttributeState.STAT_SHORT.get(stat, "?")
	var pct: int = TIER_PCTS[tier - 1]
	var item := Item.new()
	item.id = StringName("test_%s_t%d" % [stat, tier])
	item.kind = slot
	item.main_type = String(slot).capitalize()
	item.glyph = AttributeState.TIER_ROMAN[tier - 1]
	item.glyph_color = AttributeState.STAT_COLORS.get(stat, Color.WHITE)
	item.rarity = TIER_RARITIES[tier - 1]
	item.name_key = "%s T%d (%d%%)" % [short, tier, pct]
	item.stat_modifiers = {stat: pct}
	return item

func _make_multi_stat_item(stats: Array, tier: int, slot: StringName) -> Item:
	var pct: int = TIER_PCTS[tier - 1]
	var shorts: Array[String] = []
	var blended := Color(0.0, 0.0, 0.0, 0.0)
	for s: StringName in stats:
		shorts.append(AttributeState.STAT_SHORT.get(s, "?"))
		blended += AttributeState.STAT_COLORS.get(s, Color.WHITE)
	blended /= float(stats.size())
	var label := "+".join(shorts)

	var item := Item.new()
	item.id = StringName("test_multi_%s_t%d" % [label.to_lower(), tier])
	item.kind = slot
	item.main_type = String(slot).capitalize()
	item.glyph = AttributeState.TIER_ROMAN[tier - 1]
	item.glyph_color = blended
	item.rarity = TIER_RARITIES[tier - 1]
	item.name_key = "%s T%d (%d%% ea)" % [label, tier, pct]
	var mods: Dictionary = {}
	for s: StringName in stats:
		mods[s] = pct
	item.stat_modifiers = mods
	return item
