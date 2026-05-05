class_name StatVFXController
extends Node3D

# Tier VFX stub — will be redesigned for the new talent system.
# Keeps the setup() contract so callers don't need to null-check.

var _base_mat: StandardMaterial3D = null


func setup(_visual: Node3D, base_mat: StandardMaterial3D) -> void:
	_base_mat = base_mat
	if _base_mat != null:
		_base_mat.emission_enabled = true
		_base_mat.emission = Color.BLACK
		_base_mat.emission_energy_multiplier = 0.0
