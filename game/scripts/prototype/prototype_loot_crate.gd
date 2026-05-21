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

# Visual is a .glb instance; the lid (`zCrateLarge_Top`) is one of its
# children. We resolve both at _ready so the open animation can hinge
# the lid without disturbing the rest of the model.
@onready var visual: Node3D = $Visual

# Cached at _ready by walking the .glb hierarchy. Lid is the named top
# node from the source asset; _mesh is the first MeshInstance3D anywhere
# under Visual (used by the outline shader, falls back to a Node3D if
# the model is unusual). Both can be null if the .glb structure changes
# — code that uses them guards on null.
var _mesh: MeshInstance3D = null
var _lid: Node3D = null
var _lid_rest_position: Vector3 = Vector3.ZERO
# AnimationPlayer is preferred over the manual lid tween whenever the .glb
# ships with its own open animation. Set by _ready when the imported scene
# contains an AnimationPlayer node — Godot adds one automatically when the
# source glTF has animation tracks (Sci Fi Storage Box ships three of them).
var _anim_player: AnimationPlayer = null
var _open_anim_name: StringName = &""

var _opened: bool = false

func _ready() -> void:
	_mesh = _find_first_mesh(visual)
	_lid = _find_named_descendant(visual, "zCrateLarge_Top")
	if _lid != null:
		_lid_rest_position = _lid.position
	_anim_player = _find_anim_player(visual)
	if _anim_player != null:
		# Pick the first available animation as "open." For the current
		# Sci Fi Storage Box .glb, all three baked animations are variants
		# of "Inner BoxAction" doing roughly the same lid-lift motion, so
		# any of them reads as "the crate opens."
		var names: PackedStringArray = _anim_player.get_animation_list()
		if names.size() > 0:
			_open_anim_name = StringName(names[0])
	super._ready()


static func _find_anim_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var nested := _find_anim_player(child)
		if nested != null:
			return nested
	return null


static func _find_first_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var nested := _find_first_mesh(child)
		if nested != null:
			return nested
	return null


static func _find_named_descendant(node: Node, target_name: String) -> Node3D:
	for child in node.get_children():
		if child.name == target_name and child is Node3D:
			return child
		var nested := _find_named_descendant(child, target_name)
		if nested != null:
			return nested
	return null

func _get_outline_source() -> MeshInstance3D:
	return _mesh

func _get_tooltip_text() -> String:
	return "Loot Crate" if not _opened else "Empty Crate"

func reset_state() -> void:
	_opened = false
	if _lid != null:
		_lid.position = _lid_rest_position
		_lid.rotation_degrees = Vector3.ZERO
	if _anim_player != null and _open_anim_name != &"":
		_anim_player.stop()
		_anim_player.seek(0.0, true)
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
	# Prefer the .glb's baked-in animation when present (Sci Fi Storage Box
	# ships an "Inner BoxAction" lid-lift). Falls through to the manual lid
	# tween if the model has a named lid node but no AnimationPlayer (older
	# Container Large authoring pattern).
	if _anim_player != null and _open_anim_name != &"":
		_anim_player.play(_open_anim_name)
		WeaponSounds.play_generic(&"chest_open", global_position)
		return
	# Lift the lid off the crate and tilt it backward — the model is
	# authored with the top as a removable lid (no hinge geometry), so
	# the natural animation is "set it aside" rather than "hinge open."
	# Total ~0.5s — chase it with the chest_open SFX so the sound's
	# decay lines up with the tween settle.
	if _lid != null:
		var tween := create_tween().set_parallel(true)
		tween.tween_property(
			_lid, "position",
			_lid_rest_position + Vector3(0.0, 0.45, -0.35), 0.45,
		).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(
			_lid, "rotation_degrees",
			Vector3(-22.0, 0.0, 6.0), 0.45,
		).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# Plays on both the local opener AND every peer that receives the
	# _client_open_visual RPC (the visual path runs on both sides).
	WeaponSounds.play_generic(&"chest_open", global_position)


func _become_inert() -> void:
	input_ray_pickable = false
	SpatialGrid.unregister(self)
	if _outline_source != null:
		OutlineCompositor.detach(_outline_source)
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


func _apply_color(_c: Color) -> void:
	# No-op: the .glb ships with its own PBR materials we don't override.
	# Open-state read comes from the lid-lift tween + _become_inert
	# (outline hide, pickability off). Kept as a stub so any caller
	# that still invokes _apply_color doesn't error.
	pass
