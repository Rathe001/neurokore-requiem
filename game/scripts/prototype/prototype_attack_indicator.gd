class_name PrototypeAttackIndicator
extends RefCounted

const GROUND_OFFSET := 0.02
const FADE_DURATION := 0.15
const CONE_SEGMENTS := 20
const DISK_SEGMENTS := 48
const PLAYER_COLOR := Color(0.3, 0.7, 1.0)
const ENEMY_COLOR := Color(1.0, 0.2, 0.15)

# Shockwave hit FX. Both variants use a screen-space refraction shader — no
# color tint, just a heat-ripple-like warp of whatever's behind. Radial uses an
# expanding sphere centered on the host. Cone uses a hemispherical wedge whose
# apex sits at the host and whose arc opens forward across the swing's cone,
# so the wavefront reads as a directional blast rather than a 360° bubble.
const SHOCKWAVE_DURATION_RADIAL := 0.50
const SHOCKWAVE_DURATION_CONE := 0.36
const SHOCKWAVE_START_SCALE := 0.06
const SHOCKWAVE_BUBBLE_DISTORTION := 0.10
const SHOCKWAVE_BUBBLE_CHROMA := 0.014
const SHOCKWAVE_BUBBLE_RIM := 0.25
const SHOCKWAVE_BUBBLE_LIFT := 0.05      # origin slightly above ground
const CONE_DOME_RINGS := 10
const CONE_DOME_SEGMENTS := 24
const SHOCKWAVE_BUBBLE_SHADER: Shader = preload("res://scripts/prototype/shockwave_bubble.gdshader")

# Lightning arc visual — a flat plane stretched between two world points
# running the lightning_arc.gdshader. Used by chain-lightning weapons
# (Charged Arc Taser) for both per-link visuals and the held-channel
# tase. Thin enough that the iso camera reads it as a horizontal bolt
# at chest height; the FBM displacement in the shader gives the
# centerline its jagged-arc shape so we don't need geometry per zigzag.
const LIGHTNING_ARC_SHADER: Shader = preload("res://scripts/prototype/lightning_arc.gdshader")

# Shared unit-size PlaneMesh for every lightning arc — instances are
# scaled per-spawn instead of allocating a new mesh each tick. Built
# lazily on first arc spawn. Held-channel chain attacks (Taser hold)
# spawn an arc every 0.15s; with 4 players × 2 arcs/tick this saved
# ~50 PlaneMesh allocations/sec.
static var _lightning_arc_mesh: PlaneMesh = null
# Templated ShaderMaterial duplicated per-instance. Duplicating a
# pre-resolved material is cheaper than constructing from scratch
# because the shader pointer + param defaults are already set on the
# template — duplicate() does a shallow copy of param values into a
# new material instance ready for per-arc tween animation.
static var _lightning_arc_material_template: ShaderMaterial = null


static func _get_lightning_arc_mesh() -> PlaneMesh:
	if _lightning_arc_mesh == null:
		_lightning_arc_mesh = PlaneMesh.new()
		# Unit size — actual arc dimensions come from inst.scale at spawn.
		# Width = 1 along local X (link direction); height = 1 along Y.
		_lightning_arc_mesh.size = Vector2(1.0, 1.0)
		_lightning_arc_mesh.orientation = PlaneMesh.FACE_Z
	return _lightning_arc_mesh


static func _get_lightning_arc_material_template() -> ShaderMaterial:
	if _lightning_arc_material_template == null:
		_lightning_arc_material_template = ShaderMaterial.new()
		_lightning_arc_material_template.shader = LIGHTNING_ARC_SHADER
	return _lightning_arc_material_template
# Vertical extent of the lightning plane (in world units). The shader's
# amp_start controls how far the centerline zigzags within the plane,
# and core_radius controls how thick the visible bolt is — so plane
# height needs to be large enough that the FBM displacement doesn't
# clip at the plane edges. 1.0m + amp_start 0.6 gives ~30cm of
# zigzag amplitude with a ~4cm-thick bolt.
const LIGHTNING_ARC_HEIGHT := 0.6
# Arc lifetime — keep slightly under the held-channel tick_interval
# (0.15s) so each tick replaces the previous arc cleanly. Longer
# durations created a "trail" effect: a new arc spawning from the
# player's current position while the previous arc was still visible
# at the position the player held a moment ago, especially when the
# player was strafing during the channel.
const LIGHTNING_ARC_DURATION := 0.12

# Mesh cache: cone outlines keyed by Vector2(range, cone_deg),
# disk outlines keyed by float(range). ArrayMesh resources are
# shareable across MeshInstance3D, so a small set of unique
# (radius, angle) combinations keeps telegraph spawns allocation-free.
static var _cone_cache: Dictionary = {}
static var _disk_cache: Dictionary = {}
static var _line_cache: Dictionary = {}
static var _bubble_mesh_cache: Dictionary = {}
static var _cone_dome_cache: Dictionary = {}
static var _material_template_cache: Dictionary = {}  # Color -> StandardMaterial3D template
# Beam cylinder mesh caches keyed by length — two radii (core / glow).
static var _beam_core_mesh_cache: Dictionary = {}
static var _beam_glow_mesh_cache: Dictionary = {}
# Beam material templates keyed by Color — duplicated per use for tween animation.
static var _beam_core_mat_cache: Dictionary = {}
static var _beam_glow_mat_cache: Dictionary = {}
# Reusable pool of OmniLight3D for impact/beam/explosion effects. Avoids
# creating hundreds of light nodes per frame during horde-scale combat.
static var _light_pool: Array[OmniLight3D] = []
const _LIGHT_POOL_MAX := 32

static func _acquire_light() -> OmniLight3D:
	if not _light_pool.is_empty():
		return _light_pool.pop_back()
	return OmniLight3D.new()


static func _release_light(light: OmniLight3D) -> void:
	if not is_instance_valid(light):
		return
	if light.get_parent() != null:
		light.get_parent().remove_child(light)
	light.light_energy = 0.0
	if _light_pool.size() < _LIGHT_POOL_MAX:
		_light_pool.append(light)
	else:
		light.queue_free()


static func spawn(host: Node3D, skill: Skill, aim: Vector3, attack_range: float = 0.0) -> void:
	var eff_range := attack_range if attack_range > 0.0 else skill.skill_range
	# Airstrike skills (Tactical Strike) skip the directional line
	# telegraph in favour of an X marker painted on the floor at the
	# cursor target. The marker appears immediately on input — it has
	# to outlast the windup AND the rocket's fall time, so its lifetime
	# is computed from the skill, not the windup alone.
	if skill.is_airstrike:
		spawn_airstrike_marker(host, skill, eff_range)
		return
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			spawn_cone(host, aim, eff_range, skill.cone_deg, skill.wind_up)
		Skill.TargetingMode.AOE_RADIAL:
			spawn_radial(host, eff_range, skill.wind_up)
		Skill.TargetingMode.PROJECTILE:
			spawn_line(host, aim, eff_range, skill.wind_up)
		Skill.TargetingMode.HITSCAN:
			spawn_line(host, aim, eff_range, skill.wind_up)


const MARKER_SHADER: Shader = preload("res://scripts/prototype/airstrike_marker.gdshader")
# Airstrike marker dimensions. Plane is square; size is fixed across
# all casts so we can share one PlaneMesh instance rather than
# allocating per-cast. Per-marker variation lives in the per-instance
# ShaderMaterial (tweened intensity).
const AIRSTRIKE_MARKER_PLANE_SIZE: float = 3.2

