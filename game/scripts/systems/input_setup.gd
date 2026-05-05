extends Node

# Registers input actions at startup so the rest of the game can refer to
# them by name (e.g. "move_up") instead of hardcoding key constants.
# When we add controller bindings or a rebinding UI later, they slot in
# alongside the keyboard bindings here.

func _ready() -> void:
	_register_keys(&"move_up", [KEY_W])
	_register_keys(&"move_down", [KEY_S])
	_register_keys(&"move_left", [KEY_A])
	_register_keys(&"move_right", [KEY_D])
	_register_mouse(&"fire", MOUSE_BUTTON_LEFT)
	_register_mouse(&"alt_fire", MOUSE_BUTTON_RIGHT)
	_register_keys(&"skill_1", [KEY_1])
	_register_keys(&"skill_2", [KEY_2])
	_register_keys(&"skill_3", [KEY_3])
	_register_keys(&"skill_4", [KEY_4])
	_register_keys(&"skill_q", [KEY_Q])
	_register_keys(&"skill_e", [KEY_E])
	_register_keys(&"reload", [KEY_R])
	_register_keys(&"interact", [])
	_register_keys(&"toggle_light", [KEY_F])
	_register_keys(&"toggle_inventory", [KEY_I, KEY_C])
	_register_keys(&"sprint", [KEY_SHIFT])
	_register_keys(&"crouch", [KEY_CTRL])
	_register_keys(&"jump", [KEY_SPACE])
	_register_keys(&"toggle_view", [KEY_V])
	_register_keys(&"toggle_minimap", [KEY_TAB])
	_register_keys(&"toggle_talents", [KEY_N])
	_register_keys(&"toggle_fullscreen", [KEY_F11])
	_register_keys(&"toggle_debug_panel", [KEY_F3])
	_register_keys(&"debug_horde_spawn", [KEY_F1])
	_register_keys(&"debug_horde_clear", [KEY_F2])

func _register_keys(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
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
