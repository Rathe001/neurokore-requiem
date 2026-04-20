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
var _light: OmniLight3D
var _tube_mat: StandardMaterial3D


func setup(light: OmniLight3D, tube_mat: StandardMaterial3D) -> void:
	_light = light
	_tube_mat = tube_mat
	_base_energy = light.light_energy
	_base_emission = tube_mat.emission_energy_multiplier


func _physics_process(delta: float) -> void:
	if _light == null:
		return

	if _flicker_timer > 0.0:
		_flicker_timer -= delta
		if _flicker_timer <= 0.0:
			_light.light_energy = _base_energy
			if _tube_mat != null:
				_tube_mat.emission_energy_multiplier = _base_emission
		return

	if randf() < flicker_chance:
		var depth := randf_range(flicker_depth * 0.3, flicker_depth)
		var factor := 1.0 - depth
		_light.light_energy = _base_energy * factor
		if _tube_mat != null:
			_tube_mat.emission_energy_multiplier = _base_emission * factor
		_flicker_timer = randf_range(flicker_duration * 0.5, flicker_duration * 1.5)
		# Occasional longer flicker — double blink.
		if randf() < 0.15:
			_flicker_timer *= 3.0
