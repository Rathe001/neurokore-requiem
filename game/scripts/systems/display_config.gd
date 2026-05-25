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
## Temporal anti-aliasing — accumulates samples across frames. Cheap and
## extremely effective on procedural shaders (kills the sub-pixel crawl
## on bump-mapped floor seams). Compose with MSAA for the best image.
@export var use_taa: bool = false
@export var bloom_enabled: bool = true

## Global Illumination quality. Drives SDFGI on/off + tuning at scene apply time.
## OFF       — sdfgi_enabled = false. Lowest GPU/CPU cost, fastest level load.
##              Default for the v0.3.x perf pass after the 50-second SDFGI
##              cascade-bake stall hit playtesters on a procgen-rebake every
##              level. Cyberpunk look relies on emissive + bloom rather than
##              soft GI bounce, so the visual hit is small.
## LOW       — sdfgi_enabled, 0.35m cells, 2 cascades, no occlusion, 1 bounce.
##              ~10s convergence, ~3ms/frame steady-state. Visible soft bounce
##              for warm interiors without the full-quality cost.
## HIGH      — sdfgi_enabled, original (0.15m cells, 4 cascades, occlusion,
##              2 bounces). The pre-v0.3 setting. ~50s convergence on level
##              load, best-looking GI; only viable on strong GPUs.
enum GiQuality {
	OFF,
	LOW,
	HIGH,
}

@export var gi_quality: GiQuality = GiQuality.OFF
