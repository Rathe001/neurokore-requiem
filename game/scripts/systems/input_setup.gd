extends Node

# Registers input actions at startup so the rest of the game can refer to
# them by name (e.g. "move_up") instead of hardcoding key constants.
# When we add controller bindings or a rebinding UI later, they slot in
# alongside the keyboard bindings here.

func _ready() -> void:
	_register_key(&"move_up", KEY_W)
	_register_key(&"move_down", KEY_S)
	_register_key(&"move_left", KEY_A)
	_register_key(&"move_right", KEY_D)
	_register_mouse(&"attack_single", MOUSE_BUTTON_LEFT)
	_register_mouse(&"attack_aoe", MOUSE_BUTTON_RIGHT)
	_register_key(&"skill_1", KEY_1)
	_register_key(&"skill_2", KEY_2)
	_register_key(&"skill_3", KEY_3)
	_register_key(&"skill_4", KEY_4)
	_register_key(&"skill_q", KEY_Q)
	_register_key(&"skill_e", KEY_E)
	_register_key(&"toggle_inventory", KEY_I)
	_register_key(&"toggle_debug_panel", KEY_F3)
	_register_key(&"debug_horde_spawn", KEY_F1)
	_register_key(&"debug_horde_clear", KEY_F2)

func _register_key(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

func _register_mouse(action: StringName, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
