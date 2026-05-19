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
	# Thick ground-cover fog via GPUParticles3D. Each particle is a wide
	# horizontal PlaneMesh disc (~2-3m across) lying flat near the floor.
	# Big sprites + high density + soft radial alpha = continuous ground
	# layer that reads as solid fog rather than scattered puffs.
	#
	# Physics reaction comes from two GPU-particle systems:
	#   1. GPUParticlesAttractorSphere3D on the player (added by
	#      PrototypePlayer._spawn_fog_attractor) parts fog as the player
	#      moves through it.
	#   2. GPUParticlesCollisionBox3D one-per-room-wall (created below)
	#      gives the particles actual collision against the room walls,
	#      so fog can't drift out of the room footprint visibly.
	var p := GPUParticles3D.new()
	p.name = &"GroundFog"
	var area := size_x * size_z
	# High density — big horizontal sprites need to overlap to read as a
	# continuous layer. Clamp upper bound to keep large rooms from going
	# wild.
	p.amount = clampi(int(area * 1.8), 32, 96)
	p.lifetime = 10.0
	p.preprocess = 5.0
	var wh := ctx.theme.wall_height
	# Tight Y range — fog hugs the floor. Generous X/Z so the iso camera
	# doesn't cull at the room edges.
	p.visibility_aabb = AABB(
		Vector3(-size_x * 0.6, -0.1, -size_z * 0.6),
		Vector3(size_x * 1.2, 0.8, size_z * 1.2))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# Emit across the full room footprint at floor level. Thicker slab
	# than wisps (0.15 vs 0.04) so particles span a small Y range and
	# stack visually instead of laying in one plane.
	mat.emission_box_extents = Vector3(size_x * 0.45, 0.15, size_z * 0.45)
	# Very slow drift — fog should look almost still, not actively rising.
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.04
	mat.gravity = Vector3.ZERO
	# Wide discs — overlap each other to form continuous coverage.
	mat.scale_min = 1.8
	mat.scale_max = 3.0
	# Slow horizontal turbulence — particles meander, don't shoot up.
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.15
	mat.turbulence_noise_speed_random = 0.1
	mat.turbulence_noise_speed = Vector3(0.03, 0.01, 0.03)
	# Collision so particles bounce off walls instead of drifting through.
	# Pairs with the GPUParticlesCollisionBox3D nodes spawned below.
	mat.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	mat.collision_bounce = 0.0  # no bounce — particles slide along the wall
	mat.collision_friction = 0.4
	# Fade in fast, hold, fade out slow — keeps density steady through the
	# middle of each particle's life.
	var alpha_gradient := Gradient.new()
	alpha_gradient.set_color(0, Color(1, 1, 1, 0))
	alpha_gradient.set_color(1, Color(1, 1, 1, 0))
	alpha_gradient.add_point(0.1, Color(1, 1, 1, 1))
	alpha_gradient.add_point(0.75, Color(1, 1, 1, 1))
	var alpha_gradient_tex := GradientTexture1D.new()
	alpha_gradient_tex.gradient = alpha_gradient
	mat.color_ramp = alpha_gradient_tex
	p.process_material = mat

	# Soft circular alpha mask — turns the PlaneMesh from a hard rectangle
	# into a fuzzy puff. Each disc's centre is opaque, edges fade out, so
	# overlapping discs blend into continuous coverage.
	var radial := Gradient.new()
	radial.set_color(0, Color(1, 1, 1, 1))
	radial.set_color(1, Color(1, 1, 1, 0))
	radial.add_point(0.5, Color(1, 1, 1, 0.9))
	var radial_tex := GradientTexture2D.new()
	radial_tex.gradient = radial
	radial_tex.fill = GradientTexture2D.FILL_RADIAL
	radial_tex.fill_from = Vector2(0.5, 0.5)
	radial_tex.fill_to = Vector2(1.0, 0.5)
	radial_tex.width = 64
	radial_tex.height = 64

	# PlaneMesh lies flat on XZ by default (normal +Y) — exactly what we
	# want for a ground-cover layer. No billboarding so discs stay
	# horizontal regardless of camera angle.
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	# Higher alpha than the wisp version — user wants thick solid cover.
	# Each disc centre is ~50% opaque; overlapping discs build full thick
	# fog. Edges fade via the radial mask so seams disappear.
	draw_mat.albedo_color = Color(0.58, 0.62, 0.68, 0.5)
	draw_mat.albedo_texture = radial_tex
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.disable_receive_shadows = true
	# Cull off — flat discs viewed from above need both sides visible if
	# the camera ever tilts below.
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = draw_mat
	p.draw_pass_1 = mesh

	p.transform.origin = center
	ctx.root.add_child(p)
	p.add_to_group(&"room_geometry")

	# Per-wall GPUParticlesCollisionBox3D — the "reacts to physics" piece.
	# Four walls per room, each a thin box just outside the room footprint.
	# Particles colliding with these boxes can't drift past the wall plane,
	# so the fog stays inside the room visually no matter how strong the
	# turbulence is. (Regular CollisionShape3D bodies don't affect GPU
	# particles — the GPU pipeline needs dedicated collision nodes.)
	_create_fog_walls(ctx, center, size_x, size_z, wh)


static func _create_fog_walls(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float, wh: float) -> void:
	# `extents` for GPUParticlesCollisionBox3D is half-size. The walls sit
	# OUTSIDE the room (at +/- half-size + a small margin) and are thin in
	# the perpendicular axis, tall enough to clip rising particles too.
	var hx: float = size_x * 0.5
	var hz: float = size_z * 0.5
	var thin: float = 0.05
	var height: float = wh * 0.5
	var configs: Array[Dictionary] = [
		{"pos": Vector3(0, height * 0.5, -hz), "ext": Vector3(hx, height, thin)},  # N
		{"pos": Vector3(0, height * 0.5,  hz), "ext": Vector3(hx, height, thin)},  # S
		{"pos": Vector3( hx, height * 0.5, 0), "ext": Vector3(thin, height, hz)},  # E
		{"pos": Vector3(-hx, height * 0.5, 0), "ext": Vector3(thin, height, hz)},  # W
	]
	for cfg in configs:
		var collider := GPUParticlesCollisionBox3D.new()
		collider.size = cfg["ext"] * 2.0  # `size` is full, our extents are half
		collider.position = center + cfg["pos"]
		ctx.root.add_child(collider)
		collider.add_to_group(&"room_geometry")


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
