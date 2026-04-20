extends Node

# Runtime state for the active player character. Populated by the startup
# screen before the game scene loads; consumed by the player on _ready.

signal class_changed(class_id: StringName)
signal spec_changed(spec_id: StringName)

var class_id: StringName = &""
var spec_id: StringName = &""

func set_class(id: StringName) -> void:
	if class_id == id:
		return
	class_id = id
	spec_id = &""
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
		class_changed.emit(class_id)
	if spec_diff:
		spec_changed.emit(spec_id)
