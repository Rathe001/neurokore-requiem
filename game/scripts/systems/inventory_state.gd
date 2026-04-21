extends Node

signal equipment_changed(slot: StringName)
signal inventory_changed(index: int)
signal capacity_changed
signal items_overflowed(overflow: Array[Item])

const BASE_INVENTORY_SIZE := 10
const MAX_INVENTORY_SIZE := 40
const MAX_UTILITY_SLOTS := 4

const STARTER_FLASHLIGHT: Item = preload("res://resources/items/common_flashlight.tres")
const STARTER_BACKPACK: Item = preload("res://resources/items/common_backpack.tres")
const STARTER_BELT: Item = preload("res://resources/items/common_belt.tres")
const SEED_HELMET: Item = preload("res://resources/items/common_helmet.tres")
const SEED_CHEST: Item = preload("res://resources/items/common_chest.tres")
const SEED_WEAPON: Item = preload("res://resources/items/common_weapon.tres")
const SEED_OFFHAND: Item = preload("res://resources/items/common_offhand.tres")
const SEED_GLOVES: Item = preload("res://resources/items/common_gloves.tres")
const SEED_BOOTS: Item = preload("res://resources/items/common_boots.tres")
const SEED_UTILITY: Item = preload("res://resources/items/common_utility.tres")

var equipment: Dictionary = {}
var inventory: Array[Item] = []

func _ready() -> void:
	inventory.resize(MAX_INVENTORY_SIZE)
	inventory[0] = STARTER_BACKPACK
	inventory[1] = STARTER_BELT
	inventory[2] = SEED_HELMET
	inventory[3] = SEED_CHEST
	inventory[4] = SEED_WEAPON
	inventory[5] = SEED_OFFHAND
	inventory[6] = SEED_GLOVES
	inventory[7] = SEED_BOOTS
	inventory[8] = SEED_UTILITY
	inventory[9] = STARTER_FLASHLIGHT

func get_equipped(slot: StringName) -> Item:
	return equipment.get(slot, null)

func get_inventory_item(index: int) -> Item:
	if index < 0 or index >= inventory.size():
		return null
	return inventory[index]

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
