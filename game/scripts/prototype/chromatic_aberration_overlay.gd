class_name ChromaticAberrationOverlay
extends CanvasLayer

## Full-screen RGB-split overlay used as a sprint visual. Owns one shader
## ColorRect and tweens the `strength` uniform between 0 (off) and a small
## peak value when the player asks for the effect on/off. Lives on its own
## CanvasLayer above the world but below the HUD so HUD elements never get
## color-fringed.
##
## API:
##   set_active(true|false)  — start ramping toward target. Cheap to call
##                              every frame; checks current target before
##                              starting a new tween.
##   refresh_accessibility() — re-reads AccessibilityState and forces
##                              strength to 0 if reduce_camera_effects is on.

const SHADER: Shader = preload("res://scripts/prototype/chromatic_aberration.gdshader")
# Peak offset in normalized screen units. 0.008 ≈ 15px at 1080p edges,
# combined with the shader's radial bias produces a clearly-visible
# tunneling effect without screen-breaking. Tune downward if it reads as
# too aggressive.
const PEAK_STRENGTH := 0.008
const RAMP_DURATION := 0.18
# CanvasLayer between world (default 0) and HUD layers. HUD spawns at higher
# layers via prototype_hud.tscn; if anything ends up at layer 5 we'd want
# this lower. Keep at 1 for now.
const LAYER := 1

var _rect: ColorRect
var _mat: ShaderMaterial
var _active: bool = false
var _tween: Tween


func _ready() -> void:
	layer = LAYER
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"strength", 0.0)

	_rect = ColorRect.new()
	# Block input so the overlay never eats clicks. mouse_filter MUST be
	# IGNORE on a fullscreen control or every cursor interaction below it
	# silently dies.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	# Color is unused — the shader writes its own RGB from SCREEN_TEXTURE
	# samples, so this just needs to be opaque enough that the shader runs
	# on every pixel. Pure white at full alpha leaves the shader output
	# unmolested.
	_rect.color = Color(1, 1, 1, 1)
	add_child(_rect)

	if has_node("/root/AccessibilityState"):
		AccessibilityState.changed.connect(refresh_accessibility)
	refresh_accessibility()


## Begin ramping the effect toward `on`. No-op when already at the requested
## state, so callers can poll this every frame from the player movement loop.
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if _is_disabled_by_accessibility():
		return
	_start_ramp(PEAK_STRENGTH if on else 0.0)


## Re-reads AccessibilityState. When reduce_camera_effects is on, force
## strength to 0 immediately and ignore any in-flight tween.
func refresh_accessibility() -> void:
	if _is_disabled_by_accessibility():
		_kill_tween()
		_mat.set_shader_parameter(&"strength", 0.0)
	elif _active:
		_start_ramp(PEAK_STRENGTH)


func _is_disabled_by_accessibility() -> bool:
	if AccessibilityState.config == null:
		return false
	return AccessibilityState.config.reduce_camera_effects


func _start_ramp(target: float) -> void:
	_kill_tween()
	var current := float(_mat.get_shader_parameter(&"strength"))
	# Scale duration by remaining distance so a quick on/off doesn't double
	# up — a half-ramped tween that gets cancelled returns at the same rate
	# instead of snapping back over the full duration.
	var dist := absf(target - current)
	var dur := RAMP_DURATION * (dist / PEAK_STRENGTH) if PEAK_STRENGTH > 0.0 else RAMP_DURATION
	dur = clampf(dur, 0.04, RAMP_DURATION)
	_tween = create_tween()
	_tween.tween_method(_set_strength, current, target, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_strength(v: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter(&"strength", v)
