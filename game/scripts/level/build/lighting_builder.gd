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
	# Feed SDFGI's indirect-light pass — fill lights are subtle ambient
	# washes, so even their tiny contribution helps SDFGI find some color
	# to bounce off the back walls of dim rooms.
	light.light_bake_mode = Light3D.BAKE_STATIC
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


# Per-room mesh-based ground fog. A transparent BoxMesh inside the room
# carries the fog_volume.gdshader spatial shader (raymarch + 3D noise);
# Godot's standard transparency depth-test guarantees walls and pillars
# cull any fragment behind them. Replaces the earlier FogVolume approach
# which couldn't be contained because emission + bloom leaked past wall
# edges regardless of bounds.
#
# Box sits just above the floor and stops well below the ceiling — that's
# what makes it read as "ground fog" rather than "the room is full of
# smoke." Bottom inset prevents z-fighting with the floor mesh; top stops
# at FOG_BOX_HEIGHT so the raymarch's vertical fade band is fully inside
# the box (otherwise the ray exits the box before density reaches zero
# and you see a hard mesh edge).
const FOG_BOX_HEIGHT := 0.9
const FOG_BOX_BOTTOM := 0.02

const _FOG_SHADER: Shader = preload("res://scripts/level/build/fog_volume.gdshader")
# One ShaderMaterial shared across every room's fog box. Uniforms set on it
# (density, fog_color, etc.) apply globally — tune once, every room reflects
# the change. If a specific room ever needs custom values, set
# material_override on its MeshInstance3D.
static var _fog_material: ShaderMaterial = null


static func _get_fog_material() -> ShaderMaterial:
	if _fog_material == null:
		_fog_material = ShaderMaterial.new()
		_fog_material.shader = _FOG_SHADER
	return _fog_material


static func create_fog_volume(ctx: LevelBuildContext, center: Vector3, size_x: float, size_z: float) -> void:
	# Inset the box so it stops short of the wall plane on every side. The
	# edge fade in the shader handles the rest — fog dissolves smoothly
	# inside the inset rather than stopping at a hard rectangle.
	const INSET := 0.1
	var box_sx := maxf(size_x - INSET * 2.0, 0.5)
	var box_sz := maxf(size_z - INSET * 2.0, 0.5)
	var box := BoxMesh.new()
	box.size = Vector3(box_sx, FOG_BOX_HEIGHT, box_sz)
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _get_fog_material()
	# Per-instance half-extents drive the shader's edge-fade. Single shared
	# ShaderMaterial; instance uniforms supply the per-room dimensions.
	mi.set_instance_shader_parameter(&"box_half_extents_xz", Vector2(box_sx * 0.5, box_sz * 0.5))
	# Lift the box up by half its height so its bottom sits at FOG_BOX_BOTTOM
	# (slightly above floor y=0).
	mi.transform.origin = Vector3(center.x, FOG_BOX_BOTTOM + FOG_BOX_HEIGHT * 0.5, center.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Don't let SDFGI voxelize the fog as solid geometry — without DISABLED
	# the fog box would carve a wall-shaped hole into the indirect lighting
	# cascade.
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ctx.root.add_child(mi)
	# room_geometry → LoS culler hides the fog when the room is offscreen,
	# saving the per-fragment raymarch on a never-visible room. We
	# previously gated fog on explored state too, but the cut at the
	# doorway between an explored and an unexplored room read worse than
	# just letting fog drift into the next room — the player wants the
	# atmospheric continuity, not a fog-stops-here line.
	mi.add_to_group(&"room_geometry")


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
	# Feed SDFGI so this fluorescent contributes to bounced indirect light.
	# STATIC means the light position/color is baked into the cascade once;
	# the flicker still animates the DIRECT light per-frame, only the
	# (softer, slower-changing) indirect bounce stays cached. Without this,
	# SDFGI sees no light sources in the level and the indirect pass is
	# pitch black, defeating the point of enabling SDFGI.
	light.light_bake_mode = Light3D.BAKE_STATIC
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
