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
@export var fps_mouse_sensitivity: float = 0.006
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA_4X
@export var screen_space_aa: Viewport.ScreenSpaceAA = Viewport.SCREEN_SPACE_AA_FXAA
@export var bloom_enabled: bool = true
