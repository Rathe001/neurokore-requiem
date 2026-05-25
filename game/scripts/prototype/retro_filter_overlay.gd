class_name RetroFilterOverlay
extends CanvasLayer

## Debug-driven retro post-process overlay. Owns one ColorRect + ShaderMaterial
## that runs on every frame and picks behavior at runtime via a `mode` uniform.
## Modes are listed in the RetroMode enum below; add new modes here AND in
## retro_filter.gdshader (kept in sync by hand — small enough to drift-detect).
##
## Reads DebugState.config.retro_filter_mode on startup and whenever the
## DebugConfig resource emits `changed`. The debug panel calls
## DebugState.config.emit_changed() after writing the new mode.
##
## Lives on its own CanvasLayer at layer 0 just like the chromatic aberration
## overlay. Tree order matters within a layer: the overlay added LAST is the
## one that samples the most-recent screen, so this should be added after
## ChromaticAberrationOverlay if both are present.

enum RetroMode {
	OFF = 0,
	VHS = 1,
	SECURITY_CAM = 2,
	NIGHT_VISION = 3,
	THERMAL = 4,
	CONCUSSED = 5,
	DRUNK = 6,
	LOW_HP = 7,
	HALLUCINATION = 8,
	GLITCH = 9,
	NOIR = 10,
	INVERTED = 11,
	CEL_SHADED = 12,
}

const SHADER: Shader = preload("res://scripts/prototype/retro_filter.gdshader")
const LAYER := 0

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = LAYER
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER

	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	_rect.color = Color(1, 1, 1, 1)
	_rect.visible = false
	add_child(_rect)

	if has_node("/root/DebugState"):
		var cfg: DebugConfig = DebugState.config
		if cfg != null:
			cfg.changed.connect(_apply_from_config)
		_apply_from_config()


## Re-reads DebugState.config.retro_filter_mode and updates the shader. The
## ColorRect is hidden in OFF so the shader doesn't run at all when no filter
## is selected — passthrough mode is still a back-buffer copy per pixel.
func _apply_from_config() -> void:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return
	var m: int = int(cfg.retro_filter_mode)
	if m == int(RetroMode.OFF):
		_rect.visible = false
		return
	_rect.visible = true
	_mat.set_shader_parameter(&"mode", m)
