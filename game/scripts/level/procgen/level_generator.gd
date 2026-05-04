extends Resource
class_name LevelGenerator
## Polymorphic base for level generators. Subclasses produce a LevelGraph
## (rooms + connections + optional puzzles) which then flows through the
## existing GraphSolver → LevelBuilder pipeline unchanged. A non-zero seed
## makes the output deterministic; seed=0 means "use wall-clock time".
##
## Convention: subclasses do not mutate the templates or RoomDefs they read
## from — those are shared resources. Each generated RoomNode holds a
## reference (not a copy) to its source RoomDef.

@export var rng_seed: int = 0


func generate() -> LevelGraph:
	push_error("[LevelGenerator] Subclass must override generate().")
	return null


# Weighted role-based pick from a template pool. Subclasses use this to
# select rooms during graph emission. Returns null when no template matches.
static func pick_by_role(templates: Array[RoomTemplate], role: StringName, rng: RandomNumberGenerator) -> RoomTemplate:
	var candidates: Array[RoomTemplate] = []
	var total_weight := 0.0
	for t: RoomTemplate in templates:
		if t == null or t.role != role or t.room == null:
			continue
		candidates.append(t)
		total_weight += t.weight
	return _weighted_pick(candidates, total_weight, rng)


# Weighted pick from templates whose RoomDef.openings exactly matches
# `required` (as a set — order doesn't matter, no extras allowed). Lets a
# generator select rooms by structural shape instead of designer-given
# role tag. Returns null when no template matches.
static func pick_by_openings(templates: Array[RoomTemplate], required: Array, rng: RandomNumberGenerator) -> RoomTemplate:
	var candidates: Array[RoomTemplate] = []
	var total_weight := 0.0
	for t: RoomTemplate in templates:
		if t == null or t.room == null:
			continue
		if _opening_set_equals(t.room.openings, required):
			candidates.append(t)
			total_weight += t.weight
	return _weighted_pick(candidates, total_weight, rng)


static func _weighted_pick(candidates: Array[RoomTemplate], total_weight: float, rng: RandomNumberGenerator) -> RoomTemplate:
	if candidates.is_empty():
		return null
	var roll := rng.randf() * total_weight
	var acc := 0.0
	for t in candidates:
		acc += t.weight
		if roll <= acc:
			return t
	return candidates[-1]


static func _opening_set_equals(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for x in a:
		if not b.has(x):
			return false
	return true
