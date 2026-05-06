extends Node

signal equipment_changed(slot: StringName)
signal inventory_changed(index: int)
signal capacity_changed
signal items_overflowed(overflow: Array[Item])

# Bag economy: player starts with 8 slots. The equipped backpack contributes
# its `stat_modifiers[&"inventory_bonus"]` (rolled at 8 by ItemRoller, plus
# any affix rolls that touch the same key). MAX is the hard ceiling for the
# combined sum.
const BASE_INVENTORY_SIZE := 8
const MAX_INVENTORY_SIZE := 40

var equipment: Dictionary = {}
var inventory: Array[Item] = []

func _ready() -> void:
	# Backing array is sized to the hard ceiling so capacity growth from gear
	# never triggers a resize / index reshuffle — `get_inventory_capacity()`
	# decides how many slots are *visible* to the UI.
	inventory.resize(MAX_INVENTORY_SIZE)
	# Player starts with NO equipment and an empty inventory. Basic gear is
	# rolled by the spawn-room starter chest (see prototype_loot_crate.gd
	# starter_weapon_kit). Removed 2026-05-03 — the prior auto-equipped
	# weapon + offhand and 6 T3 test items pre-loaded the player and let
	# them skip the chest entirely.
	# When the Forged Amalgamation perk gains/loses tiers, the extra weapon
	# slot count changes — evict items from now-locked slots so a player who
	# respecs out of the perk doesn't keep silently-equipped weapons.
	PerkState.perks_changed.connect(reconcile_extra_weapon_slots)

## Clear all equipment and inventory. Called before creating a new character
## so no items from a previous session leak through.
func reset() -> void:
	var slots := equipment.keys()
	equipment.clear()
	inventory.fill(null)
	for slot in slots:
		equipment_changed.emit(slot)
	capacity_changed.emit()

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
	var old_inv_cap := get_inventory_capacity() if is_backpack else 0

	# Extra weapon slots reject 2H weapons (each extra arm wields a 1H per
	# the Forged Amalgamation design). Silently no-op rather than swap, so
	# the calling UI doesn't accidentally consume the drag.
	if item != null and item.two_handed and SlotRegistry.is_extra_weapon_slot(slot):
		return
	# Extra weapon slots also need the perk to be unlocked. If a slot is
	# locked, refuse to equip there.
	if item != null and SlotRegistry.is_extra_weapon_slot(slot) and not is_extra_weapon_slot_unlocked(slot):
		return
	# Offhand is mutually exclusive with a 2H weapon. ItemSlot.can_accept_item
	# blocks the drag-into-offhand path; this guards programmatic + quick-equip
	# callers so the rule holds everywhere.
	if slot == &"offhand" and item != null and is_two_handed_equipped():
		return

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
	var bonus := 0 if pack == null else pack.get_modifier(&"inventory_bonus")
	return min(BASE_INVENTORY_SIZE + bonus, MAX_INVENTORY_SIZE)



## How many extra 1H weapon slots the player currently has unlocked, sourced
## from the Forged Amalgamation perk's `extra_weapon_slots` aggregate.
## Clamped to the registered EXTRA_WEAPON_SLOTS array length so a perk can
## never grant more arms than the engine knows how to render.
func get_extra_weapon_slot_count() -> int:
	var raw := int(round(Effects.get_aggregate(&"extra_weapon_slots")))
	return clampi(raw, 0, SlotRegistry.EXTRA_WEAPON_SLOTS.size())


## True when the perk has unlocked enough extra arms to use the slot. The
## extras unlock IN ORDER — weapon_2 with 1 extra, weapon_3 with 2, etc.
func is_extra_weapon_slot_unlocked(slot: StringName) -> bool:
	var idx := SlotRegistry.EXTRA_WEAPON_SLOTS.find(slot)
	if idx < 0:
		return true  # not an extra slot
	return idx < get_extra_weapon_slot_count()


## Return every currently-equipped weapon slot, in fire-order: main first,
## then extras up to the perk-unlocked count. Used by the LMB combat path
## to fan-out the input across all the player's weapons.
func get_active_weapon_slots() -> Array[StringName]:
	var out: Array[StringName] = [&"weapon"]
	var extras := get_extra_weapon_slot_count()
	for i in extras:
		out.append(SlotRegistry.EXTRA_WEAPON_SLOTS[i])
	return out


## Empty the extra weapon slots that the player no longer has unlocked
## (e.g. perk tier dropped due to gear swap). Sends each evicted item to
## the inventory or the overflow signal.
func reconcile_extra_weapon_slots() -> void:
	var unlocked_count := get_extra_weapon_slot_count()
	var overflow: Array[Item] = []
	for i in SlotRegistry.EXTRA_WEAPON_SLOTS.size():
		if i < unlocked_count:
			continue
		var slot: StringName = SlotRegistry.EXTRA_WEAPON_SLOTS[i]
		var displaced: Item = equipment.get(slot, null)
		if displaced == null:
			continue
		equipment.erase(slot)
		equipment_changed.emit(slot)
		if not add_to_inventory(displaced):
			overflow.append(displaced)
	if not overflow.is_empty():
		items_overflowed.emit(overflow)

