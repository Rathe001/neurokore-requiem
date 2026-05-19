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

const _FOG_SHADER: Shader = preload("res://scripts/level/build/fog_volume.gdshader")
# One shared FogMaterial across every room's FogVolume. ShaderMaterial uniforms
# can be set per-instance via FogVolume.material_override if a specific room
# wants different density/colour later; for now every room reads from the
# same material so tuning is one place.
static var _fog_material: ShaderMaterial = null


static func _get_fog_material() -> ShaderMaterial:
	if _fog_material == null:
		_fog_material = ShaderMaterial.new()
		_fog_material.shader = _FOG_SHADER
	return _fog_material


static func create_fog_volume(ctx: LevelBuildContext, _center: Vector3, _size_x: float, _size_z: float) -> void:
	# Fog parked. The volumetric pipeline (FogVolume + custom fog shader)
	# couldn't deliver "pitch black outside walls" — emission + HDR bloom
	# leaked brightness past wall edges no matter the FogVolume bounds.
	# Re-implementation path is mesh-based: a transparent BoxMesh inside
	# the room with a custom spatial shader doing noise + alpha, where
	# Godot's standard depth-test occlusion guarantees nothing renders
	# behind solid walls.
	return


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
