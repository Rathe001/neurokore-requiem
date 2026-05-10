class_name DamageNumber extends Node3D

# Pooled floating combat numbers. At horde scale every kill / multistrike
# emits at least one of these; allocating a fresh Node3D + Label3D + Tween
# per hit was visible in profiler. Free instances are kept on a static stack
# and rebound to a new world parent on reuse.

const DURATION: float = 0.85
const RISE: float = 1.2
const SPREAD: float = 0.35
const PIXEL_SIZE: float = 0.004
const POOL_LIMIT: int = 64
# Pop-in: numbers spawn larger and quickly settle to 1.0 — gives every
# hit a momentary "punch" on screen. Crit hits pop bigger so they read
# as distinct visual events even when the color difference is missed.
const POP_SCALE_NORMAL: float = 1.25
const POP_SCALE_CRIT: float = 1.55
const POP_DURATION: float = 0.14

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
const COLOR_HEAL: Color = Color(0.40, 1.00, 0.55, 1.0)
const COLOR_MISS: Color = Color(0.70, 0.70, 0.75, 0.9)
const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.08, 1.0)
const OUTLINE_SIZE: int = 12

static var _pool: Array[DamageNumber] = []

var _label: Label3D
var _shake: float = 0.0
var _elapsed: float = 0.0
var _pop_scale: float = 1.0
var _tween: Tween

static func spawn(world: Node, pos: Vector3, amount: int, multistrike: int = 1, is_crit: bool = false) -> void:
	# Crits add a "!" suffix on top of color + scale to triple-up the
	# visual hierarchy. Multistrike "×N" pushes onto the same line.
	var text := str(amount)
	if is_crit:
		text += "!"
	if multistrike > 1:
		text += " ×%d" % multistrike
	_spawn_internal(world, pos, text,
		_font_for(multistrike, is_crit),
		COLOR_CRIT if is_crit else COLOR_NORMAL,
		_shake_for(multistrike, is_crit),
		POP_SCALE_CRIT if is_crit else POP_SCALE_NORMAL)


static func spawn_miss(world: Node, pos: Vector3) -> void:
	_spawn_internal(world, pos, "Miss!", FONT_NORMAL, COLOR_MISS, SHAKE_NONE, POP_SCALE_NORMAL)


static func spawn_heal(world: Node, pos: Vector3, amount: int) -> void:
	_spawn_internal(world, pos, "+" + str(amount), FONT_NORMAL, COLOR_HEAL, SHAKE_NONE, POP_SCALE_NORMAL)


static func _spawn_internal(world: Node, pos: Vector3, text: String, font_size: int, color: Color, shake: float, pop_scale: float) -> void:
	var n: DamageNumber = _acquire()
	var label := n._label
	label.text = text
	label.font_size = font_size
	label.modulate = color
	label.position = Vector3.ZERO
	n._shake = shake
	n._elapsed = 0.0
	n._pop_scale = pop_scale

	var current_parent := n.get_parent()
	if current_parent != world:
		if current_parent != null:
			current_parent.remove_child(n)
		world.add_child(n)

	n.global_position = pos + Vector3(randf_range(-SPREAD, SPREAD), 0.0, randf_range(-SPREAD, SPREAD))
	n._animate()

static func _acquire() -> DamageNumber:
	while _pool.size() > 0:
		var n: DamageNumber = _pool.pop_back()
		if is_instance_valid(n) and is_instance_valid(n._label):
			return n
	return _build_new()

static func _build_new() -> DamageNumber:
	var n := DamageNumber.new()
	n.top_level = true
	var label := Label3D.new()
	label.pixel_size = PIXEL_SIZE
	label.outline_modulate = OUTLINE_COLOR
	label.outline_size = OUTLINE_SIZE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.fixed_size = false
	n._label = label
	n.add_child(label)
	return n

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
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var start := global_position
	var end := start + Vector3(0.0, RISE, 0.0)
	_label.modulate.a = 1.0
	# Start the label scaled up; it pops down to 1.0 quickly. Crits use
	# a higher start scale so they read as a heavier impact.
	scale = Vector3.ONE * _pop_scale
	_tween = create_tween().set_parallel(true)
	# Rise — BACK trans on the way up gives a tiny overshoot for the
	# "leap off the target" feel before settling into its arc.
	_tween.tween_property(self, ^"global_position", end, DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Scale pop — quickly snap back to 1.0 (front-loaded into the
	# first POP_DURATION seconds).
	_tween.tween_property(self, ^"scale", Vector3.ONE, POP_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_label, ^"modulate:a", 0.0, DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(DURATION * 0.4)
	_tween.chain().tween_callback(_release)

func _release() -> void:
	_tween = null
	_shake = 0.0
	_pop_scale = 1.0
	scale = Vector3.ONE  # reset for next acquire — tween left us at 1, but defensive
	if _pool.size() < POOL_LIMIT:
		var parent := get_parent()
		if parent != null:
			parent.remove_child(self)
		_pool.append(self)
	else:
		queue_free()

func _process(delta: float) -> void:
	if _shake <= 0.0 or _label == null:
		return
	_elapsed += delta
	var fade := 1.0 - clampf(_elapsed / DURATION, 0.0, 1.0)
	var d := _shake * fade
	_label.position = Vector3(randf_range(-d, d), randf_range(-d, d), 0.0)
