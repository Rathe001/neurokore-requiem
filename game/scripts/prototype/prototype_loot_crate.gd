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
## When true, the crate spits out a starter weapon kit instead of the
## default item generation: 50/50 chance of (one common 2H weapon) vs
## (one common 1H weapon + one common offhand), plus a head armor with
## a light mod so the player can navigate dark zones. Set by
## LootCrateDoorPuzzle on the spawn-room chest.
@export var starter_weapon_kit: bool = false
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
		# Head armor with a light mod so the player can use F to navigate.
		items.append(ItemRoller.roll("Head Armor", ilvl, &"common", rng))
		# One of each offhand archetype for playtest — remove once
		# active-offhand items roll naturally through ItemRoller.
		items.append(_make_starter_shield_generator())
		items.append(_make_starter_active_shield())
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


# Hand-built Shield Generator offhand for playtest. Equip in the
# offhand slot; RMB activates a 25% damage-reduction buff with a
# 25-damage absorption pool (level-1 baseline). Remove this helper
# once active-offhand items roll naturally through ItemRoller.
func _make_starter_shield_generator() -> Item:
	var item := Item.new()
	item.id = &"starter_shield_generator"
	item.kind = &"offhand"
	item.main_type = "Offhand"
	item.sub_type = "Amplification Shield"
	item.glyph = SlotRegistry.glyph_for_type("Offhand")
	item.glyph_color = Color(0.85, 0.92, 1.0, 1.0)
	item.rarity = &"unique"
	item.name_key = "Shield Generator"
	item.fire_skill = load("res://resources/skills/shield_generator.tres") as Skill
	return item


# Hand-built Active Shield offhand for playtest. Hold RMB to block
# 100% of incoming damage up to a 50-damage pool. Releases without
# cooldown; pool only refreshes after a break (post-cooldown). Same
# remove-once-rolling caveat as the Shield Generator.
func _make_starter_active_shield() -> Item:
	var item := Item.new()
	item.id = &"starter_active_shield"
	item.kind = &"offhand"
	item.main_type = "Offhand"
	item.sub_type = "Active Shield"
	item.glyph = SlotRegistry.glyph_for_type("Offhand")
	item.glyph_color = Color(0.85, 0.95, 0.85, 1.0)
	item.rarity = &"unique"
	item.name_key = "Active Shield"
	item.fire_skill = load("res://resources/skills/active_shield.tres") as Skill
	return item
