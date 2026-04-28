class_name DamageNumber extends Node3D

const DURATION: float = 0.7
const RISE: float = 1.0
const SPREAD: float = 0.35
const PIXEL_SIZE: float = 0.004

const FONT_NORMAL: int = 56
const FONT_MULTISTRIKE: int = 78
const FONT_CRIT: int = 88
const FONT_CRIT_MULTI: int = 108

const SHAKE_NONE: float = 0.0
const SHAKE_MULTISTRIKE: float = 0.05
const SHAKE_CRIT: float = 0.07
const SHAKE_CRIT_MULTI: float = 0.10

const COLOR_NORMAL: Color = Color(1.00, 0.95, 0.85, 1.0)
const COLOR_CRIT: Color = Color(1.00, 0.40, 0.30, 1.0)
const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.08, 1.0)
const OUTLINE_SIZE: int = 12

var _label: Label3D
var _shake: float = 0.0
var _elapsed: float = 0.0

static func spawn(world: Node, pos: Vector3, amount: int, multistrike: int = 1, is_crit: bool = false) -> void:
	var n := DamageNumber.new()
	n.top_level = true
	n.global_position = pos + Vector3(randf_range(-SPREAD, SPREAD), 0.0, randf_range(-SPREAD, SPREAD))

	var label := Label3D.new()
	var text := str(amount)
	if multistrike > 1:
		text += " ×%d" % multistrike
	label.text = text
	label.font_size = _font_for(multistrike, is_crit)
	label.pixel_size = PIXEL_SIZE
	label.modulate = COLOR_CRIT if is_crit else COLOR_NORMAL
	label.outline_modulate = OUTLINE_COLOR
	label.outline_size = OUTLINE_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.fixed_size = false
	n._label = label
	n.add_child(label)

	n._shake = _shake_for(multistrike, is_crit)
	world.add_child(n)
	n._animate()

static func _font_for(multistrike: int, is_crit: bool) -> int:
	if is_crit and multistrike > 1:
		return FONT_CRIT_MULTI
	if is_crit:
		return FONT_CRIT
	if multistrike > 1:
		return FONT_MULTISTRIKE
	return FONT_NORMAL

static func _shake_for(multistrike: int, is_crit: bool) -> float:
	if is_crit and multistrike > 1:
		return SHAKE_CRIT_MULTI
	if is_crit:
		return SHAKE_CRIT
	if multistrike > 1:
		return SHAKE_MULTISTRIKE
	return SHAKE_NONE

func _animate() -> void:
	var start := global_position
	var end := start + Vector3(0.0, RISE, 0.0)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, ^"global_position", end, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_label, ^"modulate:a", 0.0, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(DURATION * 0.35)
	tween.chain().tween_callback(queue_free)

func _process(delta: float) -> void:
	if _shake <= 0.0 or _label == null:
		return
	_elapsed += delta
	var fade := 1.0 - clampf(_elapsed / DURATION, 0.0, 1.0)
	var d := _shake * fade
	_label.position = Vector3(randf_range(-d, d), randf_range(-d, d), 0.0)
