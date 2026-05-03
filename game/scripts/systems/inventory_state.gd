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
const MAX_UTILITY_SLOTS := 4

# Tier-3 starter kit: one single-stat item per specialised class. Equip the
# matching item alone to push that class's primary stat past TIERS_OWN[2]
# (99% under the simplified breakpoints) → T3 unlocked. The constant is a
# raw stat amount, NOT a percentage — set deliberately huge so the starter
# weapon's small random stat rolls don't dilute the primary below 99%
# (1000 / 1005 = 99.5% even if the starter weapon adds 5 stat points).
# Equipping more than one starter T3 item simultaneously will push BOTH
# primaries to ~50% by design — the new threshold model says "all-in or
# nothing," so testing one class at a time is the intended workflow.
const T3_STAT_PCT: int = 1000

# Slot per spec class for the starter kit items. Picked so all six can sit
# in the inventory simultaneously without colliding with each other in the
# same equipment slot.
const STARTER_KIT_SLOTS: Dictionary = {
	&"count":       &"head",
	&"survivalist": &"chest",
	&"enculted":    &"gloves",
	&"forged":      &"boots",
	&"automaton":   &"belt",
	&"polymath":    &"offhand",
}

# Slot-kind → ItemRoller main_type label, used to pick the right glyph for
# starter-kit items via SlotRegistry.
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
	# Backing array is sized to the hard ceiling so capacity growth from gear
	# never triggers a resize / index reshuffle — `get_inventory_capacity()`
	# decides how many slots are *visible* to the UI.
	inventory.resize(MAX_INVENTORY_SIZE)
	equipment[&"weapon"] = _make_starter_weapon()
	equipment[&"offhand"] = _make_starter_offhand()
	# Six T3 starter items — one per spec class — populate the first slots
	# so playtesting any class can immediately reach T3 (or T2 for origin)
	# by equipping the matching item.
	var i := 0
	for spec_id: StringName in AttributeState.CLASS_DEFINITIONS:
		inventory[i] = _make_class_tier3_item(spec_id)
		i += 1
	# When the Forged Amalgamation perk gains/loses tiers, the extra weapon
	# slot count changes — evict items from now-locked slots so a player who
	# respecs out of the perk doesn't keep silently-equipped weapons.
	PerkState.perks_changed.connect(reconcile_extra_weapon_slots)

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

	# Extra weapon slots reject 2H weapons (each extra arm wields a 1H per
	# the Forged Amalgamation design). Silently no-op rather than swap, so
	# the calling UI doesn't accidentally consume the drag.
	if item != null and item.two_handed and SlotRegistry.is_extra_weapon_slot(slot):
		return
	# Extra weapon slots also need the perk to be unlocked. If a slot is
	# locked, refuse to equip there.
	if item != null and SlotRegistry.is_extra_weapon_slot(slot) and not is_extra_weapon_slot_unlocked(slot):
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
	var bonus := 0 if pack == null else pack.get_modifier(&"inventory_bonus")
	return min(BASE_INVENTORY_SIZE + bonus, MAX_INVENTORY_SIZE)

func get_utility_capacity() -> int:
	var belt: Item = equipment.get(&"belt", null)
	if belt == null:
		return 0
	return clamp(belt.utility_slots, 0, MAX_UTILITY_SLOTS)


## How many extra 1H weapon slots the player currently has unlocked, sourced
## from the Forged Amalgamation perk's `extra_weapon_slots` aggregate.
## Clamped to the registered EXTRA_WEAPON_SLOTS array length so a perk can
## never grant more arms than the engine knows how to render.
func get_extra_weapon_slot_count() -> int:
	var raw := int(round(PerkState.get_aggregate(&"extra_weapon_slots")))
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
	item.glyph = SlotRegistry.glyph_for_type("Offhand")
	item.glyph_color = ItemRoller.RARITY_COLOR.get(&"common", Color.WHITE)
	item.rarity = &"common"
	item.name_key = "Starter Offhand"
	item.fire_skill = preload("res://resources/skills/aoe_burst.tres")
	return item


## Build one max-tier test item per spec class. Equipping the matching item
## as the dominant stat source pushes that class's primary stat past the
## TIERS_OWN[2] (99%) threshold → T3 unlocked. For origin classes the same
## item lifts the corresponding kore stat past TIERS_KORE_ORIGIN[1] (66%)
## → T2. Reduces playtest setup from "kill enemies until you roll the right
## affixes" to "drag this onto the matching slot."
func _make_class_tier3_item(spec_id: StringName) -> Item:
	var stat: StringName = AttributeState.CLASS_DEFINITIONS[spec_id][&"stat"]
	var slot: StringName = STARTER_KIT_SLOTS.get(spec_id, &"head")
	var main_type: String = STARTER_SLOT_MAIN_TYPE.get(slot, String(slot).capitalize())
	var short: String = AttributeState.STAT_SHORT.get(stat, "?")
	var spec_label: String = String(spec_id).capitalize()
	var item := Item.new()
	item.id = StringName("starter_t3_%s" % spec_id)
	item.kind = slot
	item.main_type = main_type
	item.glyph = SlotRegistry.glyph_for_type(main_type)
	item.glyph_color = AttributeState.STAT_COLORS.get(stat, Color.WHITE)
	item.rarity = &"unique"
	item.name_key = "%s T3 (%s %d%%)" % [spec_label, short, T3_STAT_PCT]
	item.stat_modifiers = {stat: T3_STAT_PCT}
	return item
