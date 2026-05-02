extends Node

signal equipment_changed(slot: StringName)
signal inventory_changed(index: int)
signal capacity_changed
signal items_overflowed(overflow: Array[Item])

# Bag economy: player starts with 8 slots; equipping a backpack adds another
# 8 (set on the rolled Item's inventory_bonus by ItemRoller). MAX is the hard
# ceiling future drop affixes (currently inventory_bonus on backpacks only)
# can reach with affix rolls layered on top.
const BASE_INVENTORY_SIZE := 8
const MAX_INVENTORY_SIZE := 40
const MAX_UTILITY_SLOTS := 4

var equipment: Dictionary = {}
var inventory: Array[Item] = []

func _ready() -> void:
	# Backing array is sized to the hard ceiling so capacity growth from gear
	# never triggers a resize / index reshuffle — `get_inventory_capacity()`
	# decides how many slots are *visible* to the UI.
	inventory.resize(MAX_INVENTORY_SIZE)
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
