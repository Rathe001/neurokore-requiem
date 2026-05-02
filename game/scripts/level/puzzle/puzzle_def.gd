extends Resource
class_name PuzzleDef
## Polymorphic base for level puzzles. Subclasses (built-in templates and
## designer-authored one-offs) override apply() to wire interactables,
## doors, and any custom logic at the end of level construction.
##
## apply() runs once at build time, AFTER all geometry, doors, and
## interactable slots have been spawned. By that point:
##   - `slots[name]` returns the spawned interactable Node (e.g. a switch)
##     for any slot declared as "{room_id}.{slot_id}" on a RoomDef.
##   - `doors[connection_id]` returns the PrototypeDoor at the from-room
##     side of the named connection.
##
## Wiring stays in effect across level resets: HoverableInteractable.reset_state()
## and PrototypeDoor.reset_state() restore initial state, so puzzles do not
## need to re-apply.


# Subclasses must override.
func apply(_ctx: LevelBuildContext, _slots: Dictionary, _doors: Dictionary) -> void:
	push_error("[PuzzleDef] Subclass must override apply().")
