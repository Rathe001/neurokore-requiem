class_name DoomsayerAura
extends Node3D

# Visual aura for the Enculted Doomsayer perk — a purple miasma that
# surrounds the player while the perk is active. PrototypePlayer creates
# one on _ready and parents it to the visual root; tier updates come
# through set_tier() driven by PerkState.perks_changed.
#
# Tier readout:
#   T0 — invisible (perk not active)
#   T1 — thin haze + dim purple ambient light
#   T2 — visible cloud, brighter spill
#   T3 — heavy miasma, dramatic purple light radius
#
# Particles are billboarded quads with a procedurally-built radial
# gradient texture so each one renders as a soft circular wisp instead
# of a hard square. MIX blend (not additive) gives the "vapor" look the
# perk's flavor calls for; the OmniLight3D handles the actual purple
# glow against the world. Depth-write disabled so overlapping wisps
# blend cleanly instead of punching holes in each other.

const COLOR := Color(0.78, 0.35, 0.85, 1.0)  # AMB stat color (purple)

# Per-tier visual scaling. Index 0 is "off." Particle amount stays at
# T3's max so tier transitions don't restart the system (which would
# pop visibly); we modulate alpha + emission energy + light spill
# instead. Alpha values are higher than they look — the soft-edged
# texture means most of each particle's pixels are already partly
# transparent, so the centre alpha needs headroom to read.
const PARTICLE_AMOUNT_T3 := 220
const ALPHA_PER_TIER: Array[float] = [0.0, 0.32, 0.52, 0.78]
const EMISSION_PER_TIER: Array[float] = [0.0, 0.4, 0.8, 1.4]
const LIGHT_ENERGY_PER_TIER: Array[float] = [0.0, 0.9, 1.7, 3.0]
const LIGHT_RANGE_PER_TIER: Array[float] = [0.0, 5.5, 7.5, 10.0]

# Spawn volume around the player. Larger than the original 2.4m to
# read as a proper aura presence (still smaller than the actual
# DOOMSAYER_AURA_RADIUS = 9m effect range — the miasma signals "you're
# in dread territory" without trying to be a precise rangefinder).
const SPAWN_RADIUS := 5.0
const PARTICLE_LIFETIME := 5.5
# Quad base size. Final on-screen size is QUAD_SIZE × scale_curve ×
# scale_min/max — kept smaller than the old 0.7 so individual wisps
# don't read as tiles when the camera's close.
const PARTICLE_QUAD_SIZE := 0.5
# Soft circular gradient texture dimensions — small is fine, GPU
# samples this every fragment.
const TEXTURE_SIZE := 64

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
	_particles.preprocess = PARTICLE_LIFETIME * 0.7
	# local_coords = true keeps particles attached to the player as they
	# move; otherwise the player would leave a trail of static wisps
	# (which reads as smoke trail, not as a personal aura).
	_particles.local_coords = true
	_particles.emitting = false

	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_mat.emission_sphere_radius = SPAWN_RADIUS
	# Slow upward drift with wide spread — wisps swirl rather than puff
	# straight up. Gravity zero so the cloud doesn't sink off the floor.
	process_mat.direction = Vector3(0.0, 1.0, 0.0)
	process_mat.spread = 50.0
	process_mat.initial_velocity_min = 0.05
	process_mat.initial_velocity_max = 0.30
	process_mat.gravity = Vector3.ZERO
	process_mat.damping_min = 0.3
	process_mat.damping_max = 0.7
	# Per-particle scale jitter — variety stops the cloud from looking
	# like a uniform sphere of identical sprites.
	process_mat.scale_min = 0.5
	process_mat.scale_max = 1.6
	# Slow per-particle rotation. Each wisp spins independently, which
	# breaks up the "all sprites locked to the same axis" look.
	process_mat.angle_min = 0.0
	process_mat.angle_max = 360.0
	process_mat.angular_velocity_min = -45.0
	process_mat.angular_velocity_max = 45.0
	# Scale curve gives the wisp a soft fade-in / fade-out shape — born
	# tiny, balloon out, shrink back as they die.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.2))
	scale_curve.add_point(Vector2(0.35, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.6))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	process_mat.scale_curve = scale_tex
	# Alpha curve fades in / hold / fades out — multiplied with the
	# material's albedo alpha (which we modulate per tier).
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 0.0))
	alpha_curve.add_point(Vector2(0.2, 1.0))
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
	# MIX (default) blend reads as vapor; the previous ADD blend made
	# every wisp look like a fluorescent decal. Light spill from the
	# OmniLight3D below is what makes the cloud feel "glowy" — particles
	# themselves are diffuse purple smoke.
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	# Without this, overlapping transparent quads write to depth and
	# punch holes in each other (visible as hard rectangular cutouts —
	# exactly the artefact in the original screenshot).
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[0])
	_material.albedo_texture = _build_radial_texture()
	_material.emission_enabled = true
	_material.emission = COLOR
	_material.emission_energy_multiplier = EMISSION_PER_TIER[0]
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.billboard_keep_scale = true
	_material.disable_receive_shadows = true
	mesh.material = _material
	_particles.draw_pass_1 = mesh
	add_child(_particles)


# Procedural radial gradient — opaque white in the centre, fading to
# fully transparent at the edge of the quad. Used as albedo_texture so
# each particle renders as a soft circular wisp instead of a hard
# square. Built once at _ready; the texture itself is colored by the
# material's albedo_color (which carries the purple tint).
func _build_radial_texture() -> Texture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.55),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	# fill_to at radius=0.5 means the gradient covers exactly the quad's
	# half-width — edge of the gradient lands at the edge of the quad.
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = TEXTURE_SIZE
	tex.height = TEXTURE_SIZE
	return tex


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