# Shared PlaneMesh for every airstrike marker — every cast reuses this
# one mesh. The material can't be shared (per-instance intensity tween)
# but is duplicated from a pre-resolved template, which is cheaper than
# constructing one from scratch.
static var _airstrike_marker_mesh: PlaneMesh = null
static var _airstrike_marker_material_template: ShaderMaterial = null


static func _get_airstrike_marker_mesh() -> PlaneMesh:
	if _airstrike_marker_mesh == null:
		_airstrike_marker_mesh = PlaneMesh.new()
		_airstrike_marker_mesh.size = Vector2(
			AIRSTRIKE_MARKER_PLANE_SIZE, AIRSTRIKE_MARKER_PLANE_SIZE)
	return _airstrike_marker_mesh


static func _get_airstrike_marker_material_template() -> ShaderMaterial:
	if _airstrike_marker_material_template == null:
		_airstrike_marker_material_template = ShaderMaterial.new()
		_airstrike_marker_material_template.shader = MARKER_SHADER
		# Constant params — every cast wants the same color / bar width /
		# alpha; only intensity varies per-cast (tweened). Setting these
		# on the template means duplicate() carries them and per-cast
		# code only writes the param that changes.
		_airstrike_marker_material_template.set_shader_parameter(
			&"marker_color", Vector3(1.0, 0.25, 0.05))
		_airstrike_marker_material_template.set_shader_parameter(
			&"bar_width", 0.10)
		_airstrike_marker_material_template.set_shader_parameter(
			&"max_alpha", 0.30)
	return _airstrike_marker_material_template


# Paints a glowing red "X" decal on the floor at the cursor target,
# auto-frees it after the cast resolves. Runs at click time (before the
# windup await), so the player sees where the strike will land BEFORE
# the rocket spawns. Two crossed flat boxes give the X shape; emission
# is low so the marker reads as a paint, not a beacon.
static func spawn_airstrike_marker(host: Node3D, skill: Skill, eff_range: float) -> void:
	# Not gated on _telegraphs_enabled — the airstrike X is a target
	# paint shown to the firing player, not an enemy windup warning,
	# so it's part of the cast feedback, not the telegraph debug
	# toggle. The toggle still suppresses cone/line/radial telegraphs.
	# Resolve the strike point on the host's ground plane via cursor.
	# Falls back to the host's facing if the host doesn't expose a
	# cursor (FPS / lock-target / non-player hosts that ever try this).
	var ground: Vector3
	if host.has_method(&"cursor_world_position"):
		var cursor_pos: Vector3 = host.call(&"cursor_world_position")
		var origin := host.global_position
		if cursor_pos == origin:
			var facing := -host.global_transform.basis.z
			facing.y = 0.0
			if facing.length_squared() < 0.0001:
				facing = Vector3.FORWARD
			ground = origin + facing.normalized() * eff_range
		else:
			var to_target := cursor_pos - origin
			to_target.y = 0.0
			if to_target.length() > eff_range:
				to_target = to_target.normalized() * eff_range
			ground = origin + to_target
		ground.y = origin.y
	else:
		var facing2 := -host.global_transform.basis.z
		facing2.y = 0.0
		if facing2.length_squared() < 0.0001:
			facing2 = Vector3.FORWARD
		ground = host.global_position + facing2.normalized() * eff_range
	# Single horizontal PlaneMesh with an X shader — reads as paint on
	# the floor regardless of camera angle. Replaces the previous
	# crossed-BoxMesh slabs which had vertical thickness and caught
	# iso-camera perspective as 3D objects. Mesh is shared across all
	# casts; material is per-instance (intensity is tweened) but
	# duplicated from a pre-resolved template.
	var mat: ShaderMaterial = _get_airstrike_marker_material_template().duplicate()
	mat.set_shader_parameter(&"intensity", 1.4)
	var node := MeshInstance3D.new()
	node.name = "AirstrikeMarker"
	node.mesh = _get_airstrike_marker_mesh()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.get_parent().add_child(node)
	# PlaneMesh is in the X-Z plane by default — perfect for a floor
	# decal. Lift slightly above the floor surface so depth-test
	# doesn't z-fight with the floor mesh, but small enough that the
	# camera reads it as flush.
	node.global_position = ground + Vector3(0.0, 0.04, 0.0)
	# Lifetime covers windup (rocket hasn't spawned yet) + fall time
	# (rocket falling from the sky) + a small buffer so the marker
	# survives through the explosion frame.
	var fall_time: float = skill.airstrike_fall_height / maxf(skill.projectile_speed, 0.001)
	var lifetime: float = skill.wind_up + fall_time + 0.25
	# Pulse intensity so the X reads as an active target paint instead
	# of a static decal. The kill tween auto-frees the node when its
	# job is done; the loop tween is auto-killed when the node is freed.
	var pulse := node.create_tween()
	pulse.tween_property(mat, "shader_parameter/intensity", 2.4, 0.35)
	pulse.tween_property(mat, "shader_parameter/intensity", 1.4, 0.35)
	pulse.set_loops(int(ceil(lifetime / 0.7)) + 1)
	var killer := node.create_tween()
	killer.tween_interval(lifetime)
	killer.tween_callback(node.queue_free)

static func spawn_cone(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float, wind_up: float = 0.0) -> void:
	if not _telegraphs_enabled():
		return
	var node := MeshInstance3D.new()
	node.mesh = _cone_mesh(attack_range, cone_deg)
	var mat := _build_material(_color_for_host(host))
	node.material_override = mat
	host.add_child(node)
	node.position = Vector3(0.0, GROUND_OFFSET, 0.0)
	if aim.length_squared() > 0.0001:
		node.look_at(node.global_position + aim, Vector3.UP)
	_play_fade(node, mat, wind_up)

static func spawn_radial(host: Node3D, radius: float, wind_up: float = 0.0) -> void:
	if not _telegraphs_enabled():
		return
	var node := MeshInstance3D.new()
	node.mesh = _disk_mesh(radius)
	var mat := _build_material(_color_for_host(host))
	node.material_override = mat
	host.add_child(node)
	node.position = Vector3(0.0, GROUND_OFFSET, 0.0)
	_play_fade(node, mat, wind_up)

static func spawn_line(host: Node3D, aim: Vector3, attack_range: float, wind_up: float = 0.0) -> void:
	if not _telegraphs_enabled():
		return
	var node := MeshInstance3D.new()
	node.mesh = _line_mesh(attack_range)
	var mat := _build_material(_color_for_host(host))
	node.material_override = mat
	host.add_child(node)
	node.position = Vector3(0.0, GROUND_OFFSET, 0.0)
	if aim.length_squared() > 0.0001:
		node.look_at(node.global_position + aim, Vector3.UP)
	_play_fade(node, mat, wind_up)

## Instant hitscan beam: a glowing cylinder from the host along aim for `length`
## units, detached into world space so it stays put while the host moves.
## Fades quickly (no wind-up phase).
const BEAM_RADIUS := 0.012
const BEAM_FADE := 0.18

