extends Node

signal equipment_changed(slot: StringName)
signal inventory_changed(index: int)
signal capacity_changed
signal items_overflowed(overflow: Array[Item])

# Prototype: full visibility — every test item is shown without needing a backpack.
const BASE_INVENTORY_SIZE := 40
const MAX_INVENTORY_SIZE := 40
const MAX_UTILITY_SLOTS := 4

# Tier-3 starter kit: one single-stat item per specialized class. Equip the
# matching item alone (no other stat-bearing gear) to push that class's primary
# stat to >= 40% of the budget, hitting AttributeState.TIERS_OWN tier 3.
const T3_STAT_PCT: int = 40

# Slot per class for the starter T3 items. Picked so all six can sit in the
# inventory simultaneously without colliding with the auto-equipped weapon.
const STARTER_KIT_SLOTS: Dictionary = {
	&"count":   &"head",
	&"survivalist": &"chest",
	&"enculted":    &"gloves",
	&"forged":      &"boots",
	&"automaton":   &"belt",
	&"polymath":    &"offhand",
}

# Slot-kind → ItemRoller main_type label, used to pick the right TYPE_GLYPH for
# starter kit items. The two armor slots embed "Armor" in the label; everything
# else just title-cases the slot name.
const STARTER_SLOT_MAIN_TYPE: Dictionary = {
	&"head":    "Head Armor",
	&"chest":   "Chest Armor",
	&"gloves":  "Gloves",
	&"boots":   "Boots",
	&"belt":    "Belt",
	&"offhand": "Offhand",
}

var equipment: Dictionary = {}
var inventory: Array[Item] = []

func _ready() -> void:
	inventory.resize(MAX_INVENTORY_SIZE)
	var i := 0
	for spec_id: StringName in AttributeState.CLASS_DEFINITIONS:
		inventory[i] = _make_class_tier3_item(spec_id)
		i += 1
	equipment[&"weapon"] = _make_starter_weapon()
	equipment[&"offhand"] = _make_starter_offhand()

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
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return ItemRoller.roll("1H Weapon", 1, &"common", rng)

func _make_starter_offhand() -> Item:
	var item := Item.new()
	item.id = &"starter_offhand"
	item.kind = &"offhand"
	item.main_type = "Offhand"
	item.glyph = ItemRoller.TYPE_GLYPH.get("Offhand", "?")
	item.glyph_color = ItemRoller.RARITY_COLOR.get(&"common", Color.WHITE)
	item.rarity = &"common"
	item.name_key = "Starter Offhand"
	item.fire_skill = preload("res://resources/skills/aoe_burst.tres")
	return item

func _make_class_tier3_item(spec_id: StringName) -> Item:
	var stat: StringName = AttributeState.CLASS_DEFINITIONS[spec_id][&"stat"]
	var slot: StringName = STARTER_KIT_SLOTS.get(spec_id, &"head")
	var short: String = AttributeState.STAT_SHORT.get(stat, "?")
	var spec_label := String(spec_id).capitalize()
	var item := Item.new()
	item.id = StringName("starter_t3_%s" % spec_id)
	item.kind = slot
	item.main_type = STARTER_SLOT_MAIN_TYPE.get(slot, String(slot).capitalize())
	item.glyph = ItemRoller.TYPE_GLYPH.get(item.main_type, AttributeState.TIER_ROMAN[2])
	item.glyph_color = AttributeState.STAT_COLORS.get(stat, Color.WHITE)
	item.rarity = &"unique"
	item.name_key = "%s T3 (%s %d%%)" % [spec_label, short, T3_STAT_PCT]
	item.stat_modifiers = {stat: T3_STAT_PCT}
	return item
