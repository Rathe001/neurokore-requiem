extends Node

## Per-run fog-of-war / room-tracking state. Two responsibilities:
##
## 1. Cell → room lookup. LevelBuilder calls register_room() for every room
##    and corridor at build time, stamping each 4m cell within the piece's
##    XZ footprint with the piece's id. LosCuller queries room_at_world() to
##    gate entity visibility by current-room match — entities in rooms the
##    player isn't standing in don't render.
##
## 2. Persistent "ever-explored" set. The first time the player stands in a
##    room (or any frame thereafter), reveal_room() flips that room's bit.
##    The minimap and full map read is_explored() to decide which rooms to
##    draw. Bits never un-set within a level — once seen, always remembered.
##
## Reset on level descend (PrototypeExit dispatches &"level_reset_handler"
## reset_level) clears both halves so the next floor starts blank.
##
## MP: host-authoritative. Host's reveal_room() RPCs _client_reveal to all
## peers so a peer's minimap matches what the host has explored. Late-joiners
## get the current set via sync_to_peer() called from the lobby join flow.
## Cell map is built locally on each peer from the deterministically-seeded
## layout — no RPC needed since both sides build the same geometry.

signal changed
signal room_revealed(room_id: StringName)

const CELL_SIZE := 4.0
const _INV_CELL_SIZE := 1.0 / CELL_SIZE

# Vector2i (cell x, cell z) -> StringName (room/corridor id).
var _cell_to_room: Dictionary = {}
# StringName -> true. Membership = "this room has been revealed at some point
# during the current run."
var _explored: Dictionary = {}
# Per-piece XZ footprints captured during register_room. Used by
# finalize_layout() to compute adjacency; cleared on reset.
# Each entry: {"id": StringName, "cx": float, "cz": float, "hx": float, "hz": float}
var _piece_records: Array = []
# room_id -> Array[StringName] of directly-touching neighbours. Populated by
# finalize_layout() after all pieces are registered. A piece is "adjacent" to
# another if their XZ AABBs share an edge (within wall-thickness tolerance) —
# rooms-to-corridors and corridors-to-rooms light up; rooms separated by a
# corridor are NOT adjacent (they're two hops away). LosCuller treats the
# current piece + its neighbours as "visible together" so standing in a
# corridor still shows the rooms at its endpoints, fixing the "clutter
# disappears around the corner" leak that strict per-piece gating creates
# when the player's perceptual "open space" spans two LevelGraph pieces.
var _adjacent: Dictionary = {}


func _ready() -> void:
	add_to_group(&"level_reset_handler")


# Group-dispatched from PrototypeExit / PrototypeRoot on level descend.
# Signature matches MissionState.reset_level.
func reset_level() -> void:
	reset()


func reset() -> void:
	_cell_to_room.clear()
	_explored.clear()
	_piece_records.clear()
	_adjacent.clear()
	changed.emit()


# ── Build-time registration ───────────────────────────────────────────────

## LevelBuilder calls this once per piece (room or corridor) after the
## geometry pass. center + half-extents define the XZ footprint; every cell
## fully or partially covered is stamped with room_id. Cells overlapping
## multiple pieces (which shouldn't happen with non-overlapping geometry)
## last-write-wins — registration order isn't meaningful.
func register_room(room_id: StringName, center: Vector3, half_x: float, half_z: float) -> void:
	if room_id == &"" or half_x <= 0.0 or half_z <= 0.0:
		return
	var x0 := int(floor((center.x - half_x) * _INV_CELL_SIZE))
	var z0 := int(floor((center.z - half_z) * _INV_CELL_SIZE))
	var x1 := int(ceil((center.x + half_x) * _INV_CELL_SIZE))
	var z1 := int(ceil((center.z + half_z) * _INV_CELL_SIZE))
	for x in range(x0, x1):
		for z in range(z0, z1):
			_cell_to_room[Vector2i(x, z)] = room_id
	_piece_records.append({"id": room_id, "cx": center.x, "cz": center.z, "hx": half_x, "hz": half_z})


## LevelBuilder calls this once after all pieces are registered for a given
## build. Computes the per-piece neighbour list by AABB-touch testing every
## pair — O(n²) but n ≤ ~40 pieces so the cost is trivial at level-load.
## Must be called after the final register_room() and before the next
## reset(); LosCuller's room-gating reads the adjacency map directly.
func finalize_layout() -> void:
	_adjacent.clear()
	# Wall-thickness tolerance. Pieces butt up flush at openings but the
	# wall geometry has ~0.6m thickness; the floor StaticBodies that drive
	# our half-extents extend out to the interior wall face, so two pieces
	# whose interiors are wall-separated have a gap of about one wall
	# thickness. Bump to ~1.5 (about a third of a cell) to absorb that
	# without false-positive matching distant pieces.
	const TOUCH_EPS := 1.5
	for i in range(_piece_records.size()):
		var a: Dictionary = _piece_records[i]
		for j in range(i + 1, _piece_records.size()):
			var b: Dictionary = _piece_records[j]
			if _aabbs_touch(a, b, TOUCH_EPS):
				_add_neighbour(a["id"], b["id"])
				_add_neighbour(b["id"], a["id"])


