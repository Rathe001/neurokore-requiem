extends Node

## Tracks the current floor's objective chain (switches → boss → descend) so
## the MissionsPanel can render a single live mission line per phase. State
## is populated by the level-build / puzzle / boss / exit layers calling the
## notify_* helpers below; the panel listens for `changed` and re-derives the
## current phase via `current_phase()`.
##
## Phases:
##   SWITCHES — at least one SwitchDoorPuzzle registered switches and not all
##              are activated yet. Label shows "(done/total)".
##   BOSS     — a boss was registered and is still alive.
##   DESCEND  — boss is dead (or no boss but switches done). Stays here until
##              level reset clears the state.
##   NONE     — nothing registered, panel shows the empty placeholder.
##
## reset() is called on level reset / NG+ so the next floor starts clean.

signal changed

const PHASE_NONE: StringName = &""
const PHASE_SWITCHES: StringName = &"switches"
const PHASE_BOSS: StringName = &"boss"
const PHASE_DESCEND: StringName = &"descend"

var _has_switches: bool = false
var switch_total: int = 0
var switch_done: int = 0

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
	_has_switches = false
	switch_total = 0
	switch_done = 0
	_has_boss = false
	boss_alive = false
	exit_unlocked = false
	changed.emit()


# ── Build-time registration ───────────────────────────────────────────────

## SwitchDoorPuzzle calls this after wiring its switches so the panel knows
## the denominator. Multiple puzzles on the same floor accumulate.
func register_switches(count: int) -> void:
	if count <= 0:
		return
	_has_switches = true
	switch_total += count
	changed.emit()


## PrototypeBossSpawn / PrototypeRoot._spawn_boss call this once the boss
## node is in the tree. Idempotent — re-spawning the same boss on level
## reset just re-flags it alive.
func register_boss() -> void:
	_has_boss = true
	boss_alive = true
	changed.emit()


# ── Runtime notifications ─────────────────────────────────────────────────

## PrototypeSwitch._mark_used hooks here. Counter caps at total so a
## stray extra notification doesn't break the display.
func notify_switch_used() -> void:
	if not _has_switches:
		return
	switch_done = mini(switch_done + 1, switch_total)
	changed.emit()


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

## Current phase ID — used by the panel to detect transitions for the
## checkmark animation. Returns PHASE_NONE when nothing's registered yet.
func current_phase() -> StringName:
	if _has_switches and switch_done < switch_total:
		return PHASE_SWITCHES
	if _has_boss and boss_alive:
		return PHASE_BOSS
	if _has_boss or exit_unlocked or (_has_switches and switch_done >= switch_total):
		return PHASE_DESCEND
	return PHASE_NONE


## Current objective label — the panel renders this verbatim.
func current_label() -> String:
	match current_phase():
		PHASE_SWITCHES:
			return "Activate switches (%d/%d)" % [switch_done, switch_total]
		PHASE_BOSS:
			return "Kill the boss"
		PHASE_DESCEND:
			return "Descend to the next level"
		_:
			return ""
