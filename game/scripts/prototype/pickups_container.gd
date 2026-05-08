extends Node3D
class_name PickupsContainer

## Container for all world pickups (items + credits). In multiplayer, a
## MultiplayerSpawner with a custom spawn_function replicates spawns to
## all peers. The host generates loot and calls spawn_item / spawn_credit;
## the spawner delivers serialized data to every client's _on_spawn which
## reconstructs the pickup locally.
##
## Pickup validation RPCs live here (persistent node) rather than on the
## pickup itself, avoiding races between RPC delivery and spawner removal.

const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_item_pickup.tscn")
const CREDIT_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_credit_pickup.tscn")

var _spawner: MultiplayerSpawner


func _ready() -> void:
	add_to_group(&"pickups_container")
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "MultiplayerSpawner"
	_spawner.spawn_path = NodePath("..")
	_spawner.spawn_function = _on_spawn
	add_child(_spawner)


# ── Public spawn API (host / SP) ───────────────────────────────────

func spawn_item(item: Item, pos: Vector3, owner_id: StringName = &"") -> void:
	if NetState.is_in_lobby():
		var data: Dictionary = {
			&"t": "item",
			&"d": item.to_dict(),
			&"px": pos.x, &"py": pos.y, &"pz": pos.z,
			&"o": String(owner_id),
		}
		_spawner.spawn(data)
	else:
		var pickup := ITEM_PICKUP_SCENE.instantiate()
		pickup.configure(item, owner_id)
		add_child(pickup)
		pickup.global_position = pos


func spawn_credit(amount: int, pos: Vector3) -> void:
	if NetState.is_in_lobby():
		var data: Dictionary = {
			&"t": "credit",
			&"a": amount,
			&"px": pos.x, &"py": pos.y, &"pz": pos.z,
		}
		_spawner.spawn(data)
	else:
		# SP path — use EntityPool for horde-scale perf.
		var pickup := EntityPool.acquire(CREDIT_PICKUP_SCENE)
		if pickup == null:
			return
		pickup.amount = amount
		add_child(pickup)
		pickup.global_position = pos
		pickup.reset()


# ── Spawner callback (runs on ALL peers) ───────────────────────────

func _on_spawn(data: Variant) -> Node:
	var d: Dictionary = data as Dictionary
	if d == null:
		push_warning("[PickupsContainer] _on_spawn received non-Dictionary data.")
		return Node3D.new()
	var type: String = d.get(&"t", "")
	var pos := Vector3(
		float(d.get(&"px", 0.0)),
		float(d.get(&"py", 0.0)),
		float(d.get(&"pz", 0.0)),
	)
	match type:
		"item":
			var item := Item.from_dict(d.get(&"d", {}))
			var owner_str: String = d.get(&"o", "")
			var pickup := ITEM_PICKUP_SCENE.instantiate()
			pickup.configure(item, StringName(owner_str))
			# Position is set BEFORE the spawner adds this as a child, so
			# the pop-up animation launches from the right spot on every peer.
			pickup.position = pos
			return pickup
		"credit":
			var pickup := CREDIT_PICKUP_SCENE.instantiate()
			pickup.amount = int(d.get(&"a", 1))
			pickup.position = pos
			return pickup
		_:
			push_warning("[PickupsContainer] Unknown spawn type: %s" % type)
			return Node3D.new()


# ── Drop-in snapshot (Phase 7) ────────────────────────────────────

## Host-side: serialize every live pickup for a late-joining peer.
func serialize_all() -> Array:
	var result: Array = []
	for child in get_children():
		if child is MultiplayerSpawner:
			continue
		if child.has_method(&"configure") and &"item" in child:
			# Item pickup.
			var item_data: Dictionary = child.item.to_dict() if child.item != null else {}
			var oid: String = String(child.owner_id) if child.owner_id != null else ""
			result.append({
				&"name": child.name,
				&"t": "item",
				&"d": item_data,
				&"px": child.global_position.x,
				&"py": child.global_position.y,
				&"pz": child.global_position.z,
				&"o": oid,
			})
		elif &"amount" in child:
			# Credit pickup.
			result.append({
				&"name": child.name,
				&"t": "credit",
				&"a": int(child.amount),
				&"px": child.global_position.x,
				&"py": child.global_position.y,
				&"pz": child.global_position.z,
			})
	return result


