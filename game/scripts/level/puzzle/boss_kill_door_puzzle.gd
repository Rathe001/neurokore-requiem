extends PuzzleDef
class_name BossKillDoorPuzzle
## Doors that auto-unlock when the boss falls. Subscribes each named door to
## the "boss_listeners" group so PrototypeEnemy._die() (group dispatch) calls
## door.on_boss_died() → door.unlock(). Compatible with multi-switch puzzles
## on the same door — the boss-kill counts as one unlock.

@export var door_connection_ids: Array[StringName] = []


func apply(_ctx: LevelBuildContext, _slots: Dictionary, doors: Dictionary) -> void:
	for cid in door_connection_ids:
		var door := doors.get(cid) as PrototypeDoor
		if door == null:
			push_error("[BossKillDoorPuzzle] No door found for connection '%s'." % cid)
			continue
		# Boss-kill unlock co-exists with any prior lock state — don't reset
		# unlock counters here. Just opt the door into the group dispatch.
		door.unlock_on_boss = true
		if not door.is_in_group(&"boss_listeners"):
			door.add_to_group(&"boss_listeners")
