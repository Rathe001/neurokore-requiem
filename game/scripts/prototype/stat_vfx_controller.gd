class_name StatVFXController
extends Node3D

# Simplified tier visualisation: a single emissive glow on the player /
# enemy mesh, intensity scaled by the highest active tier across stats,
# colour blended from all active stats. Replaces the previous layered
# stack (mist + directional particles + halo + aura) which read as too
# much visual noise during combat. Intent: soft glow at T1, medium at
# T2, heavy at T3 — telegraphs progression without overwhelming the
# encounter.

# Keep the same per-stat colour palette so the colour read of "which stat
# tier is active" is consistent with where it was before. Higher
# saturation than the UI palette so emissives register against varied
# room lighting.
const VFX_STAT_COLORS: Dictionary = {
	&"ort": Color(1.00, 0.85, 0.30, 1.0),  # gold
	&"ing": Color(0.10, 1.00, 0.50, 1.0),  # bioluminescent green
	&"amb": Color(0.55, 0.10, 0.90, 1.0),  # deep purple
	&"dev": Color(1.00, 0.45, 0.10, 1.0),  # orange sparks
	&"opt": Color(0.15, 0.75, 1.00, 1.0),  # cold blue
	&"cla": Color(1.00, 1.00, 0.30, 1.0),  # yellow-white
}

# Emission energy per highest-tier band. Soft / medium / heavy.
const TIER_GLOW_ENERGY: Array[float] = [0.0, 0.35, 0.85, 1.6]

var _base_mat: StandardMaterial3D = null
var _current_tiers: Dictionary = {}


func setup(_visual: Node3D, base_mat: StandardMaterial3D) -> void:
	_base_mat = base_mat
	if _base_mat != null:
		_base_mat.emission_enabled = true
		_base_mat.emission = Color.BLACK
		_base_mat.emission_energy_multiplier = 0.0

	for stat_id in AttributeState.ROLLABLE_STATS:
		_current_tiers[stat_id] = 0

	_apply_all_current_tiers()
	PlayerState.tier_changed.connect(_on_tier_changed)


func _on_tier_changed(stat_id: StringName, _old: int, new_tier: int) -> void:
	_current_tiers[stat_id] = new_tier
	_blend_emissive()


func _apply_all_current_tiers() -> void:
	if PlayerState.class_id.is_empty() or PlayerState.spec_id.is_empty():
		return
	for stat_id in AttributeState.ROLLABLE_STATS:
		var tier := AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
		_current_tiers[stat_id] = tier
	_blend_emissive()


# Average colour of all active-tier stats, weighted by the highest tier
# any single stat has reached. Highest tier picks the band (soft/med/heavy).
func _blend_emissive() -> void:
	if _base_mat == null:
		return
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var count := 0
	var max_tier := 0
	for stat_id in _current_tiers:
		var tier: int = int(_current_tiers[stat_id])
		if tier < 1:
			continue
		var col: Color = VFX_STAT_COLORS.get(stat_id, Color.WHITE)
		r += col.r
		g += col.g
		b += col.b
		count += 1
		if tier > max_tier:
			max_tier = tier
	if count == 0:
		_base_mat.emission = Color.BLACK
		_base_mat.emission_energy_multiplier = 0.0
		return
	_base_mat.emission = Color(r / count, g / count, b / count, 1.0)
	var idx := clampi(max_tier, 0, TIER_GLOW_ENERGY.size() - 1)
	_base_mat.emission_energy_multiplier = TIER_GLOW_ENERGY[idx]
