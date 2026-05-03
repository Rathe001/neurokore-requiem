class_name DoomsayerAura
extends Node3D

# Visual aura for the Enculted Doomsayer perk — a purple miasma that
# surrounds the player while the perk is active. PrototypePlayer creates
# one on _ready and parents it to the visual root; tier updates come
# through set_tier() driven by PerkState.perks_changed.
#
# Tier readout:
#   T0 — invisible (perk not active)
#   T1 — subtle wisps + faint purple ambient light
#   T2 — moderate haze, more particles, brighter light
#   T3 — heavy purple miasma, dramatic light radius
#
# Built from a GPUParticles3D (the actual miasma) plus a low-energy
# OmniLight3D for ambient color spill on nearby surfaces. The light
# matters more than people expect — particles alone read as a flat
# decal in the dark prototype zones; the spill anchors the miasma to
# the world so it feels embedded rather than overlaid.

const COLOR := Color(0.78, 0.35, 0.85, 1.0)  # AMB stat color (purple)

# Per-tier visual scaling. Index 0 is "off." Particle amount needs a
# system restart to apply, so we max out at T3's value and modulate
# alpha + emission energy to fade lower tiers — restart only happens
# on actual tier crossings.
const PARTICLE_AMOUNT_T3 := 80
const ALPHA_PER_TIER: Array[float] = [0.0, 0.18, 0.32, 0.55]
const EMISSION_PER_TIER: Array[float] = [0.0, 0.7, 1.4, 2.6]
const LIGHT_ENERGY_PER_TIER: Array[float] = [0.0, 0.6, 1.3, 2.4]
const LIGHT_RANGE_PER_TIER: Array[float] = [0.0, 4.0, 6.0, 8.0]

# Particles drift outward from the player at this max distance, slowly
# rising. Smaller than DOOMSAYER_AURA_RADIUS (9m) on purpose — the
# aura's effect range is invisible, the miasma just signals presence.
const SPAWN_RADIUS := 2.4
const PARTICLE_LIFETIME := 4.0
const PARTICLE_QUAD_SIZE := 0.7

var _tier: int = 0
var _particles: GPUParticles3D
var _material: StandardMaterial3D
var _light: OmniLight3D


func _ready() -> void:
	_build_particles()
	_build_light()
	_apply_tier()


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = &"Miasma"
	_particles.amount = PARTICLE_AMOUNT_T3
	_particles.lifetime = PARTICLE_LIFETIME
	# Preprocess so the aura is "already alive" at spawn instead of
	# fading in over the first lifetime cycle when the perk first unlocks.
	_particles.preprocess = PARTICLE_LIFETIME * 0.6
	# local_coords = true keeps particles attached to the player as they
	# move; otherwise the player would leave a trail of static wisps
	# (which reads as smoke, not as a personal aura).
	_particles.local_coords = true
	_particles.emitting = false

	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_mat.emission_sphere_radius = SPAWN_RADIUS
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 35.0
	process_mat.initial_velocity_min = 0.15
	process_mat.initial_velocity_max = 0.45
	process_mat.gravity = Vector3.ZERO
	process_mat.damping_min = 0.2
	process_mat.damping_max = 0.5
	process_mat.scale_min = 0.6
	process_mat.scale_max = 1.4
	# Particles fade out over their lifetime via alpha curve; the ramp
	# also pulses scale slightly so the miasma feels like it's breathing.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.4))
	scale_curve.add_point(Vector2(0.4, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.7))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	process_mat.scale_curve = scale_tex
	# Alpha curve: fade in from 0, hold, fade out. Multiplied with the
	# material's albedo alpha (which we modulate per tier).
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 0.0))
	alpha_curve.add_point(Vector2(0.25, 1.0))
	alpha_curve.add_point(Vector2(0.75, 1.0))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	var alpha_tex := CurveTexture.new()
	alpha_tex.curve = alpha_curve
	process_mat.alpha_curve = alpha_tex
	_particles.process_material = process_mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(PARTICLE_QUAD_SIZE, PARTICLE_QUAD_SIZE)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[0])
	_material.emission_enabled = true
	_material.emission = COLOR
	_material.emission_energy_multiplier = EMISSION_PER_TIER[0]
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.billboard_keep_scale = true
	# No depth write because additive transparent particles overlap in
	# layers — without this they punch holes in each other.
	_material.disable_receive_shadows = true
	mesh.material = _material
	_particles.draw_pass_1 = mesh
	add_child(_particles)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = &"Spill"
	_light.light_color = COLOR
	_light.light_energy = LIGHT_ENERGY_PER_TIER[0]
	_light.omni_range = LIGHT_RANGE_PER_TIER[0]
	_light.omni_attenuation = 2.0
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 0.0
	_light.position = Vector3(0.0, 1.2, 0.0)
	add_child(_light)


# Public API — PrototypePlayer calls this on perks_changed with the
# unlocked AMB tier (0..3). T0 hides everything; T1+ scales visibility.
func set_tier(t: int) -> void:
	var clamped := clampi(t, 0, 3)
	if clamped == _tier:
		return
	_tier = clamped
	_apply_tier()


func _apply_tier() -> void:
	var on := _tier > 0
	if _particles != null:
		_particles.emitting = on
		_particles.visible = on
	if _material != null:
		_material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[_tier])
		_material.emission_energy_multiplier = EMISSION_PER_TIER[_tier]
	if _light != null:
		_light.visible = on
		_light.light_energy = LIGHT_ENERGY_PER_TIER[_tier]
		_light.omni_range = LIGHT_RANGE_PER_TIER[_tier]
