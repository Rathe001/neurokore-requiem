extends RefCounted
class_name LightingBuilder
## Light placement: ceiling fluorescents (with rolled flicker profile),
## per-piece fill lights, and FPS-mode fog configuration.
##
## Pit lights (ooze glow / spike rim / pillar markers) live in PitBuilder
## because they're tightly coupled to the pit geometry that produces them.

const CEILING_CLEARANCE := 0.1
const CEILING_LIGHT_ENERGY_MIN := 4.0
const CEILING_LIGHT_ENERGY_MAX := 11.0
const CEILING_LIGHT_RANGE_MIN := 9.0
const CEILING_LIGHT_RANGE_MAX := 14.0
const CEILING_LIGHT_ATTENUATION := 1.3


static func place_room_fluorescents(ctx: LevelBuildContext, center: Vector3, rd: RoomDef) -> void:
	var lc := rd.light_color
	if lc == null:
		return
	var y := ctx.theme.wall_height - CEILING_CLEARANCE
	_create_ceiling_light(ctx, center + Vector3(0, y, 0), lc)


static func place_corridor_fluorescents(ctx: LevelBuildContext, center: Vector3, cd: CorridorDef) -> void:
	var lc := cd.light_color
	if lc == null or cd.light_interval <= 0.0:
		return
	var y := ctx.theme.wall_height - CEILING_CLEARANCE
	var hl := cd.length * 0.5
	var along_z := cd.axis == CorridorDef.Axis.Z

	var v := -hl + cd.light_interval * 0.5
	while v < hl:
		var pos: Vector3
		if along_z:
			pos = Vector3(center.x, y, center.z + v)
		else:
			pos = Vector3(center.x + v, y, center.z)
		_create_ceiling_light(ctx, pos, lc)
		v += cd.light_interval


# Per-piece soft fill light — a low-intensity omni at chest height that
# lifts the room out of total darkness without competing with the
# fluorescents for visual focus.
static func create_fill_light(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.55, 0.7)
	light.light_energy = 0.15
	light.omni_range = maxf(size_x, size_z) * 0.6
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	light.transform.origin = center + Vector3(0, 2.0, 0)
	ctx.root.add_child(light)
	# room_geometry → LoS culler hides this light when the room is 2+ hops
	# away from the player. Light3D.visible = false fully disables the light
	# (no shadow cubemap render, no contribution to lit pixels), so the cost
	# of "all rooms lit at once" drops to "only adjacent rooms lit at once".
	light.add_to_group(&"room_geometry")


# Pre-configures WorldEnvironment fog from the theme so the FPS-mode toggle
# only needs to flip fog_enabled — density and color are already correct.
static func configure_fps_fog(ctx: LevelBuildContext) -> void:
	var t := ctx.theme
	var we_node := ctx.root.get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we_node == null or we_node.environment == null:
		return
	var env := we_node.environment
	env.fog_enabled = false
	env.fog_light_color = t.fps_fog_color
	env.fog_density = t.fps_fog_density


# Per-room FogVolume — low-lying "dry ice" fog that hugs the floor.
# A thin slab (FOG_HEIGHT) sitting at floor level gives the dungeon a
# ground-mist look without filling the room with smoke.
# The iso camera sits at y≈14 looking nearly straight down. A thin slab
# has almost no optical depth from that angle. Two stacked layers fake a
# density gradient: a dense thin slab on the floor for the FPS view, and
# a taller, softer layer above it that gives the iso camera enough depth
# to accumulate visible fog while staying visually floor-weighted.
const FOG_FLOOR_HEIGHT := 0.15
const FOG_FLOOR_DENSITY := 6.0
const FOG_HAZE_HEIGHT := 0.5
const FOG_HAZE_DENSITY := 1.5