func _add_neighbour(from: StringName, to: StringName) -> void:
	if not _adjacent.has(from):
		_adjacent[from] = [] as Array
	var arr: Array = _adjacent[from]
	if not (to in arr):
		arr.append(to)


# True when the two AABBs are touching or overlapping in both XZ axes
# (with eps tolerance on each axis). Edge-touch (gap == 0 on one axis,
# overlap on the other) qualifies; corner-only touches don't (a piece
# only adjacent at a corner-cell isn't perceptually "the same space").
func _aabbs_touch(a: Dictionary, b: Dictionary, eps: float) -> bool:
	var a_min_x: float = float(a["cx"]) - float(a["hx"])
	var a_max_x: float = float(a["cx"]) + float(a["hx"])
	var a_min_z: float = float(a["cz"]) - float(a["hz"])
	var a_max_z: float = float(a["cz"]) + float(a["hz"])
	var b_min_x: float = float(b["cx"]) - float(b["hx"])
	var b_max_x: float = float(b["cx"]) + float(b["hx"])
	var b_min_z: float = float(b["cz"]) - float(b["hz"])
	var b_max_z: float = float(b["cz"]) + float(b["hz"])
	var gap_x: float = maxf(a_min_x, b_min_x) - minf(a_max_x, b_max_x)
	var gap_z: float = maxf(a_min_z, b_min_z) - minf(a_max_z, b_max_z)
	# Edge-touch: gap ≤ eps on one axis AND strict overlap (gap < 0) on the
	# other. Two axes touching with no overlap = corner kiss, which we don't
	# count — those pieces only share a single cell and aren't perceptually
	# the same space.
	if gap_x <= eps and gap_z < 0.0:
		return true
	if gap_z <= eps and gap_x < 0.0:
		return true
	return false


# ── Runtime queries ───────────────────────────────────────────────────────

## Returns the room/corridor id containing the given world position, or &""
## if the position is outside any registered piece. Cell-sized granularity —
## the lookup is O(1) so callers can hit this every physics frame.
func room_at_world(world: Vector3) -> StringName:
	var cell := Vector2i(
		int(floor(world.x * _INV_CELL_SIZE)),
		int(floor(world.z * _INV_CELL_SIZE)),
	)
	return _cell_to_room.get(cell, &"")


func is_explored(room_id: StringName) -> bool:
	return _explored.has(room_id)


## True when both rooms should be visible at the same time — same room, or
## directly-adjacent pieces (corridor↔room, room↔room sharing an opening).
## LosCuller uses this to decide whether an entity in a different piece than
## the player should still render. Pieces two hops away (room → corridor →
## room) read as not-visible-together, so distant rooms stay hidden.
## Empty room_ids are treated permissively (return true) so entities placed
## outside any registered piece, or in legacy levels with no graph, keep
## their pre-room-gating visibility.
func rooms_visible_together(player_room: StringName, target_room: StringName) -> bool:
	if player_room == &"" or target_room == &"":
		return true
	if player_room == target_room:
		return true
	var neighbours: Array = _adjacent.get(player_room, [] as Array)
	return target_room in neighbours


# ── Reveal ────────────────────────────────────────────────────────────────

## Marks `room_id` explored. Idempotent — re-revealing a room is a no-op.
## Host broadcasts to peers; clients calling this directly only update local
## state (host's RPC is the authoritative source for them).
func reveal_room(room_id: StringName) -> void:
	if room_id == &"" or _explored.has(room_id):
		return
	_explored[room_id] = true
	room_revealed.emit(room_id)
	changed.emit()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_client_reveal.rpc(room_id)


## Late-join sync. Host calls this with a peer_id when a new player joins
## the lobby so they see the host's current explored set immediately. Sent
## as a single bulk RPC rather than one-per-room to keep the join latency
## low even on heavily-explored floors.
func sync_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var ids: Array = _explored.keys()
	_client_bulk_reveal.rpc_id(peer_id, ids)


@rpc("authority", "call_remote", "reliable")
func _client_reveal(room_id: StringName) -> void:
	if _explored.has(room_id):
		return
	_explored[room_id] = true
	room_revealed.emit(room_id)
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _client_bulk_reveal(ids: Array) -> void:
	var added := false
	for id in ids:
		var sid := id as StringName
		if sid == &"" or _explored.has(sid):
			continue
		_explored[sid] = true
		room_revealed.emit(sid)
		added = true
	if added:
		changed.emit()