## Client-side: recreate pickups from a snapshot.
func apply_snapshot(data: Array) -> void:
	for entry in data:
		var d: Dictionary = entry as Dictionary
		if d == null:
			continue
		var type: String = d.get(&"t", "")
		var pos := Vector3(
			float(d.get(&"px", 0.0)),
			float(d.get(&"py", 0.0)),
			float(d.get(&"pz", 0.0)),
		)
		var node_name: String = d.get(&"name", "")
		match type:
			"item":
				var item := Item.from_dict(d.get(&"d", {}))
				var owner_str: String = d.get(&"o", "")
				var pickup := ITEM_PICKUP_SCENE.instantiate()
				pickup.configure(item, StringName(owner_str))
				if node_name != "":
					pickup.name = node_name
				add_child(pickup)
				pickup.global_position = pos
			"credit":
				var pickup := CREDIT_PICKUP_SCENE.instantiate()
				pickup.amount = int(d.get(&"a", 1))
				if node_name != "":
					pickup.name = node_name
				add_child(pickup)
				pickup.global_position = pos


# ── Pickup validation RPCs ─────────────────────────────────────────
# Routed through this persistent node so the pickup can be queue_free'd
# immediately after confirm without worrying about RPC delivery order.

@rpc("any_peer", "call_remote", "reliable")
func request_item_pickup(pickup_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var pickup := get_node_or_null(pickup_path)
	if pickup == null or not pickup.has_method(&"interact"):
		return
	var requester: int = multiplayer.get_remote_sender_id()
	var owner: String = String(pickup.owner_id) if pickup.owner_id != null else ""
	# Validate: owner_id is a Steam id (set at drop time from
	# NetState.lobby_members, keyed by Steam id), `requester` is a Godot
	# peer id. Bridge through NetState.steam_id_for_peer so the
	# comparison happens in the same id space.
	if owner != "":
		var requester_steam_id: int = NetState.steam_id_for_peer(requester)
		if owner != str(requester_steam_id):
			return
	# Confirm to the requesting peer with the full item data so they
	# don't depend on the node still existing when the RPC arrives.
	var item_data: Dictionary = pickup.item.to_dict() if pickup.item != null else {}
	_confirm_item_pickup.rpc_id(requester, item_data)
	# If the host IS the requester, they already got the confirm above
	# via rpc_id — but rpc_id to self doesn't fire when you're the server.
	# Handle host pickup inline.
	if requester == 1:
		if pickup.item != null:
			InventoryState.add_to_inventory(pickup.item)
	SpatialGrid.unregister(pickup)
	pickup.queue_free()


@rpc("authority", "call_remote", "reliable")
func _confirm_item_pickup(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return
	var item := Item.from_dict(item_data)
	InventoryState.add_to_inventory(item)


@rpc("any_peer", "call_remote", "reliable")
func request_credit_collect(credit_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var pickup := get_node_or_null(credit_path)
	if pickup == null:
		return
	var requester: int = multiplayer.get_remote_sender_id()
	var amount: int = int(pickup.get(&"amount")) if &"amount" in pickup else 1
	_confirm_credit_collect.rpc_id(requester, amount)
	if requester == 1:
		for node in get_tree().get_nodes_in_group(&"player"):
			if node.is_multiplayer_authority() and node.has_method(&"add_credits"):
				node.add_credits(amount)
				break
	SpatialGrid.unregister(pickup)
	pickup.queue_free()


@rpc("authority", "call_remote", "reliable")
func _confirm_credit_collect(amount: int) -> void:
	# Find the LOCAL player (the one with multiplayer authority), not a
	# remote avatar that happens to be first in the group.
	for node in get_tree().get_nodes_in_group(&"player"):
		if node.is_multiplayer_authority() and node.has_method(&"add_credits"):
			node.add_credits(amount)
			return