static func create_fog_volume(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float) -> void:
	# Per-room ground fog via GPUParticles3D. Replaced FogVolume + volumetric
	# pass because the volumetric approach lit the ceiling fluorescents'
	# scatter through wall edges (visible as a "halo" outside rooms). Each
	# particle is a Y-axis billboarded soft puff emitted in a thin slab near
	# the floor, drifting slowly upward and outward — emission stays inside
	# the room footprint and lifetimes are short enough that drift doesn't
	# cross walls visibly. PrototypePlayer adds a GPUParticlesAttractorSphere3D
	# child in _ready(), so the fog visibly parts as the player moves.
	#
	# Iso-camera notes:
	# - BILLBOARD_FIXED_Y keeps sprites VERTICAL (rotating only around Y to
	#   face camera). BILLBOARD_PARTICLES would tilt them flat on the floor
	#   under the near-top-down view, reading as opaque floor tiles.
	# - SHADING_MODE_UNSHADED so the fog isn't lit by the high-energy
	#   fluorescent omnis (lighting it = bright white, no matter how low
	#   the albedo alpha is).
	# - Radial alpha mask via GradientTexture2D (FILL_RADIAL) softens each
	#   sprite into a puff rather than a hard rectangle.
	var p := GPUParticles3D.new()
	p.name = &"GroundFog"
	var area := size_x * size_z
	p.amount = clampi(int(area * 0.9), 18, 48)
	p.lifetime = 7.0
	# Pre-roll a chunk of the lifecycle so the room doesn't fade in from
	# nothing when the player arrives.
	p.preprocess = 4.0
	var wh := ctx.theme.wall_height
	p.visibility_aabb = AABB(
		Vector3(-size_x * 0.6, 0.0, -size_z * 0.6),
		Vector3(size_x * 1.2, wh * 0.5, size_z * 1.2))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Thin emission slab at floor level, spanning ~90% of the room footprint.
	mat.emission_box_extents = Vector3(size_x * 0.45, 0.04, size_z * 0.45)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.02
	mat.initial_velocity_max = 0.08
	mat.gravity = Vector3.ZERO
	# Small vertical cards — fog reads as a layered haze when many small
	# soft puffs overlap, not when a few big cards stack.
	mat.scale_min = 0.5
	mat.scale_max = 0.9
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.35
	mat.turbulence_noise_speed_random = 0.2
	mat.turbulence_noise_speed = Vector3(0.05, 0.02, 0.05)
	# Fade in over the first 20% of life, hold, fade out over the last 30%.
	var alpha_gradient := Gradient.new()
	alpha_gradient.set_color(0, Color(1, 1, 1, 0))
	alpha_gradient.set_color(1, Color(1, 1, 1, 0))
	alpha_gradient.add_point(0.2, Color(1, 1, 1, 1))
	alpha_gradient.add_point(0.7, Color(1, 1, 1, 1))
	var alpha_gradient_tex := GradientTexture1D.new()
	alpha_gradient_tex.gradient = alpha_gradient
	mat.color_ramp = alpha_gradient_tex
	p.process_material = mat

	# Soft circular alpha mask via radial gradient — turns the QuadMesh
	# from a hard rectangle into a fuzzy puff without needing a texture
	# asset or custom shader.
	var radial := Gradient.new()
	radial.set_color(0, Color(1, 1, 1, 1))
	radial.set_color(1, Color(1, 1, 1, 0))
	var radial_tex := GradientTexture2D.new()
	radial_tex.gradient = radial
	radial_tex.fill = GradientTexture2D.FILL_RADIAL
	radial_tex.fill_from = Vector2(0.5, 0.5)
	radial_tex.fill_to = Vector2(1.0, 0.5)
	radial_tex.width = 64
	radial_tex.height = 64

	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	# Cool grey-blue. Alpha is the final multiplier on the radial mask, so
	# the effective opacity at sprite centre is this value; edges fade to 0.
	draw_mat.albedo_color = Color(0.55, 0.60, 0.66, 0.22)
	draw_mat.albedo_texture = radial_tex
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.disable_receive_shadows = true
	mesh.material = draw_mat
	p.draw_pass_1 = mesh

	p.transform.origin = center
	ctx.root.add_child(p)
	p.add_to_group(&"room_geometry")


