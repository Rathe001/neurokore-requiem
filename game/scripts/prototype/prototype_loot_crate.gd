class_name PrototypeLootCrate
extends HoverableInteractable

const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_item_pickup.tscn")

const COLOR_CLOSED := Color(0.9, 0.75, 0.3, 1.0)
const COLOR_OPENED := Color(0.35, 0.35, 0.35, 1.0)

## Items to spawn on open. When empty, rolls random items instead.
@export var fixed_items: Array[Item] = []
## Number of random items to spawn when fixed_items is empty.
@export var random_item_count: int = 3
## Weapon base resource paths to roll as test items. Overrides random_item_count.
@export var test_weapon_base_paths: Array[String] = []
## When true, spawns one of each Optics variant (Flashlight, Lantern, Scanner,
## UV) in addition to whatever else the crate would drop. For the starter
## chest so the player can sample every light type up front.
@export var include_all_optics: bool = false
## When true, the crate spits out a starter weapon kit instead of the
## default item generation: 50/50 chance of (one common 2H weapon) vs
## (one common 1H weapon + one common offhand). Set by LootCrateDoorPuzzle
## on the spawn-room chest so the player gets a guaranteed playable
## weapon set on level start. ALSO drops one max-tier stat-stick test
## item per spec class (temporary playtest convenience — equipping the
## matching item alone pushes that class's primary stat past T3).
@export var starter_weapon_kit: bool = false

# Stat-stick magnitude for the T3 test items. Set huge so the starter
# weapon's small random rolls don't dilute the primary below 99% (the
# T3 threshold) — see project memory note `project_kore_terminology`
# / the prior _make_class_tier3_item helper that lived in
# inventory_state.gd before being removed when the player started empty.
const _STARTER_T3_STAT_AMOUNT: int = 1000
# Slot per spec class for the T3 stat-stick — picked so all six items
# can sit in inventory without colliding on equip.
const _STARTER_T3_KIT_SLOTS: Dictionary = {
	&"count":       &"head",
	&"survivalist": &"chest",
	&"enculted":    &"gloves",
	&"forged":      &"boots",
	&"automaton":   &"belt",
	&"polymath":    &"offhand",
}
const _STARTER_T3_SLOT_MAIN_TYPE: Dictionary = {
	&"head":    "Head Armor",
	&"chest":   "Chest Armor",
	&"gloves":  "Gloves",
	&"boots":   "Boots",
	&"belt":    "Belt",
	&"offhand": "Offhand",
}
## Optional door this crate unlocks on first interact — mirrors the
## PrototypeSwitch.target_door pattern. Set by LootCrateDoorPuzzle, not
## hand-authored. Empty path = no door wiring (regular loot drop).
@export var target_door: NodePath

@onready var mesh: MeshInstance3D = $Mesh
@onready var lid: MeshInstance3D = $Lid

var _opened: bool = false
var _mat: StandardMaterial3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 2.0
	_apply_color(COLOR_CLOSED)
	mesh.material_override = _mat
	super._ready()

func _get_outline_source() -> MeshInstance3D:
	return mesh

func _get_tooltip_text() -> String:
	return "Loot Crate" if not _opened else "Empty Crate"

func reset_state() -> void:
	_opened = false
	_apply_color(COLOR_CLOSED)
	if lid != null:
		lid.visible = true
	input_ray_pickable = true
	SpatialGrid.register(self, &"interactables")

