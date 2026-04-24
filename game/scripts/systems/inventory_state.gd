extends Node

signal equipment_changed(slot: StringName)
signal inventory_changed(index: int)
signal capacity_changed
signal items_overflowed(overflow: Array[Item])

const BASE_INVENTORY_SIZE := 10
const MAX_INVENTORY_SIZE := 40
const MAX_UTILITY_SLOTS := 4

const STARTER_FLASHLIGHT: Item = preload("res://resources/items/common_flashlight.tres")
const STARTER_LANTERN: Item = preload("res://resources/items/common_lantern.tres")
const STARTER_SCANNER: Item = preload("res://resources/items/common_scanner.tres")
const STARTER_UV_LIGHT: Item = preload("res://resources/items/common_uv_light.tres")
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
	inventory[6] = STARTER_FLASHLIGHT
	inventory[7] = STARTER_LANTERN
	inventory[8] = STARTER_SCANNER
	inventory[9] = STARTER_UV_LIGHT
	# Stat test items — equip these to unlock talent tree tiers.
	inventory[10] = _make_stat_item(&"stat_vest_ort",   &"chest",    "C", Color(0.95, 0.92, 0.8),  {&"ort": 30})
	inventory[11] = _make_stat_item(&"stat_helmet_ing", &"head",     "H", Color(0.7,  0.85, 0.35), {&"ing": 25})
	inventory[12] = _make_stat_item(&"stat_gloves_dev", &"gloves",   "G", Color(0.9,  0.25, 0.2),  {&"dev": 35})
	inventory[13] = _make_stat_item(&"stat_boots_opt",  &"boots",    "B", Color(0.55, 0.78, 0.85), {&"opt": 20})
	inventory[14] = _make_stat_item(&"stat_optic_cla",  &"optics",   "O", Color(0.95, 0.9,  0.3),  {&"cla": 15})
	inventory[15] = _make_stat_item(&"stat_pack_amb",   &"backpack", "K", Color(0.78, 0.35, 0.85), {&"amb": 25})

func _make_stat_item(id: StringName, kind: StringName, glyph: String, color: Color, stats: Dictionary) -> Item:
	var item := Item.new()
	item.id = id
	item.kind = kind
	item.main_type = String(kind).capitalize()
	item.glyph = glyph
	item.glyph_color = color
	item.rarity = &"uncommon"
	item.stat_modifiers = stats
	var stat_parts: Array[String] = []
	for k in stats:
		stat_parts.append("+%d %s" % [stats[k], (k as String).to_upper()])
	item.name_key = " / ".join(stat_parts)
	return item

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
