class_name DoomsayerAura
extends Node3D

# Visual aura for the Enculted Doomsayer perk — a swirl of purple smoke
# puffs around the player. Uses a hand-painted smoke spritesheet
# (assets/effects/smoke.png — 7×7 grid, 46 used frames) as a flipbook
# texture on GPUParticles3D billboards. Each particle plays through the
# smoke frames over its lifetime, giving organic billowing motion that
# would be tedious to fake procedurally. The grayscale smoke is tinted
# purple via the material's albedo_color.
#
# Per-tier scaling drives particle count, scale, and OmniLight3D energy.
# The OmniLight handles the wider purple wash on world surfaces and
# respects walls via shadow casting.

const SMOKE_TEXTURE: Texture2D = preload("res://assets/effects/smoke.png")
const COLOR := Color(0.78, 0.35, 0.85, 1.0)  # AMB stat color (purple)
# Spritesheet layout: 7 columns × 7 rows. Last row only fills 4 cells
# (3 empty), but Godot's particle anim picks frames sequentially so the
# empty cells just render as fully-transparent puffs — invisible filler,
# no visual artifact.
const SPRITE_H_FRAMES := 7
const SPRITE_V_FRAMES := 7

# Per-tier visual scaling. T0 hides everything. Higher tiers spawn more
# puffs from a wider area; the OmniLight scales independently to match
# the skill's per-tier aura radius (so the wash on walls/floor traces
# the actual proc-eligible area).
const PARTICLE_AMOUNT_PER_TIER: Array[int] = [0, 32, 48, 72]
const SPAWN_RADIUS_PER_TIER: Array[float] = [0.0, 1.0, 1.4, 1.8]
const PARTICLE_SCALE_MIN_PER_TIER: Array[float] = [0.0, 1.2, 1.5, 1.8]
const PARTICLE_SCALE_MAX_PER_TIER: Array[float] = [0.0, 2.2, 2.8, 3.5]
const LIGHT_ENERGY_PER_TIER: Array[float] = [0.0, 1.6, 2.8, 4.5]
const LIGHT_RANGE_PER_TIER: Array[float] = [0.0, 5.0, 7.0, 9.0]
const PARTICLE_LIFETIME := 2.5
const SPAWN_OFFSET_Y := 1.0  # spawn around the player's torso, not at feet

var _tier: int = 0
var _particles: GPUParticles3D
var _material: StandardMaterial3D
var _process_mat: ParticleProcessMaterial
var _light: OmniLight3D


func _ready() -> void:
	_build_particles()
	_build_light()
	_apply_tier()


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = &"SmokePuffs"
	_particles.lifetime = PARTICLE_LIFETIME
	# Preprocess so the cloud is "alive" at spawn instead of fading in
	# over the first cycle when the perk first unlocks.
	_particles.preprocess = PARTICLE_LIFETIME * 0.7
	# Particles in local coords follow the player as they move; without
	# this the player would leave a trail of static puffs.
	_particles.local_coords = true
	_particles.position.y = SPAWN_OFFSET_Y
	_particles.amount = PARTICLE_AMOUNT_PER_TIER[3]  # max — set once, modulated per tier via emitting + visibility
	_particles.emitting = false

	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_process_mat.emission_sphere_radius = SPAWN_RADIUS_PER_TIER[1]  # tier-updated in _apply_tier
	# Slow upward drift with wide spread — puffs swirl outward and rise
	# rather than puff straight up. Zero gravity so the cloud stays at
	# torso height instead of sinking.
	_process_mat.direction = Vector3(0.0, 1.0, 0.0)
	_process_mat.spread = 65.0
	_process_mat.initial_velocity_min = 0.2
	_process_mat.initial_velocity_max = 0.6
	_process_mat.gravity = Vector3.ZERO
	_process_mat.damping_min = 0.4
	_process_mat.damping_max = 0.9
	_process_mat.scale_min = PARTICLE_SCALE_MIN_PER_TIER[1]
	_process_mat.scale_max = PARTICLE_SCALE_MAX_PER_TIER[1]
	# Slow per-particle rotation — each puff turns independently for
	# organic motion. Without this every billboard locks to the same
	# orientation and the cloud reads as static.
	_process_mat.angle_min = 0.0
	_process_mat.angle_max = 360.0
	_process_mat.angular_velocity_min = -25.0
	_process_mat.angular_velocity_max = 25.0
	# Flipbook playback — each particle advances through smoke frames
	# over its lifetime. anim_speed = 1 means one full pass through the
	# 49-cell grid in one lifetime; non-loop means it ends on the final
	# frame rather than restarting.
	_process_mat.anim_speed_min = 0.9
	_process_mat.anim_speed_max = 1.1
	# Alpha curve fades each puff in / out over its lifetime so puffs
	# don't pop in or out abruptly when they're born / die.
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 0.0))
	alpha_curve.add_point(Vector2(0.2, 1.0))
	alpha_curve.add_point(Vector2(0.7, 1.0))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	var alpha_tex := CurveTexture.new()
	alpha_tex.curve = alpha_curve
	_process_mat.alpha_curve = alpha_tex
	_particles.process_material = _process_mat

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_material.albedo_texture = SMOKE_TEXTURE
	# Multiplying the grayscale smoke with the purple albedo tints it.
	# The smoke texture's transparency is preserved through the alpha
	# channel multiplied by the alpha_curve above.
	_material.albedo_color = COLOR
	_material.emission_enabled = true
	_material.emission = COLOR
	_material.emission_energy_multiplier = 0.6
	# BILLBOARD_PARTICLES routes the per-particle anim_speed/anim_offset
	# from the ParticleProcessMaterial into the texture sampling so each
	# particle picks the right cell of the flipbook.
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_material.particles_anim_h_frames = SPRITE_H_FRAMES
	_material.particles_anim_v_frames = SPRITE_V_FRAMES
	_material.particles_anim_loop = false
	_material.disable_receive_shadows = true
	quad.material = _material
	_particles.draw_pass_1 = quad
	add_child(_particles)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = &"Spill"
	_light.light_color = COLOR
	_light.light_energy = LIGHT_ENERGY_PER_TIER[0]
	_light.omni_range = LIGHT_RANGE_PER_TIER[0]
	_light.omni_attenuation = 1.6
	# Shadow casting is what gives the OmniLight its "respects walls"
	# behavior — the wash on world surfaces stops at obstacles.
	_light.shadow_enabled = true
	_light.shadow_blur = 1.5
	_light.light_volumetric_fog_energy = 0.0
	_light.position = Vector3(0.0, SPAWN_OFFSET_Y, 0.0)
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
		_particles.visible = on
		_particles.emitting = on
		_particles.amount = maxi(PARTICLE_AMOUNT_PER_TIER[_tier], 1)
	if _process_mat != null and on:
		_process_mat.emission_sphere_radius = SPAWN_RADIUS_PER_TIER[_tier]
		_process_mat.scale_min = PARTICLE_SCALE_MIN_PER_TIER[_tier]
		_process_mat.scale_max = PARTICLE_SCALE_MAX_PER_TIER[_tier]
	if _light != null:
		_light.visible = on
		_light.light_energy = LIGHT_ENERGY_PER_TIER[_tier]
		_light.omni_range = LIGHT_RANGE_PER_TIER[_tier]