## Spawn a lightning arc between two world points using the FBM
## lightning shader. The arc is a PlaneMesh oriented camera-facing —
## its normal points at the active 3D camera, its long axis follows
## the link direction (projected onto the plane perpendicular to the
## camera-look direction), and its short axis is computed orthogonal.
## This keeps the bolt visible from any camera angle, even when the
## chain link runs nearly parallel to the camera's view direction.
## Fades out over `duration` via the shader's `intensity` uniform.
static func spawn_lightning_arc(host: Node3D, from_pos: Vector3, to_pos: Vector3, duration: float = LIGHTNING_ARC_DURATION, tint_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var link := to_pos - from_pos
	var length := link.length()
	if length < 0.05:
		return
	var midpoint := (from_pos + to_pos) * 0.5
	# Camera-facing orientation. host.is_inside_tree() guards against the
	# anchor pattern used by MP RPC — a freshly-made anchor may not be
	# in the tree yet when the spawn fires deferred.
	var camera: Camera3D = null
	if host.is_inside_tree():
		camera = host.get_viewport().get_camera_3d()
	var to_camera := Vector3.UP
	if camera != null:
		to_camera = camera.global_position - midpoint
		if to_camera.length_squared() < 0.0001:
			to_camera = Vector3.UP
		else:
			to_camera = to_camera.normalized()
	# Project link direction onto plane perpendicular to to_camera.
	# Long axis lives in that plane and tracks the link as closely as
	# possible without breaking orthogonality with the normal.
	var link_dir := link / length
	var long_axis := link_dir - to_camera * link_dir.dot(to_camera)
	if long_axis.length_squared() < 0.0001:
		# Link runs parallel to camera direction (rare; e.g. zoomed
		# straight down on a vertical link). Pick an arbitrary axis
		# perpendicular to to_camera so the basis stays valid.
		long_axis = Vector3.RIGHT - to_camera * to_camera.x
		if long_axis.length_squared() < 0.0001:
			long_axis = Vector3.FORWARD - to_camera * to_camera.z
	long_axis = long_axis.normalized()
	var height_axis := to_camera.cross(long_axis).normalized()
	# Use the shared unit-size PlaneMesh and scale per-instance instead
	# of allocating a new PlaneMesh every spawn. ShaderMaterial is still
	# per-instance (intensity tween is unique per arc) but duplicated
	# from a pre-resolved template, which is cheaper than constructing
	# from scratch.
	var mat: ShaderMaterial = _get_lightning_arc_material_template().duplicate()
	mat.set_shader_parameter(&"intensity", 1.0)
	# Pass world-space plane length so the shader's FBM repeats per
	# world unit instead of stretching to fit the plane. Without this,
	# long arcs read as low-frequency smeared shapes; short arcs as
	# tight buzzes. With it, every arc has consistent per-meter detail.
	mat.set_shader_parameter(&"plane_length", length)
	# Elemental tint — when the firing weapon has a damage_type, the
	# bolt color matches it (electric=violet, cryo=cyan, etc). Zero
	# alpha = "no override" and the shader's authored default cyan-blue
	# stays in effect. The shader wants a vec3 so we drop the alpha
	# channel after the override check.
	if tint_override.a > 0.0:
		mat.set_shader_parameter(&"effect_color", Vector3(tint_override.r, tint_override.g, tint_override.b))
	var inst := MeshInstance3D.new()
	inst.mesh = _get_lightning_arc_mesh()
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	inst.global_position = midpoint
	# Basis columns are the new local axes in world space. The unit
	# mesh is 1×1; scaling along the basis axes by length / arc-height
	# stretches it to the actual arc dimensions while keeping the basis
	# orthonormal for the rotation.
	#   local +X = long_axis   (along link, projected onto camera plane)
	#   local +Y = height_axis (orthogonal, in camera plane)
	#   local +Z = to_camera   (plane normal points at the camera)
	inst.basis = Basis(long_axis * length, height_axis * LIGHTNING_ARC_HEIGHT, to_camera)
	# Linear fade — EASE_OUT held the arc bright for most of its duration
	# and only dropped at the end, so overlapping arcs from successive
	# channel ticks looked like a persistent multi-arc smear. Linear
	# clears the previous arc smoothly across the full duration.
	var tween := inst.create_tween()
	tween.tween_property(mat, "shader_parameter/intensity", 0.0, duration)
	tween.tween_callback(inst.queue_free)


static func spawn_beam(host: Node3D, aim: Vector3, length: float, source_offset: Vector3 = Vector3.ZERO, tint_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	# tint_override with non-zero alpha overrides the host's class
	# color — used for elemental weapons (flame red, cryo cyan, etc.)
	# so the beam reads as the weapon's element regardless of player
	# class. Zero-alpha = "no override" and falls back to class color.
	var color := tint_override if tint_override.a > 0.0 else _color_for_host(host)

	# Core beam — bright, slightly transparent cylinder. Mesh cached by length.
	var core_mat := _beam_core_material(color)
	var core := MeshInstance3D.new()
	core.mesh = _beam_core_mesh(length)
	core.material_override = core_mat

	# Outer glow — wider, softer, more transparent. Mesh cached by length.
	var glow_mat := _beam_glow_material(color)
	var glow := MeshInstance3D.new()
	glow.mesh = _beam_glow_mesh(length)
	glow.material_override = glow_mat

	# Container node — cylinder height runs along local Y, so rotate -90° on X
	# to align with local -Z (the look_at forward), then offset by half length.
	var node := Node3D.new()
	parent.add_child(node)
	# source_offset shifts the beam origin (right / left / above) for Forged
	# Amalgamation extras so the visual emerges from the same point as the
	# damage origin in PlayerCombat._resolve_hitscan.
	node.global_position = host.global_position + Vector3(0.0, 1.0, 0.0) + source_offset
	if aim.length_squared() > 0.0001:
		node.look_at(node.global_position + aim, Vector3.UP)

	core.rotation.x = deg_to_rad(-90.0)
	core.position.z = -length * 0.5
	glow.rotation.x = deg_to_rad(-90.0)
	glow.position.z = -length * 0.5
	node.add_child(core)
	node.add_child(glow)

	# Point light at the impact end so walls / floors near the hit catch a
	# brief glow — matches the visual contract the projectile already has
	# (see prototype_projectile.tscn's Glow OmniLight3D). No shadows because
	# the beam lives <0.2s; volumetric fog disabled to keep horde-firing cheap.
	var impact_light := _acquire_light()
	impact_light.light_color = color
	impact_light.light_energy = 2.5
	impact_light.omni_range = 4.0
	impact_light.omni_attenuation = 2.0
	impact_light.shadow_enabled = false
	impact_light.light_volumetric_fog_energy = 0.0
	impact_light.position = Vector3(0.0, 0.0, -length)
	node.add_child(impact_light)

	# Mid-beam light so the entire laser line illuminates nearby geometry,
	# not just the impact point. Placed at the beam's midpoint with a
	# wider range to cover the full corridor.
	var mid_light := _acquire_light()
	mid_light.light_color = color
	mid_light.light_energy = 1.8
	mid_light.omni_range = 3.0
	mid_light.omni_attenuation = 2.0
	mid_light.shadow_enabled = false
	mid_light.light_volumetric_fog_energy = 0.0
	mid_light.position = Vector3(0.0, 0.0, -length * 0.5)
	node.add_child(mid_light)

	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(core_mat, "albedo_color:a", 0.0, BEAM_FADE).set_ease(Tween.EASE_IN)
	tween.tween_property(glow_mat, "albedo_color:a", 0.0, BEAM_FADE).set_ease(Tween.EASE_IN)
	tween.tween_property(core_mat, "emission_energy_multiplier", 0.0, BEAM_FADE)
	tween.tween_property(glow_mat, "emission_energy_multiplier", 0.0, BEAM_FADE)
	tween.tween_property(impact_light, "light_energy", 0.0, BEAM_FADE).set_ease(Tween.EASE_IN)
	tween.tween_property(mid_light, "light_energy", 0.0, BEAM_FADE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_release_light.bind(impact_light))
	tween.chain().tween_callback(_release_light.bind(mid_light))
	tween.chain().tween_callback(node.queue_free)

# Brief impact flash spawned at a hit point — small emissive sphere that
# scales up as it fades, plus a short-lived OmniLight so nearby surfaces
# catch the burst. Used by projectile collisions and hitscan target hits.
# `color_override` opts in to a specific tint; pass Color() (zero alpha) to
# fall back to _color_for_host so player shots stay class-colored.
const IMPACT_DURATION := 0.22
const IMPACT_RADIUS_START := 0.18
const IMPACT_RADIUS_END := 0.55

static var _impact_mesh_cache: SphereMesh = null

static func _get_impact_mesh() -> SphereMesh:
	if _impact_mesh_cache != null:
		return _impact_mesh_cache
	var m := SphereMesh.new()
	m.radius = IMPACT_RADIUS_START
	m.height = IMPACT_RADIUS_START * 2.0
	m.radial_segments = 12
	m.rings = 6
	_impact_mesh_cache = m
	return m

static func spawn_impact_burst(host: Node3D, world_pos: Vector3, color_override: Color = Color(0, 0, 0, 0)) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var color := color_override
	if color.a == 0.0:
		color = _color_for_host(host)

	var mat := _build_material(color)
	mat.albedo_color.a = 0.95

	var inst := MeshInstance3D.new()
	inst.mesh = _get_impact_mesh()
	inst.material_override = mat
	parent.add_child(inst)
	inst.global_position = world_pos

	var light := _acquire_light()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 3.5
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	inst.add_child(light)

	var scale_target := IMPACT_RADIUS_END / IMPACT_RADIUS_START
	var tween := inst.create_tween().set_parallel(true)
	tween.tween_property(inst, "scale", Vector3.ONE * scale_target, IMPACT_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(mat, "albedo_color:a", 0.0, IMPACT_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, IMPACT_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_property(light, "light_energy", 0.0, IMPACT_DURATION).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_release_light.bind(light))
	tween.chain().tween_callback(inst.queue_free)

# AoE explosion burst — like spawn_impact_burst but scaled to a blast_radius.
# Two visual paths:
#   • Color-tinted (energy weapon AoE) — keeps the legacy translucent-bubble
#     shell that reads as "expanding force field". This is the path
#     plasma-charged shots etc. take.
#   • No tint (kinetic / RPG / grenade explosions) — runs the procedural
#     fireball shader: yellow-white core, orange mid, red rim, FBM
#     turbulence, fades to smoke. This is the new path the user asked
#     for, inspired by the flipbook explosion VFX shader at
#     https://godotshaders.com/shader/3d-explosion-vfx/ but reworked
#     to be procedural so it doesn't need the source's seven sprite
#     sheets.
const EXPLOSION_DURATION := 0.8
# Spark + flash layers run alongside the flipbook for the "impact
# moment" punch — the flipbook itself handles fireball + smoke phases
# internally over its own ~2s sprite-sheet lifetime, so we don't need
# a separate procedural smoke layer.
const EXPLOSION_SPARK_LIFETIME := 0.45
const EXPLOSION_FLASH_DURATION: float = 0.18
# Lifetime of the flipbook GPUParticles3D scene before we queue_free
# its instance. Matches the BigExplosionScene's particle lifetime
# (2.13s) plus a small tail so trailing frames have time to finish.
const EXPLOSION_FLIPBOOK_LIFETIME: float = 2.6
# The BigExplosionScene was authored at roughly this blast radius —
# we scale the instantiated scene by (blast_radius / this) so smaller
# grenades produce smaller flipbooks instead of full-screen kabooms.
const FLIPBOOK_BASE_RADIUS: float = 3.0
const FLIPBOOK_EXPLOSION_SCENE: PackedScene = preload("res://assets/vfx/explosion/BigExplosionScene.tscn")

# Elemental palettes for the procedural fireball. Each entry gives the
# four shader color uniforms (core / mid / outer / smoke) plus the
# omni-light tint. Passing weapon.damage_type as the lookup key picks
# the right palette; unknown types fall back to the kinetic default.
# Colors are picked to read at-a-glance at iso distance — high contrast
# between core/outer, smoke chosen to land on a darker version of the
# same hue so the fade feels like the same explosion winding down
# rather than swapping colors.
const FIREBALL_PALETTES: Dictionary = {
	&"": {  # kinetic / no element — orange fireball, the default
		"core": Color(1.0, 0.95, 0.7),
		"mid": Color(1.0, 0.5, 0.10),
		"outer": Color(0.65, 0.15, 0.05),
		"smoke": Color(0.18, 0.16, 0.14),
		"light": Color(1.0, 0.55, 0.15),
	},
	&"flame": {  # explicit fire — same look as kinetic
		"core": Color(1.0, 0.95, 0.7),
		"mid": Color(1.0, 0.5, 0.10),
		"outer": Color(0.65, 0.15, 0.05),
		"smoke": Color(0.18, 0.16, 0.14),
		"light": Color(1.0, 0.55, 0.15),
	},
	&"cryo": {  # ice burst — white-blue core, cyan mid, deep blue rim
		"core": Color(0.95, 0.98, 1.0),
		"mid": Color(0.5, 0.85, 1.0),
		"outer": Color(0.15, 0.4, 0.7),
		"smoke": Color(0.15, 0.18, 0.25),
		"light": Color(0.55, 0.85, 1.0),
	},
	&"electric": {  # arc burst — white-yellow core, violet mid, deep purple rim
		"core": Color(1.0, 1.0, 0.85),
		"mid": Color(0.85, 0.6, 1.0),
		"outer": Color(0.4, 0.2, 0.7),
		"smoke": Color(0.18, 0.15, 0.22),
		"light": Color(0.85, 0.6, 1.0),
	},
}

static func spawn_explosion(host: Node3D, world_pos: Vector3, blast_radius: float, color_override: Color = Color(0, 0, 0, 0), damage_type: StringName = &"") -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	# Branch on whether the caller provided an explicit color. Kinetic
	# explosions (RPG, grenades) pass no color → procedural fireball.
	# Energy explosions (plasma-charged, future energy AoE) pass their
	# class accent → translucent bubble shell. damage_type only
	# matters for the fireball path — picks an elemental palette.
	if color_override.a == 0.0:
		_spawn_fireball_explosion(parent, world_pos, blast_radius, damage_type)
	else:
		_spawn_energy_explosion(parent, world_pos, blast_radius, color_override)


## Flipbook-driven explosion using the BigExplosionScene's pre-baked
## 8×8 sprite-sheet (smokesprite.png) + normal maps for lighting. The
## scene itself owns the GPUParticles3D and the material's UV
## animation; we just instantiate it, scale to blast radius, and
## stack the supporting layers (omni light, sparks, instant flash) on
## top. The flipbook includes its own smoke-dispersal phase as the
## sprite ages, so we don't spawn a separate procedural smoke layer.
static func _spawn_fireball_explosion(parent: Node, world_pos: Vector3, blast_radius: float, damage_type: StringName = &"") -> void:
	var palette: Dictionary = FIREBALL_PALETTES.get(damage_type, FIREBALL_PALETTES[&""])

	var fx: Node3D = FLIPBOOK_EXPLOSION_SCENE.instantiate() as Node3D
	parent.add_child(fx)
	fx.global_position = world_pos
	# The scene was authored for ~FLIPBOOK_BASE_RADIUS m blasts. Scale
	# the whole node so smaller grenades produce smaller flipbooks
	# instead of dominating the screen. Clamped so chip-scale AoEs
	# don't shrink the effect to invisibility and so a giant Tactical
	# Strike doesn't fill the entire viewport.
	fx.scale = Vector3.ONE * clampf(blast_radius / FLIPBOOK_BASE_RADIUS, 0.4, 2.0)
	# Auto-cleanup once the flipbook lifetime + tail expires. Particle
	# system stops emitting at ~2.13s; tail gives trailing frames time
	# to finish their UV animation before we yank the node.
	fx.get_tree().create_timer(EXPLOSION_FLIPBOOK_LIFETIME).timeout.connect(fx.queue_free)

	# Omni light pulse — surrounding floor / walls / enemies light up
	# in the explosion's color. Two-stage fade: peak holds briefly at
	# 40, drops to a sustained glow at 14 over 0.15s, then trails to
	# zero. light_volumetric_fog_energy carries a quarter of the
	# brightness into any in-room fog so dense rooms get a colored
	# haze without overpowering them.
	var light := _acquire_light()
	light.light_color = palette["light"]
	light.light_energy = 40.0
	light.omni_range = blast_radius * 3.5
	light.omni_attenuation = 0.9
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.25
	fx.add_child(light)

	var light_tween := fx.create_tween()
	light_tween.tween_property(light, "light_energy", 14.0, 0.15).set_ease(Tween.EASE_OUT)
	light_tween.chain()
	light_tween.tween_property(light, "light_energy", 0.0, EXPLOSION_DURATION).set_ease(Tween.EASE_IN)
	light_tween.chain().tween_callback(_release_light.bind(light))

	# Instant flash sphere — bright unshaded white-hot pop that
	# precedes the flipbook's first visible frame. Reads as the
	# detonation flash at iso distance even when the flipbook quads
	# haven't fully oriented to camera yet.
	_spawn_explosion_flash(parent, world_pos, blast_radius, palette["core"])
	# Sparks — bright radial dots flying outward, short lifetime, low
	# gravity. Reads as flying debris / hot fragments.
	_spawn_explosion_sparks(parent, world_pos, blast_radius, palette["mid"])


# Instant white-hot pop at the impact point — separate from the
# fireball shader so it's guaranteed to register even if the shader's
# fresnel + age fade hides the orange ball at certain angles. Sphere
# uses an unshaded high-emission StandardMaterial so it bloom-glows
# regardless of palette or volumetric fog density.
static func _spawn_explosion_flash(parent: Node, world_pos: Vector3, blast_radius: float, core_tint: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = blast_radius * 0.35
	mesh.height = blast_radius * 0.7
	mesh.radial_segments = 16
	mesh.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(core_tint.r, core_tint.g, core_tint.b, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = core_tint
	mat.emission_energy_multiplier = 6.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Start small so it pops into existence, scale up + fade fast.
	inst.scale = Vector3.ONE * 0.3
	parent.add_child(inst)
	inst.global_position = world_pos
	var tween := inst.create_tween().set_parallel(true)
	tween.tween_property(inst, "scale", Vector3.ONE * 1.4, EXPLOSION_FLASH_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(mat, "albedo_color:a", 0.0, EXPLOSION_FLASH_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, EXPLOSION_FLASH_DURATION).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(inst.queue_free)


# Bright outward-spraying spark particles. One-shot burst sized to the
# blast radius. Particles don't follow the parent so they survive the
# fireball mesh's queue_free.
static func _spawn_explosion_sparks(parent: Node, world_pos: Vector3, blast_radius: float, tint: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = clampi(int(round(blast_radius * 6.0)), 12, 48)
	particles.lifetime = EXPLOSION_SPARK_LIFETIME
	particles.explosiveness = 1.0
	particles.local_coords = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = blast_radius * 0.15
	pm.direction = Vector3(0.0, 0.3, 0.0)
	pm.spread = 180.0  # full radial spray
	pm.initial_velocity_min = blast_radius * 5.0
	pm.initial_velocity_max = blast_radius * 9.0
	pm.gravity = Vector3(0.0, -12.0, 0.0)
	pm.damping_min = 6.0
	pm.damping_max = 10.0
	pm.scale_min = 0.04
	pm.scale_max = 0.10
	pm.color = Color(tint.r, tint.g, tint.b, 1.0)
	# Scale curve fades the spark to nothing — saves a separate alpha tween.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.5))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	particles.process_material = pm

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	particles.draw_pass_1 = mesh

	# Add to tree BEFORE setting global_position — the setter walks the
	# scene tree to convert into local coords, so doing it pre-parent
	# trips "!is_inside_tree()" and silently leaves the node at origin.
	parent.add_child(particles)
	particles.global_position = world_pos
	# Cleanup after the burst — lifetime is short, but pad so the tail
	# fully fades.
	particles.get_tree().create_timer(EXPLOSION_SPARK_LIFETIME + 0.2).timeout.connect(particles.queue_free)


# Energy-weapon AoE — keeps the existing translucent-bubble look that
# reads as "expanding force field" for charged plasma, future arc /
# beam AoEs, etc. Carries the caller's color through both the bubble
# and the omni-light.
static func _spawn_energy_explosion(parent: Node, world_pos: Vector3, blast_radius: float, color: Color) -> void:
	var start_radius := blast_radius * 0.15
	var end_radius := blast_radius * 0.7

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED

	var mesh := SphereMesh.new()
	mesh.radius = start_radius
	mesh.height = start_radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12

	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	parent.add_child(inst)
	inst.global_position = world_pos

	var light := _acquire_light()
	light.light_color = color
	light.light_energy = 6.0
	light.omni_range = blast_radius * 1.5
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	inst.add_child(light)

	var scale_target := end_radius / start_radius
	var tween := inst.create_tween().set_parallel(true)
	tween.tween_property(inst, "scale", Vector3.ONE * scale_target, EXPLOSION_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(mat, "albedo_color:a", 0.0, EXPLOSION_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, EXPLOSION_DURATION * 0.8).set_ease(Tween.EASE_IN)
	tween.tween_property(light, "light_energy", 0.0, EXPLOSION_DURATION).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_release_light.bind(light))
	tween.chain().tween_callback(inst.queue_free)


static func spawn_hit_cone(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float) -> void:
	var forward := Vector3(aim.x, 0.0, aim.z)
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = -host.global_transform.basis.z
	var pos := host.global_position + Vector3(0.0, SHOCKWAVE_BUBBLE_LIFT, 0.0)
	_spawn_shockwave(host, pos, _cone_dome_mesh(attack_range, cone_deg), forward, SHOCKWAVE_DURATION_CONE)

static func spawn_hit_radial(host: Node3D, radius: float) -> void:
	var pos := host.global_position + Vector3(0.0, SHOCKWAVE_BUBBLE_LIFT, 0.0)
	_spawn_shockwave(host, pos, _bubble_mesh(radius), Vector3.ZERO, SHOCKWAVE_DURATION_RADIAL)


# ── Hammer ground-impact ring (2H hammer step-2 finisher visual) ────────────
# Floor-flat ring that sweeps outward from the player's feet. Drawn on
# a unit-disc PlaneMesh with hammer_impact.gdshader; the shader animates
# via the `progress` uniform which the host tweens 0..1. Stacks on top
# of the regular shockwave cone for the step-2 finisher so the cone
# reads as the swing and the ring reads as the ground impact.

const HAMMER_IMPACT_SHADER: Shader = preload("res://scripts/prototype/hammer_impact.gdshader")
const HAMMER_IMPACT_DURATION: float = 0.35
const HAMMER_IMPACT_RING_COLOR := Color(1.0, 0.7, 0.3, 1.0)
# Ring grows out to this radius from the player. Sized to cover the
# typical 2H hammer cone reach (~3-4m).
const HAMMER_IMPACT_RADIUS: float = 4.0
# Lift the ring barely above floor so it doesn't z-fight with the
# floor mesh. Matches the airstrike marker's offset.
const HAMMER_IMPACT_FLOOR_LIFT: float = 0.04

static var _hammer_impact_mesh: PlaneMesh = null
static var _hammer_impact_material_template: ShaderMaterial = null


static func _get_hammer_impact_mesh() -> PlaneMesh:
	if _hammer_impact_mesh == null:
		_hammer_impact_mesh = PlaneMesh.new()
		# 2 × radius for unit-disc UV mapping: world-space size becomes
		# (2*radius, 2*radius), giving the shader a UV space where the
		# unit circle is the full visible ring.
		var d := HAMMER_IMPACT_RADIUS * 2.0
		_hammer_impact_mesh.size = Vector2(d, d)
	return _hammer_impact_mesh


static func _get_hammer_impact_material_template() -> ShaderMaterial:
	if _hammer_impact_material_template == null:
		_hammer_impact_material_template = ShaderMaterial.new()
		_hammer_impact_material_template.shader = HAMMER_IMPACT_SHADER
		_hammer_impact_material_template.set_shader_parameter(
			&"ring_color", Vector3(HAMMER_IMPACT_RING_COLOR.r, HAMMER_IMPACT_RING_COLOR.g, HAMMER_IMPACT_RING_COLOR.b))
		_hammer_impact_material_template.set_shader_parameter(&"intensity", 3.5)
		_hammer_impact_material_template.set_shader_parameter(&"thickness", 0.08)
		_hammer_impact_material_template.set_shader_parameter(&"max_alpha", 0.85)
		_hammer_impact_material_template.set_shader_parameter(&"progress", 0.0)
	return _hammer_impact_material_template


static func spawn_hammer_impact(host: Node3D) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var mat: ShaderMaterial = _get_hammer_impact_material_template().duplicate()
	mat.set_shader_parameter(&"progress", 0.0)
	var inst := MeshInstance3D.new()
	inst.mesh = _get_hammer_impact_mesh()
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	# Position at the host's feet, just above the floor surface.
	inst.global_position = host.global_position + Vector3(0.0, HAMMER_IMPACT_FLOOR_LIFT, 0.0)
	# Tween progress 0 → 1 over the duration. Shader does the animation
	# math; we just supply the time variable.
	var tween := inst.create_tween()
	tween.tween_property(mat, "shader_parameter/progress", 1.0, HAMMER_IMPACT_DURATION) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_callback(inst.queue_free)


# ── Footstep dust puffs ─────────────────────────────────────────────────────
# Footstep dust puff. Triggered by PrototypePlayer every FOOTSTEP_DISTANCE
# meters of movement (per-player; remote peers' avatars also tick locally,
# so no RPC). Implemented as a one-shot CPUParticles3D burst of small
# billboarded quads with a soft-circle gradient texture. Each particle
# rises slightly off the ground and drifts outward as it fades — reads
# as kicked-up dust rather than a painted disc.

const FOOTSTEP_LIFETIME: float = 0.35
const FOOTSTEP_PARTICLE_COUNT: int = 4
# Albedo tint — warm dust, barely-there. Should register subconsciously
# without drawing the eye away from combat.
const FOOTSTEP_BASE_COLOR := Color(0.85, 0.80, 0.68, 0.22)
const FOOTSTEP_LIFT: float = 0.06

# Shared resources — generated once, reused across every footstep spawn.
# The texture is a 64×64 soft radial gradient that gives each billboarded
# particle a smooth disc silhouette instead of a visible square. The
# material's BILLBOARD_PARTICLES mode orients each quad toward the camera
# at render time so the dust always reads as facing the viewer.
static var _footstep_quad_mesh: QuadMesh = null
static var _footstep_material: StandardMaterial3D = null
static var _footstep_texture: ImageTexture = null
static var _footstep_color_ramp: Gradient = null


static func _get_footstep_texture() -> ImageTexture:
	if _footstep_texture != null:
		return _footstep_texture
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size) * 0.5, float(size) * 0.5)
	var max_r := float(size) * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(float(x), float(y)).distance_to(center) / max_r
			var a: float = 0.0
			if d < 1.0:
				# Soft falloff — pow shapes the gradient so the disc is
				# mostly translucent with a slightly stronger center.
				# Exponent 2.5 keeps the edge feathery without going
				# fully transparent in the middle.
				a = pow(1.0 - d, 2.5)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_footstep_texture = ImageTexture.create_from_image(img)
	return _footstep_texture


static func _get_footstep_quad_mesh() -> QuadMesh:
	if _footstep_quad_mesh == null:
		_footstep_quad_mesh = QuadMesh.new()
		_footstep_quad_mesh.size = Vector2(1.0, 1.0)
	return _footstep_quad_mesh


static func _get_footstep_material() -> StandardMaterial3D:
	if _footstep_material == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.albedo_color = FOOTSTEP_BASE_COLOR
		mat.albedo_texture = _get_footstep_texture()
		_footstep_material = mat
	return _footstep_material


static func _get_footstep_color_ramp() -> Gradient:
	if _footstep_color_ramp == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.6))
		g.set_color(1, Color(1, 1, 1, 0))
		g.set_offset(0, 0.0)
		g.set_offset(1, 1.0)
		_footstep_color_ramp = g
	return _footstep_color_ramp


static func spawn_footstep_puff(parent: Node3D, world_pos: Vector3) -> void:
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.amount = FOOTSTEP_PARTICLE_COUNT
	p.lifetime = FOOTSTEP_LIFETIME
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.mesh = _get_footstep_quad_mesh()
	p.material_override = _get_footstep_material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Emit from a small disc just above the foot, biased upward but
	# with enough spread that particles fan out around the step rather
	# than rocketing straight up.
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = 0.06
	p.direction = Vector3(0, 1, 0)
	p.spread = 65.0
	p.flatness = 0.6
	p.initial_velocity_min = 0.12
	p.initial_velocity_max = 0.30
	p.gravity = Vector3(0, -0.2, 0)
	p.damping_min = 2.0
	p.damping_max = 3.5
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.10
	p.color_ramp = _get_footstep_color_ramp()
	# Set position BEFORE add_child so the transform is resolved
	# correctly on tree entry — setting global_position post-add can
	# read stale parent transforms and place the emitter at the origin.
	p.top_level = true
	p.position = world_pos + Vector3(0.0, FOOTSTEP_LIFT, 0.0)
	parent.add_child(p)
	p.emitting = true
	# Free the node once the burst has finished. lifetime + small grace
	# so the very last frame renders before tear-down.
	var t := p.create_tween()
	t.tween_interval(FOOTSTEP_LIFETIME + 0.15)
	t.tween_callback(p.queue_free)


# ── Blade slash (1H knife / melee_1h hit visual) ────────────────────────────
# Procedural arced slash drawn by blade_slash.gdshader on a flat plane
# oriented to face the camera. Replaces the prior box-mesh approach
# which read as rectangles from the iso angle. The shader handles the
# curve + taper + glow falloff; host code positions + scales + tweens
# `intensity` from full to 0 over SLASH_DURATION.

const SLASH_SHADER: Shader = preload("res://scripts/prototype/blade_slash.gdshader")
const SLASH_DURATION: float = 0.20
# Half-height of the bow box relative to chord length. The shader's
# arc reaches `curvature` of UV space (-1..1), so the world-space
# bow needs proportional vertical headroom.
const SLASH_BOW_RATIO: float = 0.35
const SLASH_INTENSITY: float = 6.0
# Diagonal tilt of the slash chord, in degrees away from horizontal.
# Lifts the +X end of the chord up so the cut reads as a diagonal
# saber stroke (down-left → up-right) instead of a flat horizontal line.
const SLASH_TILT_DEG: float = 22.0

# Shared unit-square PlaneMesh — every slash uses this one mesh,
# scaled per spawn. ShaderMaterial is per-instance (intensity is
# tweened individually) but duplicated from a pre-resolved template.
static var _slash_mesh: PlaneMesh = null
static var _slash_material_template: ShaderMaterial = null


static func _get_slash_mesh() -> PlaneMesh:
	if _slash_mesh == null:
		_slash_mesh = PlaneMesh.new()
		_slash_mesh.size = Vector2(1.0, 1.0)
		# FACE_Z so the plane's normal is its local +Z; host orients the
		# inst so +Z faces the camera and the slash is fully visible.
		_slash_mesh.orientation = PlaneMesh.FACE_Z
	return _slash_mesh


static func _get_slash_material_template() -> ShaderMaterial:
	if _slash_material_template == null:
		_slash_material_template = ShaderMaterial.new()
		_slash_material_template.shader = SLASH_SHADER
	return _slash_material_template


static func spawn_blade_slash(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float) -> void:
	if host == null:
		return
	var forward := Vector3(aim.x, 0.0, aim.z)
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = -host.global_transform.basis.z
	# For the wide combo-finisher cone (>=180°) spawn 3 angled slashes
	# so the omni-sweep reads as multiple cuts. Otherwise just one
	# slash centred on the cone bisector.
	if cone_deg >= 180.0:
		_spawn_one_slash(host, forward.rotated(Vector3.UP, deg_to_rad(-55.0)), attack_range * 0.7, cone_deg * 0.4)
		_spawn_one_slash(host, forward, attack_range * 0.75, cone_deg * 0.5)
		_spawn_one_slash(host, forward.rotated(Vector3.UP, deg_to_rad(55.0)), attack_range * 0.7, cone_deg * 0.4)
	else:
		_spawn_one_slash(host, forward, attack_range * 0.75, cone_deg)


static func _spawn_one_slash(host: Node3D, forward: Vector3, mid_dist: float, cone_deg: float) -> void:
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	# Chord length at mid_dist for the given cone width. Adds a small
	# minimum so very narrow cones still produce a visible streak.
	var chord: float = maxf(0.8, 2.0 * mid_dist * sin(deg_to_rad(cone_deg * 0.5)))
	var bow: float = chord * SLASH_BOW_RATIO
	# Camera-facing orientation. The plane's normal points at the
	# camera so the procedural arc is fully visible; the chord axis is
	# whichever in-plane direction best matches "horizontal-perpendicular
	# to the swing", tilted SLASH_TILT_DEG for the saber-stroke feel.
	var camera: Camera3D = null
	if host.is_inside_tree():
		camera = host.get_viewport().get_camera_3d()
	var midpoint: Vector3 = host.global_position + forward * mid_dist + Vector3(0.0, 1.0, 0.0)
	var to_camera := Vector3.UP
	if camera != null:
		to_camera = camera.global_position - midpoint
		if to_camera.length_squared() < 0.0001:
			to_camera = Vector3.UP
		else:
			to_camera = to_camera.normalized()
	# Project the "horizontal-perpendicular to aim" axis onto the plane
	# perpendicular to to_camera so the basis stays orthonormal AND the
	# slash chord runs across the swing direction as expected.
	var horizontal_right := Vector3.UP.cross(forward)
	if horizontal_right.length_squared() < 0.0001:
		horizontal_right = Vector3.RIGHT
	horizontal_right = horizontal_right.normalized()
	var chord_axis: Vector3 = horizontal_right - to_camera * horizontal_right.dot(to_camera)
	if chord_axis.length_squared() < 0.0001:
		chord_axis = Vector3.RIGHT - to_camera * to_camera.x
	chord_axis = chord_axis.normalized()
	# Tilt the chord around the plane normal (to_camera) for the
	# saber-stroke diagonal. Bow axis stays orthogonal in-plane.
	chord_axis = chord_axis.rotated(to_camera, deg_to_rad(SLASH_TILT_DEG))
	var bow_axis: Vector3 = to_camera.cross(chord_axis).normalized()
	var mat: ShaderMaterial = _get_slash_material_template().duplicate()
	mat.set_shader_parameter(&"intensity", SLASH_INTENSITY)
	var inst := MeshInstance3D.new()
	inst.mesh = _get_slash_mesh()
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	inst.global_position = midpoint
	# Basis: scaled directly along the in-plane axes so the unit plane
	# becomes the full chord × bow size. Plane normal (Z) faces camera.
	inst.basis = Basis(chord_axis * chord, bow_axis * bow, to_camera)
	# Fade by tweening the shader's `intensity` to 0. The shader's
	# alpha follows brightness, so this single property drives both
	# the visible streak and its transparency in one ease.
	var tween := inst.create_tween()
	tween.tween_property(mat, "shader_parameter/intensity", 0.0, SLASH_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_callback(inst.queue_free)

# Detached from host so the wave stays where it was unleashed even if the
# host moves or rotates during the effect. forward == ZERO means no orientation
# (radial sphere); otherwise the mesh's local -Z is aimed along forward.
static func _spawn_shockwave(host: Node3D, world_pos: Vector3, mesh: Mesh, forward: Vector3, duration: float) -> void:
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = SHOCKWAVE_BUBBLE_SHADER
	mat.set_shader_parameter(&"distortion", SHOCKWAVE_BUBBLE_DISTORTION)
	mat.set_shader_parameter(&"chroma", SHOCKWAVE_BUBBLE_CHROMA)
	mat.set_shader_parameter(&"rim_strength", SHOCKWAVE_BUBBLE_RIM)
	mat.set_shader_parameter(&"intensity", 1.0)
	node.material_override = mat
	node.scale = Vector3.ONE * SHOCKWAVE_START_SCALE
	parent.add_child(node)
	node.global_position = world_pos
	if forward.length_squared() > 0.0001:
		node.look_at(world_pos + forward, Vector3.UP)
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "scale", Vector3.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "shader_parameter/intensity", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(node.queue_free)

static func _telegraphs_enabled() -> bool:
	if DebugState.config == null:
		return true
	return DebugState.config.show_attack_telegraphs

static func _color_for_host(host: Node) -> Color:
	if host.is_in_group(&"player"):
		return UIThemeState.palette.accent
	return ENEMY_COLOR

static func _play_fade(node: MeshInstance3D, mat: StandardMaterial3D, wind_up: float) -> void:
	var tween := node.create_tween()
	if wind_up > 0.0:
		mat.albedo_color.a = 0.4
		tween.tween_property(mat, "albedo_color:a", 1.0, wind_up)
	tween.tween_property(mat, "albedo_color:a", 0.0, FADE_DURATION)
	tween.tween_callback(node.queue_free)

static func _cone_mesh(radius: float, angle_deg: float) -> ArrayMesh:
	var key := Vector2(radius, angle_deg)
	var cached: ArrayMesh = _cone_cache.get(key)
	if cached != null:
		return cached
	var half := deg_to_rad(angle_deg * 0.5)
	# Build a filled triangle-fan wedge so the telegraph is visible from
	# the isometric camera (the old line strip was 1 px wide — invisible).
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	# Vertex 0 = apex (origin)
	verts.append(Vector3.ZERO)
	for i in range(CONE_SEGMENTS + 1):
		var t := float(i) / float(CONE_SEGMENTS)
		var angle: float = lerp(-half, half, t)
		verts.append(Vector3(sin(angle) * radius, 0.0, -cos(angle) * radius))
	# Triangle fan: apex → arc[i] → arc[i+1]
	for i in range(CONE_SEGMENTS):
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cone_cache[key] = mesh
	return mesh

static func _disk_mesh(radius: float) -> ArrayMesh:
	var cached: ArrayMesh = _disk_cache.get(radius)
	if cached != null:
		return cached
	var verts := PackedVector3Array()
	for i in range(DISK_SEGMENTS + 1):
		var angle := TAU * float(i) / float(DISK_SEGMENTS)
		verts.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	var mesh := _make_line_mesh(verts)
	_disk_cache[radius] = mesh
	return mesh

static func _line_mesh(length: float) -> ArrayMesh:
	var cached: ArrayMesh = _line_cache.get(length)
	if cached != null:
		return cached
	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	verts.append(Vector3(0.0, 0.0, -length))
	var mesh := _make_line_mesh(verts)
	_line_cache[length] = mesh
	return mesh

static func _make_line_mesh(verts: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	return mesh

# Hemispherical wedge: apex at +Y pole, expanding outward to the equator and
# clipped horizontally to the cone arc. Local -Z points along the aim, so the
# wedge opens in front of the swinger. Outward-facing per-vertex normals feed
# the refraction shader's screen-space offset.
static func _cone_dome_mesh(radius: float, cone_deg: float) -> ArrayMesh:
	var key := Vector2(radius, cone_deg)
	var cached: ArrayMesh = _cone_dome_cache.get(key)
	if cached != null:
		return cached
	var half := deg_to_rad(cone_deg * 0.5)
	var rings := CONE_DOME_RINGS
	var segments := CONE_DOME_SEGMENTS
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for r in range(rings + 1):
		var lat: float = lerp(0.0, PI * 0.5, float(r) / float(rings))
		var sin_lat := sin(lat)
		var cos_lat := cos(lat)
		for s in range(segments + 1):
			var lon: float = lerp(-half, half, float(s) / float(segments))
			var dir := Vector3(sin_lat * sin(lon), cos_lat, -sin_lat * cos(lon))
			verts.append(dir * radius)
			normals.append(dir)
	for r in range(rings):
		for s in range(segments):
			var i0 := r * (segments + 1) + s
			var i1 := i0 + 1
			var i2 := i0 + (segments + 1)
			var i3 := i2 + 1
			indices.append(i0)
			indices.append(i2)
			indices.append(i1)
			indices.append(i1)
			indices.append(i2)
			indices.append(i3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cone_dome_cache[key] = mesh
	return mesh

static func _bubble_mesh(radius: float) -> SphereMesh:
	var cached: SphereMesh = _bubble_mesh_cache.get(radius)
	if cached != null:
		return cached
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 12
	_bubble_mesh_cache[radius] = mesh
	return mesh

# ── Beam mesh / material caches ──────────────────────────────────────────────

static func _beam_core_mesh(length: float) -> CylinderMesh:
	var cached: CylinderMesh = _beam_core_mesh_cache.get(length)
	if cached != null:
		return cached
	var m := CylinderMesh.new()
	m.top_radius = BEAM_RADIUS
	m.bottom_radius = BEAM_RADIUS
	m.height = length
	m.radial_segments = 6
	m.rings = 1
	_beam_core_mesh_cache[length] = m
	return m

static func _beam_glow_mesh(length: float) -> CylinderMesh:
	var cached: CylinderMesh = _beam_glow_mesh_cache.get(length)
	if cached != null:
		return cached
	var m := CylinderMesh.new()
	m.top_radius = BEAM_RADIUS * 3.0
	m.bottom_radius = BEAM_RADIUS * 3.0
	m.height = length
	m.radial_segments = 6
	m.rings = 1
	_beam_glow_mesh_cache[length] = m
	return m

static func _beam_core_material(color: Color) -> StandardMaterial3D:
	var template: StandardMaterial3D = _beam_core_mat_cache.get(color)
	if template == null:
		template = StandardMaterial3D.new()
		template.albedo_color = Color(color.r, color.g, color.b, 0.95)
		template.emission_enabled = true
		template.emission = color
		template.emission_energy_multiplier = 20.0
		template.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		template.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		template.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_core_mat_cache[color] = template
	return template.duplicate() as StandardMaterial3D

static func _beam_glow_material(color: Color) -> StandardMaterial3D:
	var template: StandardMaterial3D = _beam_glow_mat_cache.get(color)
	if template == null:
		template = StandardMaterial3D.new()
		template.albedo_color = Color(color.r, color.g, color.b, 0.2)
		template.emission_enabled = true
		template.emission = color
		template.emission_energy_multiplier = 6.0
		template.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		template.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		template.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_glow_mat_cache[color] = template
	return template.duplicate() as StandardMaterial3D

# ── Muzzle flash ─────────────────────────────────────────────────────────────
# Quick OmniLight3D pulse at the barrel position on weapon fire. No mesh —
# just a point light pop that illuminates nearby surfaces for 1-2 frames.
# Reuses the existing light pool so no allocations at horde scale.

const MUZZLE_FLASH_DURATION: float = 0.06
const MUZZLE_FLASH_ENERGY: float = 5.0
const MUZZLE_FLASH_RANGE: float = 4.0
# Per-archetype flash color. Bullet weapons flash warm orange-white (muzzle
# fire); energy weapons flash their damage-type tint.
const MUZZLE_FLASH_BULLET_COLOR := Color(1.0, 0.8, 0.45)
const MUZZLE_FLASH_ENERGY_COLOR := Color(0.6, 0.85, 1.0)


static func spawn_muzzle_flash(host: Node3D, barrel_pos: Vector3, is_bullet: bool = true, tint: Color = Color(0, 0, 0, 0)) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var light := _acquire_light()
	if tint.a > 0.0:
		light.light_color = tint
	elif is_bullet:
		light.light_color = MUZZLE_FLASH_BULLET_COLOR
	else:
		light.light_color = MUZZLE_FLASH_ENERGY_COLOR
	light.light_energy = MUZZLE_FLASH_ENERGY
	light.omni_range = MUZZLE_FLASH_RANGE
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	parent.add_child(light)
	light.global_position = barrel_pos
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, MUZZLE_FLASH_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(_release_light.bind(light))


# ── Telegraph material ───────────────────────────────────────────────────────

static func _build_material(color: Color) -> StandardMaterial3D:
	var template: StandardMaterial3D = _material_template_cache.get(color)
	if template == null:
		template = StandardMaterial3D.new()
		template.albedo_color = Color(color.r, color.g, color.b, 1.0)
		template.emission_enabled = true
		template.emission = color
		template.emission_energy_multiplier = 4.0
		template.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		template.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		template.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material_template_cache[color] = template
	return template.duplicate() as StandardMaterial3D
