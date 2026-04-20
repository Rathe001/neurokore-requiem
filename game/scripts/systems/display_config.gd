class_name DisplayConfig
extends Resource

# Persisted display preferences. Loaded by DisplayState at boot and applied
# to the window. window_mode mirrors DisplayServer.WindowMode values for
# the modes we expose: WINDOWED, FULLSCREEN (exclusive), and a borderless
# windowed-fullscreen flag handled separately.

enum Mode {
	WINDOWED,
	BORDERLESS_FULLSCREEN,
	EXCLUSIVE_FULLSCREEN,
}

@export var mode: Mode = Mode.WINDOWED
@export var resolution: Vector2i = Vector2i(1280, 720)
