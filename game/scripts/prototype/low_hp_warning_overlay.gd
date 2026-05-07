class_name LowHpWarningOverlay
extends CanvasLayer

## Pulsing red vignette that activates when the player's HP fraction drops
## below WARN_THRESHOLD. Intensity ramps from 0 (at threshold) to 1 (at 0%
## HP) so the effect gets louder as the player gets closer to dying.
##
## Wires to the player's `health_changed(current, max)` signal via setup() —
## call setup(player) before adding to the tree, or before the player has
## emitted any health updates, so the connection is in place.

const SHADER: Shader = preload("res://scripts/prototype/low_hp_warning.gdshader")
const LAYER := 0
const WARN_THRESHOLD := 0.30

var _rect: ColorRect
var _mat: ShaderMaterial
var _player: Node


func setup(player: Node) -> void:
	_player = player


func _ready() -> void:
	layer = LAYER
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"intensity", 0.0)

	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	_rect.color = Color(1, 1, 1, 1)
	_rect.visible = false
	add_child(_rect)

	if _player != null and _player.has_signal(&"health_changed"):
		_player.health_changed.connect(_on_health_changed)


func _on_health_changed(current: int, max_value: int) -> void:
	if max_value <= 0:
		_rect.visible = false
		return
	var frac := float(current) / float(max_value)
	if frac >= WARN_THRESHOLD:
		_rect.visible = false
		_mat.set_shader_parameter(&"intensity", 0.0)
		return
	var intensity := clampf((WARN_THRESHOLD - frac) / WARN_THRESHOLD, 0.0, 1.0)
	_rect.visible = true
	_mat.set_shader_parameter(&"intensity", intensity)
