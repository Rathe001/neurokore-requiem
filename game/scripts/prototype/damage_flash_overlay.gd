class_name DamageFlashOverlay
extends CanvasLayer

## Quick screen-edge flash on heavy hits. Intensity scales with damage
## as a fraction of max health — chip damage is invisible, sniper rounds
## and RPG splash paint the screen. Separate from LowHpWarningOverlay
## (which pulses continuously below 30% HP); this fires once per hit.

const LAYER := 0
# Minimum damage fraction to trigger a flash at all. Chip damage (SMG
# ticks, bleed ticks, taser arcs) stays below this and produces no flash.
const MIN_DAMAGE_FRAC: float = 0.05
# Flash alpha at 100% max-health damage. Scales linearly from 0 at
# MIN_DAMAGE_FRAC to this at 1.0. Higher = more opaque.
const MAX_ALPHA: float = 0.45
const FLASH_DURATION: float = 0.12
const FLASH_COLOR := Color(0.85, 0.15, 0.10)

var _rect: ColorRect
var _tween: Tween


func _ready() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(FLASH_COLOR, 0.0)
	_rect.visible = false
	add_child(_rect)


func flash(damage: int, max_health: int) -> void:
	if max_health <= 0:
		return
	var frac := float(damage) / float(max_health)
	if frac < MIN_DAMAGE_FRAC:
		return
	var alpha := clampf(remap(frac, MIN_DAMAGE_FRAC, 1.0, 0.0, MAX_ALPHA), 0.0, MAX_ALPHA)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_rect.color = Color(FLASH_COLOR, alpha)
	_rect.visible = true
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", 0.0, FLASH_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_callback(func() -> void: _rect.visible = false)
