extends Node3D

const POP_UP_SPEED := 4.2
const POP_HORIZONTAL_SPEED := 1.8
const GRAVITY := 14.0
const SETTLED_HEIGHT := 0.35
const BOB_HEIGHT := 0.10
const BOB_SPEED := 2.2
const SPIN_SPEED := 0.8
const MAGNET_DURATION := 0.15
const MAGNET_SHRINK := 0.3

var item: Item = null
## Peer id (as StringName) of the player who owns this drop. Empty means
## anyone can pick it up (manual drops, SP drops).
var owner_id: StringName = &""

@onready var _object: Node3D = $Visual/Object
@onready var _halo: MeshInstance3D = $Visual/Halo
@onready var _beam: MeshInstance3D = $Visual/Beam
@onready var _area: Area3D = $PickupArea

var _velocity: Vector3 = Vector3.ZERO
var _popping: bool = true
var _collecting: bool = false
var _bob_phase: float = 0.0
var _object_y: float = 0.0
var _name_label: Label3D = null

func configure(p_item: Item, p_owner_id: StringName = &"") -> void:
	item = p_item
	owner_id = p_owner_id

func _ready() -> void:
	add_to_group(&"pickups")
	SpatialGrid.register(self, &"pickups")
	_object_y = _object.position.y
	_bob_phase = randf() * TAU
	# Halo + beam dropped — they're noisy at scale (every loot drop in a
	# generated level adds another pulsing rim/light beam). Replaced by a
	# billboarded name label so the player can read what's on the floor at
	# a glance, rarity-tinted so colour still telegraphs value.
	_halo.visible = false
	_beam.visible = false
	if item != null:
		_object.add_child(ItemVisuals.build(item))
		_build_name_label(item)
	var angle := randf() * TAU
	var speed_factor := randf_range(0.7, 1.1)
	_velocity = Vector3(
		cos(angle) * POP_HORIZONTAL_SPEED * speed_factor,
		POP_UP_SPEED * randf_range(0.9, 1.15),
		sin(angle) * POP_HORIZONTAL_SPEED * speed_factor,
	)
	_area.mouse_entered.connect(_on_hover_enter)
	_area.mouse_exited.connect(_on_hover_exit)
	_apply_ownership_visual()


func _build_name_label(p_item: Item) -> void:
	_name_label = Label3D.new()
	_name_label.text = tr(p_item.name_key) if p_item.name_key != "" else "Item"
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Always render on top of world geometry so the label can't be
	# half-clipped by a wall the pickup sits near (intra-room walls,
	# pillars, doorframes). Cross-room "label floating in unlit
	# adjacent room" leaks are handled by the LoS culler — Label3D
	# inherits from GeometryInstance3D, so when ExplorationState
	# reports the pickup's room as not-visible-together with the
	# player's room, los_culler.gd flips its transparency to 1 and
	# the label vanishes entirely. So we can safely skip depth-test
	# clipping here without losing the room gate.
	_name_label.no_depth_test = true
	_name_label.fixed_size = true
	# fixed_size scales by pixel_size; small footprint so the label hovers
	# unobtrusively above the loot. Previous values were sized for a
	# headline, not a label.
	_name_label.pixel_size = 0.0011
	_name_label.font_size = 20
	# Thick fully-opaque black outline so the rarity-coloured text reads
	# legibly against light corridors AND dark rooms without a backplate.
	_name_label.outline_size = 12
	_name_label.modulate = p_item.glyph_color
	_name_label.outline_modulate = Color(0, 0, 0, 1.0)
	_name_label.position = Vector3(0, 1.3, 0)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name_label)


## Dim non-owned item labels AND shrink the world object so the player
## can tell at a glance which drops are theirs. Only applies in MP; in SP
## every drop is owned by default.
##
## owner_id is a Steam id stringified at drop time (see prototype_enemy
## ._drop_item iterating NetState.lobby_members.keys() — those are Steam
## ids, not Godot peer ids). Compare to SteamState.steam_id, NOT
## multiplayer.get_unique_id() which is a Godot peer id (always 1 on host).
func _apply_ownership_visual() -> void:
	if not NetState.is_in_lobby():
		return
	if owner_id == &"":
		return
	var local_id := StringName(str(SteamState.steam_id))
	if owner_id == local_id:
		return
	# Not ours — dim the name label hard and shrink the world object so it
	# reads as background clutter. Hover still pops the label brightness
	# (see _on_hover_enter) so the player can read what it is.
	if _name_label != null:
		var dim: Color = item.glyph_color if item != null else Color.WHITE
		dim.a = 0.12
		_name_label.modulate = dim
	if _object != null:
		_object.scale = Vector3.ONE * 0.7


func _physics_process(delta: float) -> void:
	if _collecting:
		return
	if _popping:
		_velocity.y -= GRAVITY * delta
		var next_pos := global_position + _velocity * delta
		var horiz := Vector3(_velocity.x, 0.0, _velocity.z)
		if horiz.length_squared() > 0.0001:
			var space := get_world_3d().direct_space_state
			var ray_from := global_position + Vector3(0.0, 0.4, 0.0)
			var ray_to := next_pos + Vector3(0.0, 0.4, 0.0)
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			if not space.intersect_ray(query).is_empty():
				next_pos.x = global_position.x
				next_pos.z = global_position.z
				_velocity.x = 0.0
				_velocity.z = 0.0
		global_position = next_pos
		if global_position.y <= SETTLED_HEIGHT and _velocity.y < 0.0:
			global_position.y = SETTLED_HEIGHT
			_velocity = Vector3.ZERO
			_popping = false
		return
	_bob_phase += delta
	_object.position.y = _object_y + sin(_bob_phase * BOB_SPEED) * BOB_HEIGHT
	_object.rotation.y = _bob_phase * SPIN_SPEED

