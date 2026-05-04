extends PuzzleDef
class_name ClearRoomPuzzle
## Locks a door behind clearing all enemies inside a target room. At apply
## time we snapshot every enemy whose position falls inside the room's
## AABB and connect each of their `died` signals to our unlock handler.
## The door is configured with unlocks_required = enemy_count; each kill
## decrements the counter; the door opens when zero.
##
## Charm-aware: charming an enemy emits `died`, which counts as a "kill"
## for the purpose of this puzzle. If the charm is later released (player
## death, FIFO eviction), the enemy emits `revived` and we re-lock one
## slot on the door so it stays gated until the enemy actually dies.
##
## Empty rooms (no enemies inside the AABB) leave the door unlocked from
## the start — there's nothing to gate against. Reset hand-off works via
## the existing PrototypeDoor.reset_state path, which restores the
## _initial_locked snapshot setup_lock() captured.

@export var room_id: StringName = &""
@export var door_connection_id: StringName = &""

var _door: PrototypeDoor
# Track which guards have already been counted (died / charmed) so a
# guard that was charmed (died emitted) then actually killed doesn't
# double-decrement the counter. Keyed by instance ID.
var _counted: Dictionary = {}


func apply(ctx: LevelBuildContext, _slots: Dictionary, doors: Dictionary) -> void:
	if door_connection_id == &"":
		push_error("[ClearRoomPuzzle] door_connection_id not set.")
		return
	_door = doors.get(door_connection_id) as PrototypeDoor
	if _door == null:
		push_error("[ClearRoomPuzzle] No door found for connection '%s'." % door_connection_id)
		return

	var piece := ctx.pieces_by_id.get(room_id) as LevelPiece
	if piece == null or piece.room == null:
		push_error("[ClearRoomPuzzle] No room piece found for id '%s'." % room_id)
		return

	var center := piece.position
	var hx := piece.room.size.x * 0.5
	var hz := piece.room.size.y * 0.5

	# Snapshot enemies inside the room AABB at build time. EnemySpawner has
	# already placed them; checking position is the cheapest way to know
	# which enemies "belong" to this room without adding spawn-time tagging.
	var guards: Array[Node] = []
	for e: Node in ctx.root.get_tree().get_nodes_in_group(&"enemies"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var p := (e as Node3D).global_position
		if absf(p.x - center.x) <= hx and absf(p.z - center.z) <= hz:
			guards.append(e)

	if guards.is_empty():
		# Nothing to gate against — leave the door unlocked.
		_door.setup_lock(1, false, false)
		return

	_counted.clear()
	_door.setup_lock(guards.size(), true, false)
	for e in guards:
		if e.has_signal(&"died"):
			e.died.connect(_on_guard_died.bind(e))
		if e.has_signal(&"revived"):
			e.revived.connect(_on_guard_revived.bind(e))


func _on_guard_died(guard: Node) -> void:
	var id := guard.get_instance_id()
	if _counted.has(id):
		return
	_counted[id] = true
	if _door != null and is_instance_valid(_door):
		_door.unlock()


func _on_guard_revived(guard: Node) -> void:
	var id := guard.get_instance_id()
	if not _counted.has(id):
		return
	_counted.erase(id)
	if _door != null and is_instance_valid(_door):
		_door.relock_one()
