extends Node

# Owns window mode + resolution. Loads DisplayConfig from user://display.tres
# at boot and applies it; settings UI (and F11) mutate the config and call
# apply()/save().
#
# Resolution list is curated 16:9 + 16:10 entries filtered to ones that
# fit on the user's primary monitor. There's no engine API to enumerate
# every supported video mode (that's a fullscreen-only concept on most
# platforms), so we cap by screen size and trust the user.

signal changed

const SAVE_PATH := "user://display.tres"

const RESOLUTIONS_16_9: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

const RESOLUTIONS_16_10: Array[Vector2i] = [
	Vector2i(1280, 800),
	Vector2i(1440, 900),
	Vector2i(1680, 1050),
	Vector2i(1920, 1200),
	Vector2i(2560, 1600),
]

var config: DisplayConfig

func _ready() -> void:
	config = _load_config()
	apply()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()

func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var combined: Array[Vector2i] = []
	combined.append_array(RESOLUTIONS_16_9)
	combined.append_array(RESOLUTIONS_16_10)
	var filtered: Array[Vector2i] = []
	for res in combined:
		if res.x <= screen.x and res.y <= screen.y:
			filtered.append(res)
	filtered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return filtered

func set_mode(new_mode: int) -> void:
	if config == null or config.mode == new_mode:
		return
	config.mode = new_mode
	apply()
	save()

func set_resolution(new_resolution: Vector2i) -> void:
	if config == null or config.resolution == new_resolution:
		return
	config.resolution = new_resolution
	apply()
	save()

func toggle_fullscreen() -> void:
	if config == null:
		return
	var next := DisplayConfig.Mode.WINDOWED if config.mode != DisplayConfig.Mode.WINDOWED else DisplayConfig.Mode.BORDERLESS_FULLSCREEN
	set_mode(next)

func apply() -> void:
	if config == null:
		return
	match config.mode:
		DisplayConfig.Mode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(config.resolution)
			_center_window()
		DisplayConfig.Mode.BORDERLESS_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayConfig.Mode.EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	changed.emit()

func save() -> void:
	if config == null:
		return
	var err := ResourceSaver.save(config, SAVE_PATH)
	if err != OK:
		push_warning("[DisplayState] failed to save: %d" % err)

func _load_config() -> DisplayConfig:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded := load(SAVE_PATH) as DisplayConfig
		if loaded != null:
			return loaded
	return DisplayConfig.new()

func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen)
	var screen_origin := DisplayServer.screen_get_position(screen)
	var window_size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(screen_origin + (screen_size - window_size) / 2)
