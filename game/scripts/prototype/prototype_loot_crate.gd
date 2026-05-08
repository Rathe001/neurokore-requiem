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
## (one common 1H weapon + one common offhand). Set by
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
		lid.rotation_degrees.x = 0.0
	input_ray_pickable = true
	SpatialGrid.register(self, &"interactables")

func interact(_user: Node) -> void:
	if _opened:
		return
	# MP client: request the host to open.
	if NetState.is_in_lobby() and NetState.is_client():
		_request_open.rpc_id(1)
		return
	# SP or MP host: open directly.
	_do_open()


func _do_open() -> void:
	_opened = true
	_open_visual()
	if NetState.is_in_lobby():
		_client_open_visual.rpc()

	var items: Array[Item] = _roll_items()
	var drop_pos := global_position + Vector3(0.0, 1.5, 0.0)
	var container := _find_pickups_container()

	# MP: per-player instanced drops.
	if NetState.is_in_lobby() and container != null:
		for peer_id_v in NetState.lobby_members.keys():
			var peer_id: int = int(peer_id_v)
			# Re-roll per player so each gets a unique item set.
			var peer_items := _roll_items()
			for item in peer_items:
				container.spawn_item(item, drop_pos, StringName(str(peer_id)))
	elif container != null:
		# SP with PickupsContainer.
		for item in items:
			container.spawn_item(item, drop_pos)
	else:
		# Fallback: direct instantiate.
		var parent := get_parent()
		if parent == null:
			return
		for item in items:
			var pickup := ITEM_PICKUP_SCENE.instantiate()
			pickup.configure(item)
			parent.add_child(pickup)
			pickup.global_position = drop_pos

	if target_door != NodePath():
		var door := get_node_or_null(target_door) as PrototypeDoor
		if door != null:
			door.unlock()

	_become_inert()


func _roll_items() -> Array[Item]:
	var items: Array[Item] = []
	if starter_weapon_kit:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var starter_ilvl := 0
		if rng.randf() < 0.5:
			items.append(ItemRoller.roll("2H Weapon", starter_ilvl, &"common", rng))
		else:
			items.append(ItemRoller.roll("1H Weapon", starter_ilvl, &"common", rng))
			items.append(ItemRoller.roll("Offhand", starter_ilvl, &"common", rng))
	elif fixed_items.size() > 0:
		items.assign(fixed_items)
	elif test_weapon_base_paths.size() > 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var ilvl := maxi(1, 2 + PlayerState.zone_level_offset())
		for path in test_weapon_base_paths:
			var base := load(path) as WeaponBase
			if base == null:
				push_warning("[LootCrate] missing WeaponBase: %s" % path)
				continue
			items.append(ItemRoller.roll_from_base(base, ilvl, &"magic", rng))
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var ilvl := maxi(1, 2 + PlayerState.zone_level_offset())
		for _i in random_item_count:
			items.append(ItemRoller.roll_random(ilvl, rng))
	return items


func _open_visual() -> void:
	_apply_color(COLOR_OPENED)
	if lid != null:
		var tween := create_tween()
		tween.tween_property(lid, "rotation_degrees:x", -110.0, 0.3).set_ease(Tween.EASE_OUT)


func _become_inert() -> void:
	input_ray_pickable = false
	SpatialGrid.unregister(self)
	if _outline != null:
		_outline.visible = false
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")


@rpc("any_peer", "call_remote", "reliable")
func _request_open() -> void:
	if not multiplayer.is_server():
		return
	if _opened:
		return
	_do_open()


@rpc("authority", "call_remote", "reliable")
func _client_open_visual() -> void:
	if _opened:
		return
	_opened = true
	_open_visual()
	_become_inert()


func _find_pickups_container() -> PickupsContainer:
	var pc := get_tree().get_first_node_in_group(&"pickups_container")
	if pc is PickupsContainer:
		return pc as PickupsContainer
	return null


func _apply_color(c: Color) -> void:
	_mat.albedo_color = c
	_mat.emission = c
