class_name FluorescentFlicker
extends Node3D
## Overhead fluorescent light fixture with optional flicker effect.
## Add OmniLight3D and emissive MeshInstance3D children, then call setup().

## Chance per physics frame of triggering a flicker event (0 = never).
@export var flicker_chance: float = 0.03
## Maximum fractional drop in brightness during a flicker (0–1).
@export var flicker_depth: float = 0.4
## Base duration in seconds of a single flicker dip.
@export var flicker_duration: float = 0.08

var _base_energy: float
var _base_emission: float
var _flicker_timer: float = 0.0
var _light: Light3D
var _tube_mat: StandardMaterial3D
# Tick throttle. Flicker is RNG-driven and doesn't need 60Hz precision —
# 15Hz reads identically (the human eye won't tell the difference between
# a 33ms flicker dip vs a 66ms one against the natural duration variance).
# With 128 fixtures per dense level, the previous full-rate _physics_process
# was 128 calls/tick × ~0.0002ms = ~0.025ms/tick of pure early-out checks.
# Throttling to 1-in-4 cuts the early-out cost while keeping the visible
# flicker rate perceptually unchanged. Counter starts at a random offset
# so 128 fixtures don't all tick the same frame.
const _TICK_DIVISOR: int = 4
var _skip_counter: int = randi() % _TICK_DIVISOR


func setup(light: Light3D, tube_mat: StandardMaterial3D) -> void:
	_light = light
	_tube_mat = tube_mat
	_base_energy = light.light_energy
	_base_emission = 0.0 if tube_mat == null else tube_mat.emission_energy_multiplier


func _physics_process(delta: float) -> void:
	if _light == null:
		return
	_skip_counter += 1
	if _skip_counter < _TICK_DIVISOR:
		return
	_skip_counter = 0
	# Don't flicker lights the player can't see — ProximityLighting fights us
	# for `light_energy` writes, and a flicker dip on a dimmed-out light reads
	# as a stray brightness pop in rooms behind walls or doors.
	if not ProximityLighting.is_visible(_light):
		return

	# delta passed in is one frame's delta; multiply by the divisor so the
	# flicker_timer drains at real-time rate even though we tick at 1/N.
	var effective_delta := delta * _TICK_DIVISOR
	if _flicker_timer > 0.0:
		_flicker_timer -= effective_delta
		if _flicker_timer <= 0.0:
			_light.light_energy = _base_energy
			if _tube_mat != null:
				_tube_mat.emission_energy_multiplier = _base_emission
		return

	# flicker_chance was tuned at 60Hz; rescale so the per-second flicker
	# rate stays the same at the new tick rate.
	if randf() < flicker_chance * _TICK_DIVISOR:
		var depth := randf_range(flicker_depth * 0.3, flicker_depth)
		var factor := 1.0 - depth
		_light.light_energy = _base_energy * factor
		if _tube_mat != null:
			_tube_mat.emission_energy_multiplier = _base_emission * factor
		_flicker_timer = randf_range(flicker_duration * 0.5, flicker_duration * 1.5)
		# Occasional longer flicker — double blink.
		if randf() < 0.15:
			_flicker_timer *= 3.0
