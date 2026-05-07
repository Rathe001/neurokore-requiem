class_name DeathGlitchOverlay
extends CanvasLayer

## Cinematic glitch overlay shown while the player is dead. Activates on the
## player's `died` signal, deactivates on `respawned`. Sits at CanvasLayer
## 100 — above the gameplay filters at 0 and the HUD at 1+, but below the
## DeathScreen at 110 — so the death screen UI remains readable on top of
## the glitch.
##
## Gated by AccessibilityState.config.reduce_camera_effects: when on, the
## overlay never shows. The death screen itself still appears; only the
## cosmetic glitch is suppressed.

const SHADER: Shader = preload("res://scripts/prototype/death_glitch.gdshader")
const LAYER := 100

var _rect: ColorRect
var _player: Node
var _wants_active: bool = false


func setup(player: Node) -> void:
	_player = player


func _ready() -> void:
	layer = LAYER
	var mat := ShaderMaterial.new()
	mat.shader = SHADER

	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.material = mat
	_rect.color = Color(1, 1, 1, 1)
	_rect.visible = false
	add_child(_rect)

	if _player != null:
		if _player.has_signal(&"died"):
			_player.died.connect(_on_died)
		if _player.has_signal(&"respawned"):
			_player.respawned.connect(_on_respawned)

	if has_node("/root/AccessibilityState"):
		AccessibilityState.changed.connect(_refresh_visibility)


func _on_died() -> void:
	_wants_active = true
	_refresh_visibility()


func _on_respawned() -> void:
	_wants_active = false
	_refresh_visibility()


func _refresh_visibility() -> void:
	_rect.visible = _wants_active and not _is_disabled_by_accessibility()


func _is_disabled_by_accessibility() -> bool:
	if AccessibilityState.config == null:
		return false
	return AccessibilityState.config.reduce_camera_effects
