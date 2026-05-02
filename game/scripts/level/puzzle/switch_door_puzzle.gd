extends PuzzleDef
class_name SwitchDoorPuzzle
## N switches → 1 door. Each switch's UNLOCK action decrements the door's
## remaining-unlock counter; the door opens when the counter hits zero.
## Defaults to "all switches required"; set required_count to N for "any
## N of M".

@export var switch_slot_ids: Array[StringName] = []  ## level-global slot keys, e.g. ["lobby.sw_a", "hub.sw_b"]
@export var door_connection_id: StringName = &""
## How many switches must be hit. 0 = all (size of switch_slot_ids).
@export var required_count: int = 0


func apply(_ctx: LevelBuildContext, slots: Dictionary, doors: Dictionary) -> void:
	if door_connection_id == &"":
		push_error("[SwitchDoorPuzzle] door_connection_id not set.")
		return
	var door := doors.get(door_connection_id) as PrototypeDoor
	if door == null:
		push_error("[SwitchDoorPuzzle] No door found for connection '%s'." % door_connection_id)
		return
	if switch_slot_ids.is_empty():
		push_error("[SwitchDoorPuzzle] switch_slot_ids is empty.")
		return

	var switches: Array[PrototypeSwitch] = []
	for sid in switch_slot_ids:
		var node := slots.get(sid) as PrototypeSwitch
		if node == null:
			push_error("[SwitchDoorPuzzle] Slot '%s' is not a PrototypeSwitch (or missing)." % sid)
			continue
		switches.append(node)
	if switches.is_empty():
		return

	var n := required_count if required_count > 0 else switches.size()
	door.setup_lock(n, true, false)
	for sw in switches:
		sw.target_door = sw.get_path_to(door)
		sw.action = PrototypeSwitch.Action.UNLOCK
