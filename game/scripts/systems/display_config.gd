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

# MSAA values mirror Viewport.MSAA: 0=Disabled, 1=2×, 2=4×, 3=8×.
# screen_space_aa mirrors Viewport.ScreenSpaceAA: 0=Disabled, 1=FXAA.
@export var mode: Mode = Mode.WINDOWED
@export var resolution: Vector2i = Vector2i(1280, 720)
@export var fps_mouse_sensitivity: float = 0.006
@export var msaa_3d: int = Viewport.MSAA_4X
@export var screen_space_aa: int = Viewport.SCREEN_SPACE_AA_FXAA
@export var bloom_enabled: bool = true
