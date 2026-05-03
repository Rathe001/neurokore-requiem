class_name Effects extends RefCounted

## Unified read path for effect-kind aggregates that combines perk and
## talent contributions. Use this in gameplay code that wants the
## TOTAL value of an effect kind regardless of where it came from
## (e.g. `crit_chance_pct` may be granted by a perk and topped up by
## a talent; the consumer just wants the combined chance).
##
## When source matters — e.g. "is the Aura of Dread TALENT allocated?",
## or "what does the perk grant before talents modify it?" — read
## PerkState.get_aggregate or TalentState.get_aggregate directly. This
## helper is for the common case where the source doesn't.
##
## All methods are static; no instance is ever needed. Both PerkState
## and TalentState are autoloads registered in project.godot, so they
## resolve as global names from any script context.

static func get_aggregate(kind: StringName) -> float:
	return PerkState.get_aggregate(kind) + TalentState.get_aggregate(kind)


## Convenience for "rolls a chance from 0..1". Caller passes the kind;
## helper sums contributions and clamps to a sane range so a buggy
## .tres can't push chances past 100%.
static func roll_chance(kind: StringName) -> bool:
	var chance: float = clampf(get_aggregate(kind), 0.0, 1.0)
	return randf() < chance
