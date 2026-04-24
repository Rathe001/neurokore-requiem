extends Node

# Runtime state for the active player character. Populated by the startup
# screen before the game scene loads; consumed by the player on _ready.

signal class_changed(class_id: StringName)
signal spec_changed(spec_id: StringName)
signal talents_changed

var class_id: StringName = &""
var spec_id: StringName = &""

## Talent point budget — 1 per 5 levels. Placeholder until leveling exists.
var talent_points_total: int = 20

## Spent talent points per stat, tier, and node.
## Layout: { stat_id: [[bool]*4]*5 } — 5 tiers x 4 nodes each.
var talent_allocations: Dictionary = {}

func set_class(id: StringName) -> void:
	if class_id == id:
		return
	class_id = id
	spec_id = &""
	reset_talents()
	class_changed.emit(class_id)
	spec_changed.emit(spec_id)

func set_spec(id: StringName) -> void:
	if spec_id == id:
		return
	spec_id = id
	spec_changed.emit(spec_id)

func set_class_and_spec(new_class: StringName, new_spec: StringName) -> void:
	var class_diff := class_id != new_class
	var spec_diff := spec_id != new_spec
	class_id = new_class
	spec_id = new_spec
	if class_diff:
		reset_talents()
		class_changed.emit(class_id)
	if spec_diff:
		spec_changed.emit(spec_id)

func set_talent_alloc(stat: StringName, tier: int, node: int, allocated: bool) -> void:
	if not talent_allocations.has(stat):
		talent_allocations[stat] = [
			[false, false, false, false],
			[false, false, false, false],
			[false, false, false, false],
			[false, false, false, false],
			[false, false, false, false],
		]
	talent_allocations[stat][tier][node] = allocated
	talents_changed.emit()

func get_talent_points_spent() -> int:
	var total := 0
	for tier_rows in talent_allocations.values():
		for node_row in tier_rows:
			for allocated in node_row:
				if allocated:
					total += 1
	return total

func reset_talents() -> void:
	talent_allocations.clear()
	talents_changed.emit()