func _on_hover_enter() -> void:
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	if item != null:
		get_tree().call_group(&"interactable_tooltip", &"show_item", item, _resolve_owner_display_name())
	if _name_label != null:
		# Brighter on hover so the player sees what they're targeting,
		# even when it's not theirs — they may want to read the name
		# before walking away from someone else's drop.
		var bright: Color = item.glyph_color if item != null else Color.WHITE
		bright.a = 1.0
		_name_label.modulate = bright


# Returns the persona name of the player who owns this drop — but only
# when it isn't the local player, since "Owned by you" is implicit and
# would just be noise. Empty string in SP and for unowned (manual) drops.
func _resolve_owner_display_name() -> String:
	if not NetState.is_in_lobby():
		return ""
	if owner_id == &"":
		return ""
	if _is_owned_by_local_player():
		return ""
	# owner_id is a Steam id as a string; NetState.lobby_members is keyed
	# by int Steam id → persona name. Fall back to "Someone" if the lookup
	# fails (member left the lobby, malformed id, etc.).
	var owner_str := String(owner_id)
	if not owner_str.is_valid_int():
		return "Someone"
	var steam_id := int(owner_str)
	var name: Variant = NetState.lobby_members.get(steam_id, "")
	if name == null or String(name).is_empty():
		return "Someone"
	return String(name)

func _on_hover_exit() -> void:
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
	if _name_label != null and item != null:
		if _is_owned_by_local_player():
			_name_label.modulate = item.glyph_color
		else:
			# Re-apply the dimmed ownership visual — hover_enter
			# brightened the label so the player could read it.
			var dim: Color = item.glyph_color
			dim.a = 0.12
			_name_label.modulate = dim

## Called by PrototypePlayer._interact_with_hovered after distance gating
## (and after the walk-to-interact path catches up if the click was made
## from out of range). Bails (item stays on ground) if the inventory is
## full, surfacing a banner so the player knows why the pickup didn't
## happen instead of failing silently.
func interact(_user: Node) -> void:
	if _popping or _collecting:
		return
	# Non-owned items can't be picked up.
	if not _is_owned_by_local_player():
		return
	# Bag full: drop the pickup back on the ground (no-op — the node is
	# already there) and notify. The check has to happen BEFORE the MP
	# client RPC path: the host accepts the pickup eagerly and queue_frees
	# its world copy, so a client whose _confirm_item_pickup arrives with
	# no space would lose the item entirely.
	if not InventoryState.has_space():
		_notify_inventory_full()
		return
	# SP or host: pick up directly.
	if not NetState.is_in_lobby():
		_do_local_pickup()
		return
	# MP host picking up own item.
	if NetState.is_host():
		_do_local_pickup()
		return
	# MP client: request from host via PickupsContainer (persistent node).
	var container := _find_pickups_container()
	if container != null:
		container.request_item_pickup.rpc_id(1, get_path())


func _notify_inventory_full() -> void:
	# In MP, the &"player" group holds avatars for every peer on this
	# client. The HUD listens only on the LOCAL player's
	# notification_requested signal — emitting on a remote avatar would
	# deliver the banner to nobody. Find the local-authority player.
	for node in get_tree().get_nodes_in_group(&"player"):
		if not node.has_signal(&"notification_requested"):
			continue
		if node is Node and (node as Node).is_multiplayer_authority():
			node.notification_requested.emit(tr(&"HUD_BANNER_INVENTORY_FULL"))
			return


func _do_local_pickup() -> void:
	if not InventoryState.add_to_inventory(item):
		return
	_collecting = true
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
	SpatialGrid.unregister(self)
	# Pickup audio — reuse ui_confirm which is already registered.
	WeaponSounds.play_generic(&"ui_confirm", global_position, -4.0)
	# Magnet-to-player tween: fly toward the player and shrink.
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not is_instance_valid(player):
		queue_free()
		return
	var target_pos: Vector3 = player.global_position + Vector3(0.0, 1.0, 0.0)
	# Hide the name label immediately so the text doesn't stretch during tween.
	if _name_label != null:
		_name_label.visible = false
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", target_pos, MAGNET_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "scale", Vector3.ONE * MAGNET_SHRINK, MAGNET_DURATION).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


## True when the local player is allowed to pick this up: either we own it,
## it has no owner (manual drop), or we're in SP.
##
## owner_id is a Steam id (see _apply_ownership_visual for context).
## Compare to SteamState.steam_id; multiplayer.get_unique_id() is the
## Godot peer id (host always 1) and would never match a Steam id.
func _is_owned_by_local_player() -> bool:
	if not NetState.is_in_lobby():
		return true
	if owner_id == &"":
		return true
	return owner_id == StringName(str(SteamState.steam_id))


func _find_pickups_container() -> PickupsContainer:
	var pc := get_tree().get_first_node_in_group(&"pickups_container")
	if pc is PickupsContainer:
		return pc as PickupsContainer
	# Fallback: walk up the tree.
	var parent := get_parent()
	if parent is PickupsContainer:
		return parent as PickupsContainer
	return null