func interact(_user: Node) -> void:
	if _opened:
		return
	_opened = true
	_apply_color(COLOR_OPENED)
	if lid != null:
		var tween := create_tween()
		tween.tween_property(lid, "rotation_degrees:x", -110.0, 0.3).set_ease(Tween.EASE_OUT)

	var items: Array[Item] = []
	if starter_weapon_kit:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var ilvl := maxi(1, PlayerState.level)
		# 50/50: one 2H, OR one 1H + one offhand. Both branches roll at
		# common rarity so the player's first kit is functional but
		# unspectacular — variety / power comes from later drops.
		if rng.randf() < 0.5:
			items.append(ItemRoller.roll("2H Weapon", ilvl, &"common", rng))
		else:
			items.append(ItemRoller.roll("1H Weapon", ilvl, &"common", rng))
			items.append(ItemRoller.roll("Offhand", ilvl, &"common", rng))
		# Playtest convenience — six max-tier stat-stick items (one per
		# spec class). Equipping the matching item alone pushes that
		# class's primary past TIERS_OWN[2] (99%) → T3 unlocked. Removed
		# from the starting inventory when the player started empty;
		# re-added here so the player still has a fast path to
		# perk-tier playtesting without skipping the chest.
		for spec_id: StringName in AttributeState.CLASS_DEFINITIONS:
			items.append(_make_starter_t3_item(spec_id))
	elif fixed_items.size() > 0:
		items.assign(fixed_items)
	elif test_weapon_base_paths.size() > 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var ilvl := maxi(1, PlayerState.level)
		for path in test_weapon_base_paths:
			var base := load(path) as WeaponBase
			if base == null:
				push_warning("[LootCrate] missing WeaponBase: %s" % path)
				continue
			items.append(ItemRoller.roll_from_base(base, ilvl, &"magic", rng))
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var ilvl := maxi(1, PlayerState.level)
		for _i in random_item_count:
			items.append(ItemRoller.roll_random(ilvl, rng))

	if include_all_optics:
		var optics_rng := RandomNumberGenerator.new()
		optics_rng.randomize()
		var ilvl_optics := maxi(1, PlayerState.level)
		items.append_array(ItemRoller.roll_one_per_optics_variant(ilvl_optics, optics_rng))

	var parent := get_parent()
	if parent == null:
		return
	for i in items.size():
		var pickup := ITEM_PICKUP_SCENE.instantiate()
		pickup.configure(items[i])
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(0.0, 1.5, 0.0)

	# Trigger any door wired to this crate (LootCrateDoorPuzzle uses this
	# to gate level progression on a chest open). Mirrors the switch
	# pattern — single unlock() call, door figures out the rest.
	if target_door != NodePath():
		var door := get_node_or_null(target_door) as PrototypeDoor
		if door != null:
			door.unlock()

	# Become inert after opening — drop out of mouse picking, the spatial
	# grid (no more proximity-interact triggers), and any active hover/
	# tooltip state. Without input_ray_pickable=false the cursor keeps
	# highlighting an empty crate, which the player reads as "still has
	# something" until they've clicked enough to confirm.
	input_ray_pickable = false
	SpatialGrid.unregister(self)
	if _outline != null:
		_outline.visible = false
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func _apply_color(c: Color) -> void:
	_mat.albedo_color = c
	_mat.emission = c


# Build one max-tier stat-stick item for the given spec class. Equipping
# it alone pushes that class's primary stat past TIERS_OWN[2] (99% under
# the simplified breakpoints) → T3 unlocked. For origin classes, the
# matching team-stat item lifts the corresponding kore stat past T2.
# Mirror of the helper that lived in inventory_state.gd before the
# player started empty.
func _make_starter_t3_item(spec_id: StringName) -> Item:
	var stat: StringName = AttributeState.CLASS_DEFINITIONS[spec_id][&"stat"]
	var slot: StringName = _STARTER_T3_KIT_SLOTS.get(spec_id, &"head")
	var main_type: String = _STARTER_T3_SLOT_MAIN_TYPE.get(slot, String(slot).capitalize())
	var short: String = AttributeState.STAT_SHORT.get(stat, "?")
	var spec_label: String = String(spec_id).capitalize()
	var item := Item.new()
	item.id = StringName("starter_t3_%s" % spec_id)
	item.kind = slot
	item.main_type = main_type
	item.glyph = SlotRegistry.glyph_for_type(main_type)
	item.glyph_color = AttributeState.STAT_COLORS.get(stat, Color.WHITE)
	item.rarity = &"unique"
	item.name_key = "%s T3 (%s %d%%)" % [spec_label, short, _STARTER_T3_STAT_AMOUNT]
	item.stat_modifiers = {stat: _STARTER_T3_STAT_AMOUNT}
	return item
