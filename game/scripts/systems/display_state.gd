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
	# Sync newly-spawned WorldEnvironment nodes with the current bloom setting
	# so scene transitions don't reintroduce glow when the user disabled it.
	get_tree().node_added.connect(_on_node_added)
	apply()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	# Alt-tab cycle: viewport state (TAA history, MSAA buffer, glow buffer)
	# can land in a bad spot when the window regains focus — most visibly the
	# WorldEnvironment glow goes dark and projectile / beam lights stop
	# blooming. Re-applying the saved config rebinds the viewport AA settings
	# and pushes glow_enabled back onto every WorldEnvironment, which is
	# enough to clear the issue without rebuilding the scene.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		apply.call_deferred()

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

func set_msaa_3d(new_msaa: Viewport.MSAA) -> void:
	if config == null or config.msaa_3d == new_msaa:
		return
	config.msaa_3d = new_msaa
	apply()
	save()

func set_screen_space_aa(new_ssaa: Viewport.ScreenSpaceAA) -> void:
	if config == null or config.screen_space_aa == new_ssaa:
		return
	config.screen_space_aa = new_ssaa
	apply()
	save()

func set_use_taa(enabled: bool) -> void:
	if config == null or config.use_taa == enabled:
		return
	config.use_taa = enabled
	apply()
	save()

func set_bloom_enabled(enabled: bool) -> void:
	if config == null or config.bloom_enabled == enabled:
		return
	config.bloom_enabled = enabled
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
	# Apply AA to the root viewport. Both settings live on Viewport in Godot 4
	# and override project.godot defaults at runtime.
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = config.msaa_3d
		vp.screen_space_aa = config.screen_space_aa
		vp.use_taa = config.use_taa
	_apply_bloom_to_environments()
	changed.emit()

func _apply_bloom_to_environments() -> void:
	var root := get_tree().root if get_tree() != null else null
	if root == null:
		return
	for node in root.find_children("*", "WorldEnvironment", true, false):
		var we := node as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.glow_enabled = config.bloom_enabled

func _on_node_added(node: Node) -> void:
	# Catches WorldEnvironment nodes added after _ready (level loads, scene
	# changes) so the user's bloom preference applies to them too.
	if config == null:
		return
	var we := node as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.glow_enabled = config.bloom_enabled

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
	@warning_ignore("integer_division")
	var offset := (screen_size - window_size) / 2
	DisplayServer.window_set_position(screen_origin + offset)
