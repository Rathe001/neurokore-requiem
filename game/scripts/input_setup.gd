extends Node

# Registers input actions at startup so the rest of the game can refer to
# them by name (e.g. "move_up") instead of hardcoding key constants.
# When we add controller bindings or a rebinding UI later, they slot in
# alongside the keyboard bindings here.

func _ready() -> void:
	_register("move_up", KEY_W)
	_register("move_down", KEY_S)
	_register("move_left", KEY_A)
	_register("move_right", KEY_D)

func _register(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)
