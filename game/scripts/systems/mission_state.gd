extends Node

## Tracks the current floor's objective chain (switches → boss → descend) so
## the MissionsPanel can render live mission lines. Switch puzzles are tracked
## per-door — a boss room with two entrances generates two puzzles, and each
## shows its own (done/required) so the aggregate count never lies about
## which door is actually open.
##
## Phases:
##   SWITCHES — at least one puzzle is registered and incomplete. The panel
##              renders one line per puzzle.
##   BOSS     — all puzzles done and the boss is alive.
##   DESCEND  — boss is dead, OR no boss in level and all switches done, OR
##              the exit was already unlocked some other way. Wins over the
##              switches check so killing the boss via a partial-puzzle path
##              still cleanly advances the panel.
##   NONE     — nothing registered, panel shows the empty placeholder.
##
## reset() is called on level reset / NG+ so the next floor starts clean.

signal changed

const PHASE_NONE: StringName = &""
const PHASE_SWITCHES: StringName = &"switches"
const PHASE_BOSS: StringName = &"boss"
const PHASE_DESCEND: StringName = &"descend"

# Each puzzle is { "door": WeakRef<PrototypeDoor>, "required": int, "done": int,
# "label": String }. Door is held as a weakref so a level reset that frees
# the door doesn't leak — _puzzles is cleared in reset() anyway, this is
# belt-and-suspenders.
var _puzzles: Array[Dictionary] = []

var _has_boss: bool = false
var boss_alive: bool = false

var exit_unlocked: bool = false


func _ready() -> void:
	# Join the same groups bosses dispatch to and that PrototypeRoot uses
	# for level reset. The existing call_group(&"boss_listeners",
	# &"on_boss_died", boss) and reset-handler dispatches reach us with
	# no caller changes needed.
	add_to_group(&"boss_listeners")
	add_to_group(&"level_reset_handler")


# PrototypeExit fires this via the &"level_reset_handler" group dispatch
# when the player triggers the exit pad. Matches PrototypeRoot.reset_level
# signature.
func reset_level() -> void:
	reset()


func reset() -> void:
	_puzzles.clear()
	_has_boss = false
	boss_alive = false
	exit_unlocked = false
	changed.emit()


# ── Build-time registration ───────────────────────────────────────────────

## SwitchDoorPuzzle calls this once per puzzle, passing the door it gates
## and the switch count. Each puzzle becomes its own line in the missions
## panel, so a boss room with two locked entrances reads as two separate
## "Activate switches (X/Y)" goals instead of a misleading aggregate.
func register_puzzle(door: Node, required: int) -> void:
	if door == null or required <= 0:
		return
	# Defensive: don't double-register if the same door comes through twice.
	for puzzle in _puzzles:
		var existing: Object = puzzle["door"].get_ref()
		if existing == door:
			puzzle["required"] = required
			puzzle["done"] = 0
			changed.emit()
			return
	_puzzles.append({
		"door": weakref(door),
		"required": required,
		"done": 0,
		"label": _puzzle_label(door),
	})
	changed.emit()


## PrototypeBossSpawn / PrototypeEnemy._apply_boss_stats call this once the
## boss node is in the tree. Idempotent — re-spawning the same boss on
## level reset just re-flags it alive.
func register_boss() -> void:
	_has_boss = true
	boss_alive = true
	changed.emit()


# ── Runtime notifications ─────────────────────────────────────────────────

## PrototypeSwitch._mark_used calls this with the door its UNLOCK action
## targets. The matching puzzle's done counter advances; switches that
## aren't part of any registered puzzle are ignored.
func notify_switch_used_for_door(door: Node) -> void:
	if door == null:
		return
	for puzzle in _puzzles:
		var d: Object = puzzle["door"].get_ref()
		if d == door:
			puzzle["done"] = mini(int(puzzle["done"]) + 1, int(puzzle["required"]))
			changed.emit()
			return


## Dispatched via the &"boss_listeners" group when any boss dies (same
## hook PrototypeExit and unlock-on-boss doors use). Method name matches
## the group dispatch signature.
func on_boss_died(_boss: Node) -> void:
	if not _has_boss:
		return
	boss_alive = false
	changed.emit()


## PrototypeExit.unlock() reports here so the panel can transition to the
## descend prompt even if the level skipped the boss phase.
func notify_exit_unlocked() -> void:
	exit_unlocked = true
	changed.emit()


# ── Queries ───────────────────────────────────────────────────────────────

func _any_puzzle_incomplete() -> bool:
	for puzzle in _puzzles:
		if int(puzzle["done"]) < int(puzzle["required"]):
			return true
	return false


func _has_puzzles() -> bool:
	return not _puzzles.is_empty()


## Current phase ID. Boss-dead wins over incomplete switches because the
## player physically can't redo the puzzle once the boss is down, and
## leaving the panel stuck on "switches" after the kill confuses the
## flow.
func current_phase() -> StringName:
	if _has_boss and not boss_alive:
		return PHASE_DESCEND
	if _has_puzzles() and _any_puzzle_incomplete():
		return PHASE_SWITCHES
	if _has_boss and boss_alive:
		return PHASE_BOSS
	if exit_unlocked or _has_puzzles():
		return PHASE_DESCEND
	return PHASE_NONE


## One line per active objective. SWITCHES expands to N lines (one per
## puzzle); BOSS / DESCEND are single-line. Empty array means the
## "No active missions" placeholder.
func current_lines() -> Array[String]:
	var out: Array[String] = []
	match current_phase():
		PHASE_SWITCHES:
			for puzzle in _puzzles:
				var done: int = int(puzzle["done"])
				var req: int = int(puzzle["required"])
				if done >= req:
					continue  # this puzzle is done; hide it
				var label: String = String(puzzle["label"])
				if _puzzles.size() > 1:
					out.append("%s (%d/%d)" % [label, done, req])
				else:
					out.append("Activate switches (%d/%d)" % [done, req])
		PHASE_BOSS:
			out.append("Kill the boss")
		PHASE_DESCEND:
			out.append("Descend to the next level")
		_:
			pass
	return out


## Single-line summary — used by the checkmark animation to label the
## phase that just completed. Joins multi-line switch entries with " · "
## so the green check still reads as one cohesive completion line.
func current_label() -> String:
	var lines := current_lines()
	if lines.is_empty():
		return ""
	return " · ".join(lines)


# ── Helpers ───────────────────────────────────────────────────────────────

## Picks the per-puzzle label suffix. With two puzzles on the same boss
## room we want them distinguishable ("North gate", "South gate" etc).
## The door's cardinal direction in its parent room comes from its name —
## DoorBuilder names doors after the wall they sit on. Fall back to
## "Activate switches" if the door has no useful identifier.
func _puzzle_label(door: Node) -> String:
	if door == null:
		return "Activate switches"
	var name_str := String(door.name).to_lower()
	if "north" in name_str:
		return "North gate switches"
	if "south" in name_str:
		return "South gate switches"
	if "east" in name_str:
		return "East gate switches"
	if "west" in name_str:
		return "West gate switches"
	return "Activate switches"