# Per-room ambient dust particles — subtle floating motes that catch the
# light and sell "atmosphere". Low count, slow drift, long lifetime so
# they're always present without burning fill rate.
static func create_room_particles(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float) -> void:
	var p := GPUParticles3D.new()
	# Scale count with room area but cap to avoid GPU pressure in large rooms.
	var area := size_x * size_z
	p.amount = clampi(int(area * 0.3), 6, 32)
	p.lifetime = 12.0
	# Generous AABB so the iso camera (y=14, looking down) doesn't cull.
	var wh := ctx.theme.wall_height
	p.visibility_aabb = AABB(
		Vector3(-size_x, -wh, -size_z),
		Vector3(size_x * 2.0, wh * 3.0, size_z * 2.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(size_x * 0.45, wh * 0.4, size_z * 0.45)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.01
	mat.initial_velocity_max = 0.04
	mat.gravity = Vector3(0, -0.005, 0)
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	# Subtle turbulence so motes drift lazily, not straight-line.
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.2
	mat.turbulence_noise_speed_random = 0.15
	mat.turbulence_noise_speed = Vector3(0.05, 0.03, 0.05)
	p.process_material = mat
	# QuadMesh billboard — always faces camera, reads clearly from iso view.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.02, 0.02)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.albedo_color = Color(0.85, 0.85, 0.75, 0.2)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = draw_mat
	p.draw_pass_1 = mesh
	p.transform.origin = center + Vector3(0, wh * 0.5, 0)
	ctx.root.add_child(p)
	# room_geometry → hidden when the room is 2+ hops from the player.
	# GPUParticles3D stops drawing AND stops simulating when visibility
	# inherits as false, so offscreen rooms cost nothing.
	p.add_to_group(&"room_geometry")


# ── internals ────────────────────────────────────────────────────────────

static func _create_ceiling_light(ctx: LevelBuildContext, pos: Vector3, lc: LightColor) -> void:
	var fixture := FluorescentFlicker.new()
	fixture.position = pos

	var light := OmniLight3D.new()
	light.light_color = lc.color
	light.light_energy = randf_range(CEILING_LIGHT_ENERGY_MIN, CEILING_LIGHT_ENERGY_MAX)
	light.omni_range = randf_range(CEILING_LIGHT_RANGE_MIN, CEILING_LIGHT_RANGE_MAX)
	light.omni_attenuation = CEILING_LIGHT_ATTENUATION
	light.shadow_enabled = lc.shadows
	# Tighter bias than Godot's 0.02 default. With CEILING_LIGHT_ENERGY_MAX
	# at 11 and walls ~0.2m thick, the default bias was wide enough that
	# the cubemap depth comparison let some light through the wall plane,
	# visible as the OUTER wall surface reading lit. 0.005 closes that
	# gap. Normal bias also halved — at 0.5 we were pushing the receiver
	# plane half the wall thickness out into the wall, which made the
	# leak worse, not better.
	light.shadow_bias = 0.005
	light.shadow_normal_bias = 0.5
	# Was 0.4 — even with the global env's volumetric_fog_enabled = false,
	# the per-room FogVolumes still received this energy and scattered it
	# across screen pixels. Camera rays passing through fog (or near a
	# FogVolume's edge) picked up the scatter, producing a diagonal V-shaped
	# halo extending from room corners into the void. Setting to 0 means
	# the ceiling fluorescents don't contribute to volumetric fog at all;
	# the room mist still gets its base density from the FogVolume itself
	# but won't be lit by these lights.
	light.light_volumetric_fog_energy = 0.0
	fixture.add_child(light)

	_randomize_flicker_profile(fixture)
	fixture.setup(light, null)
	ctx.root.add_child(fixture)
	# room_geometry → hidden when the room is 2+ hops from the player. The
	# child OmniLight3D's visibility inherits from the fixture, so the
	# shadow-cubemap render and light contribution both disappear when the
	# room is offscreen — the biggest perf lever at multi-room scale.
	fixture.add_to_group(&"room_geometry")


# Roll a flicker profile per fixture: most lights are steady, some twitch
# subtly, a few are outright broken with fast / deep flickers.
static func _randomize_flicker_profile(fixture: FluorescentFlicker) -> void:
	var roll := randf()
	if roll < 0.6:
		fixture.flicker_chance = 0.0
		return
	if roll < 0.9:
		# Minor twitch — rare, subtle, fairly quick.
		fixture.flicker_chance = randf_range(0.003, 0.012)
		fixture.flicker_depth = randf_range(0.15, 0.35)
		fixture.flicker_duration = randf_range(0.04, 0.1)
		return
	# Broken — frequent, deep, and varied durations.
	fixture.flicker_chance = randf_range(0.03, 0.08)
	fixture.flicker_depth = randf_range(0.5, 0.85)
	fixture.flicker_duration = randf_range(0.06, 0.22)
