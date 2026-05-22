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


# --- Lambda-safe deferred-free helpers --------------------------------
# Binding `node.queue_free` (or any method on `node`) directly into a
# Callable means the captured Object reference must still be valid when
# the Callable fires. If the level reloads mid-VFX (or the node is
# otherwise freed between schedule and fire), Godot rejects the entire
# Callable with "Lambda capture at index 0 was freed". These helpers
# capture the instance ID (an int, never freed) and re-resolve it at
# call time instead.
static func _free_later(node: Node) -> Callable:
	var nid: int = node.get_instance_id()
	return func() -> void:
		var n := instance_from_id(nid) as Node
		if n != null:
			n.queue_free()


static func _release_light_later(light: OmniLight3D) -> Callable:
	var lid: int = light.get_instance_id()
	return func() -> void:
		var l := instance_from_id(lid) as OmniLight3D
		if l != null:
			_release_light(l)


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
	killer.tween_callback(_free_later(node))

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
	tween.tween_callback(_free_later(inst))


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
	tween.chain().tween_callback(_release_light_later(impact_light))
	tween.chain().tween_callback(_release_light_later(mid_light))
	tween.chain().tween_callback(_free_later(node))

# Brief impact flash + spark burst spawned at a hit point — mini version of
# the explosion VFX stack (flash sphere + radial sparks + omni light), no
# flipbook or smoke. Reads as a sharp detonation pop colored to the
# triggering projectile. Used by projectile collisions and hitscan target
# hits. `color_override` opts in to a specific tint; pass Color() (zero
# alpha) to fall back to _color_for_host so player shots stay class-colored.
const IMPACT_FLASH_DURATION := 0.12
const IMPACT_FLASH_RADIUS := 0.25
const IMPACT_SPARK_LIFETIME := 0.25
const IMPACT_SPARK_COUNT := 8

static func spawn_impact_burst(host: Node3D, world_pos: Vector3, color_override: Color = Color(0, 0, 0, 0)) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var color := color_override
	if color.a == 0.0:
		color = _color_for_host(host)

	# ── Flash sphere ──────────────────────────────────────────────────
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = IMPACT_FLASH_RADIUS
	flash_mesh.height = IMPACT_FLASH_RADIUS * 2.0
	flash_mesh.radial_segments = 12
	flash_mesh.rings = 6
	var flash_mat := StandardMaterial3D.new()
	# Core color is a brighter, desaturated version of the projectile color
	# so the initial pop reads as white-hot center fading to the accent.
	var core := Color(
		lerpf(color.r, 1.0, 0.6),
		lerpf(color.g, 1.0, 0.6),
		lerpf(color.b, 1.0, 0.6),
		0.9)
	flash_mat.albedo_color = core
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(core.r, core.g, core.b)
	flash_mat.emission_energy_multiplier = 5.0
	flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flash_inst := MeshInstance3D.new()
	flash_inst.mesh = flash_mesh
	flash_inst.material_override = flash_mat
	flash_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_inst.scale = Vector3.ONE * 0.3
	parent.add_child(flash_inst)
	flash_inst.global_position = world_pos

	var flash_tween := flash_inst.create_tween().set_parallel(true)
	flash_tween.tween_property(flash_inst, "scale", Vector3.ONE * 1.4, IMPACT_FLASH_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	flash_tween.tween_property(flash_mat, "albedo_color:a", 0.0, IMPACT_FLASH_DURATION).set_ease(Tween.EASE_IN)
	flash_tween.tween_property(flash_mat, "emission_energy_multiplier", 0.0, IMPACT_FLASH_DURATION).set_ease(Tween.EASE_IN)
	flash_tween.chain().tween_callback(_free_later(flash_inst))

	# ── Omni light ────────────────────────────────────────────────────
	var light := _acquire_light()
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = 3.5
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	flash_inst.add_child(light)

	# ── Spark burst ───────────────────────────────────────────────────
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = IMPACT_SPARK_COUNT
	particles.lifetime = IMPACT_SPARK_LIFETIME
	particles.explosiveness = 1.0
	particles.local_coords = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	pm.direction = Vector3(0.0, 0.2, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0.0, -8.0, 0.0)
	pm.damping_min = 4.0
	pm.damping_max = 7.0
	pm.scale_min = 0.02
	pm.scale_max = 0.05
	pm.color = Color(color.r, color.g, color.b, 1.0)
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.6, 0.4))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	particles.process_material = pm

	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.03
	spark_mesh.height = 0.06
	spark_mesh.radial_segments = 4
	spark_mesh.rings = 2
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = color
	spark_mat.emission_enabled = true
	spark_mat.emission = color
	spark_mat.emission_energy_multiplier = 4.0
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material = spark_mat
	particles.draw_pass_1 = spark_mesh

	parent.add_child(particles)
	particles.global_position = world_pos
	particles.get_tree().create_timer(IMPACT_SPARK_LIFETIME + 0.15).timeout.connect(_free_later(particles))


# ── Blood / gore ───────────────────────────────────────────────────────
#
# Three layered effects compose the gore visual on damage / kill / corpse:
#
#   spawn_blood_burst(pos, dir, count_mult)
#     — GPUParticles3D burst of red droplets. Cheap (no decals, no
#       allocations beyond the emitter), called every hit. count_mult
#       scales the droplet count for varying damage levels (1.0 = chip,
#       2-3 = kill, 4+ = explosion or crit).
#   spawn_blood_decal(pos)
#     — Floor splatter decal at the kill point. Capped via the
#       _blood_decal_ring so total active decals stay bounded.
#   spawn_blood_pool(pos)
#     — Larger, smoother decal under a settled corpse. Same cap pool.
#
# Procedural textures are generated once at startup and shared by every
# decal of the same type — no per-decal image work.

# ── Blood / fluid palette ──────────────────────────────────────────────
#
# Every blood-spawning function takes a `blood_type` StringName so a
# future Cyborg can bleed fluorescent blue and a Machine can leak black
# oil without code changes elsewhere. PrototypeEnemy stores its own
# blood_type (default &"human") and threads it through every spawn call.
#
# Adding a new fluid type is a single entry in BLOOD_PALETTES — all the
# texture generators, decal spawns, and particle bursts pick up the new
# color automatically. Textures cache per-blood_type so a horde of mixed
# enemies costs at most one texture per kind × fluid type, not per kill.
#
# Color philosophy (kept consistent across types):
#   Diffuse is kept VERY dark / saturated. The apparent brightness comes
#   from glossy specular (low ORM roughness) catching ceiling lights —
#   that wet sheen is what reads as "fresh liquid". A brighter diffuse
#   would flatten into "painted on", not "spilled".
const BLOOD_TYPE_HUMAN: StringName = &"human"
const BLOOD_TYPE_CYBORG: StringName = &"cyborg"
const BLOOD_TYPE_MACHINE: StringName = &"machine"
const BLOOD_PALETTES: Dictionary = {
	# Dark venous red — wet blood is near-black in shadow.
	&"human": Color(0.13, 0.015, 0.012),
	# Fluorescent cyan-blue — placeholder for Cyborg fluid. Brighter than
	# blood so the wet sheen reads at a glance even on dim floors.
	&"cyborg": Color(0.06, 0.45, 0.95),
	# Black oil — very dark with a subtle blue cast so it doesn't read as
	# generic "shadow under the body".
	&"machine": Color(0.02, 0.022, 0.03),
}
const BLOOD_DROPLET_LIFETIME: float = 0.45
# Burst droplet speed range. Tightened from 4.0–7.5 m/s — earlier values
# threw droplets 2–3 m past the body and read as a projectile arc; the
# tighter range keeps the spray clustered around the wound while gravity
# still pulls drops down within BLOOD_DROPLET_LIFETIME. Both the GPU
# particle material and the landing-decal ballistic sampler key off
# these constants, so changing one site won't desync visible-vs-painted
# travel distances.
const BLOOD_BURST_SPEED_MIN: float = 1.2
const BLOOD_BURST_SPEED_MAX: float = 2.4

static func blood_color_for(_blood_type: StringName) -> Color:
	# All fluids currently render as human red — the cyborg cyan and
	# machine black variants read as "wrong palette" rather than "different
	# faction bleeds different fluid" in the noir lighting (the cyan one
	# in particular looked like spilled paint). Palette dict + per-enemy
	# blood_type plumbing is kept intact; flip this back to
	# `BLOOD_PALETTES.get(blood_type, BLOOD_PALETTES[BLOOD_TYPE_HUMAN])`
	# to re-enable multi-fluid once the per-faction visual reads cleanly.
	return BLOOD_PALETTES[BLOOD_TYPE_HUMAN]

# Multiple splatter texture variants per blood type, baked once and
# picked from at random per spawn so adjacent decals don't read as
# stamped duplicates. Each variant has a matching normal map derived
# from the alpha gradient for slight surface relief at iso angles.
# ORM texture (Occlusion/Roughness/Metallic, packed RGB) is shared
# across all blood decals regardless of fluid color and drives the
# wet sheen via low roughness.
const _SPLATTER_VARIANT_COUNT: int = 4
static var _blood_splatter_variants: Dictionary = {}   # StringName -> Array[Texture2D]
static var _blood_splatter_normals: Dictionary = {}    # StringName -> Array[Texture2D]
# Wall splatters need their own variant set — every streak forced
# to point along the texture's +V axis so once the decal's V is
# aligned with world-down by _wall_drip_twist_angle, the streaks
# visibly run down the wall as gravity drips.
static var _blood_wall_splatter_variants: Dictionary = {}
static var _blood_wall_splatter_normals: Dictionary = {}
static var _blood_orm_texture: Texture2D = null
# Boot-print silhouettes — same right/left mirror system as before, but
# both variants now multiply across fluid types (so a player who walks
# through cyborg blood leaves blue prints).
static var _blood_bootprint_right_textures: Dictionary = {}
static var _blood_bootprint_left_textures: Dictionary = {}
# Ring buffer of active blood decals — oldest fades out when the cap
# is hit. Single global cap across all corpses + per-hit residue.
# 250 gives clearly-bloodier rooms before the FIFO eviction kicks in,
# at a modest perf cost (decals are frustum-culled so offscreen ones
# are nearly free; in-camera cost is sampling overhead per pixel).
const BLOOD_DECAL_MAX: int = 400
static var _blood_decal_ring: Array[Decal] = []
# Monotonic per-decal stamp used as the secondary sort key when the
# eviction scan picks "smallest, then oldest". Strictly increasing
# across all blood spawns, so a smaller value = older decal.
static var _blood_insert_seq: int = 0


# Single gate for every blood spawn path. Players who flip
# AccessibilityState.config.disable_blood in settings get a clean
# combat presentation — hit-flash + damage numbers + sounds still
# fire (those carry the actual feedback information), but no decals,
# no mist particles, no bloody footprints. Hit early so we don't pay
# any setup cost for visuals that won't appear.
static func _blood_disabled() -> bool:
	return AccessibilityState.config != null and AccessibilityState.config.disable_blood


static func spawn_blood_burst(parent: Node, world_pos: Vector3, direction: Vector3 = Vector3.UP, count_mult: float = 1.0, blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	if parent == null or _blood_disabled():
		return
	var particles := GPUParticles3D.new()
	# Same pattern as the working CombatVisuals.spawn_impact_burst: set
	# emitting=true here, then add_child + global_position. Godot defers
	# the actual emission to after the node is in the tree, by which
	# point the world position has been assigned.
	particles.emitting = true
	particles.one_shot = true
	particles.amount = clampi(int(14.0 * count_mult), 8, 90)
	particles.lifetime = BLOOD_DROPLET_LIFETIME
	particles.explosiveness = 1.0
	particles.local_coords = false
	# Transient VFX — opt out of SDFGI baking (gi_mode default STATIC
	# treats the burst as solid geometry and darkens the room behind it)
	# and shadow casting (a few dozen tiny droplets making per-frame
	# shadow updates is expensive and visually noisy).
	particles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	# Tight emission origin — small sphere reads as "from the wound"
	# at iso scale. The cone spread below is what shapes the spray.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	pm.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	# Spread is the half-angle around `direction`, so 25° here gives a
	# 50° cone — narrow enough to read as a focused exit-wound jet
	# instead of an omnidirectional puff.
	pm.spread = 25.0
	pm.initial_velocity_min = BLOOD_BURST_SPEED_MIN * count_mult
	pm.initial_velocity_max = BLOOD_BURST_SPEED_MAX * count_mult
	# Strong gravity so droplets arc back down quickly — sells "drips
	# falling to the floor" not "particles flying off into the void".
	pm.gravity = Vector3(0.0, -12.0, 0.0)
	pm.damping_min = 0.5
	pm.damping_max = 2.0
	# ParticleProcessMaterial.scale_min/max is a MULTIPLIER on the mesh
	# size. 0.7-1.3 gives natural per-droplet variation around the
	# mesh's base radius (0.035 m / ~7 cm diameter below).
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	# Droplet color = palette base (the same dark venous tone the floor
	# splatter decals use). Visibility comes from the emission term
	# below, not from brightening the diffuse — keeping the diffuse
	# dark means the mist reads as the same fluid as the splatters it
	# leaves behind.
	var droplet_color := blood_color_for(blood_type)
	pm.color = droplet_color
	# Droplets shrink as they travel — masks the moment they vanish.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.8, 0.7))
	curve.add_point(Vector2(1.0, 0.0))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	pm.scale_curve = curve_tex
	particles.process_material = pm

	# Sphere mesh — smaller droplets read as a quick mist rather than
	# gore chunks. 3.5 cm radius × scale 0.7-1.3 = 2.5-4.5 cm radius
	# (~5-9 cm diameter on screen).
	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 0.035
	droplet_mesh.height = 0.07
	droplet_mesh.radial_segments = 5
	droplet_mesh.rings = 3
	var droplet_mat := StandardMaterial3D.new()
	droplet_mat.albedo_color = droplet_color
	# Emission carries the visible color. Without it, the
	# particle_vertex_color × albedo product squares the color down to
	# near-black at iso distance against a dim floor — verified
	# empirically that an UNSHADED-only droplet was invisible even at
	# bumped sizes / counts. Multiplier 2.5 gives a clear, slightly
	# glowing droplet without looking radioactive (cf. explosion sparks
	# at 4.0 which intentionally look hot).
	droplet_mat.emission_enabled = true
	droplet_mat.emission = droplet_color
	# 3.5 puts the droplet in the readable-at-iso range without losing
	# the dark blood hue. 2.0 matched the splatter base color exactly
	# but was hard to spot against dim floors; 4.0 was punchy crimson
	# that looked detached from the splatters. 3.5 is the middle ground
	# — clearly visible mist that still reads as the same fluid as the
	# stains it leaves on the ground.
	droplet_mat.emission_energy_multiplier = 3.5
	droplet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	droplet_mesh.material = droplet_mat
	particles.draw_pass_1 = droplet_mesh

	parent.add_child(particles)
	particles.global_position = world_pos
	# Free shortly after the last particle dies. lifetime + small tail.
	particles.get_tree().create_timer(BLOOD_DROPLET_LIFETIME + 0.3).timeout.connect(_free_later(particles))
	# Per-droplet landing decals — sample N trajectories within the
	# burst cone and place a tiny drop at each predicted landing point.
	# Fire-and-forget: the function awaits a process frame internally so
	# its raycasts run safely outside any active physics-signal flush.
	_paint_mist_droplets(parent, world_pos, pm.direction, blood_type, count_mult)


# Samples N particle trajectories from the burst cone and stamps a tiny
# decal at each predicted landing position (floor or wall, whichever
# the ballistic / linear path intersects first). Matches the
# distribution of the GPUParticles3D burst — same cone half-angle, same
# velocity range, same gravity — so droplets paint where the player
# saw them fly.
#
# Async (await process_frame) so intersect_ray runs outside the physics
# step's signal-flush window, where space state is locked. Caller does
# NOT await — call as a regular function, the work happens later.
const _MIST_CONE_HALF_ANGLE_RAD: float = deg_to_rad(25.0)
const _MIST_GRAVITY: float = 12.0  # matches pm.gravity.y magnitude in spawn_blood_burst
static func _paint_mist_droplets(parent: Node, origin: Vector3, direction: Vector3, blood_type: StringName, count_mult: float) -> void:
	if parent == null:
		return
	var node := parent as Node3D
	if node == null or not node.is_inside_tree():
		return
	# Wait for the NEXT physics_frame — Godot 4.6.2's process_frame
	# can still fire inside the physics signal-flush window when chained
	# from a body_entered callback, so process_frame wasn't enough.
	# Same pattern as PrototypeEnemy._try_spawn_wall_blood (which has
	# the same flush-window problem). Unconditional await — if we're
	# already mid-physics-frame, we still wait for the NEXT one, so
	# the previous frame's flush is fully done before we query.
	await node.get_tree().physics_frame
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var space := node.get_world_3d().direct_space_state
	if space == null:
		return
	if direction.length_squared() < 0.0001:
		return
	var dir_n := direction.normalized()
	# Build perpendicular basis vectors for cone sampling. Pick an `up`
	# reference that's not parallel to dir_n (otherwise the cross
	# product degenerates).
	var up_ref: Vector3 = Vector3.UP if absf(dir_n.y) < 0.95 else Vector3.RIGHT
	var right_axis: Vector3 = dir_n.cross(up_ref).normalized()
	# Sample count scales modestly with hit_mult so blade crits paint
	# more drops than a non-crit bullet — but capped tight so even a
	# horde-scale fight doesn't queue dozens of decals + raycasts per
	# physics step. 2-6 drops per hit; larger drop size (see
	# _spawn_mist_drop_floor) means coverage stays similar to the old
	# 4-10 count.
	var sample_count: int = clampi(int(round(2.0 * count_mult)), 2, 6)
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = _DECAL_WALL_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for i in sample_count:
		# Pick a random direction in the cone: rotate dir_n by `theta`
		# around an axis perpendicular to dir_n, where the axis itself
		# is rotated by `phi` around dir_n to sweep the cone surface.
		var theta: float = randf() * _MIST_CONE_HALF_ANGLE_RAD
		var phi: float = randf() * TAU
		var spin_axis: Vector3 = right_axis.rotated(dir_n, phi)
		var sample_dir: Vector3 = dir_n.rotated(spin_axis, theta).normalized()
		# Velocity range matches the GPU particle range in spawn_blood_burst.
		var speed: float = randf_range(BLOOD_BURST_SPEED_MIN * count_mult, BLOOD_BURST_SPEED_MAX * count_mult)
		var vel: Vector3 = sample_dir * speed
		# Solve ballistic landing on y=0: y(t) = origin.y + vy*t - 6t² = 0
		# Quadratic in t: 6t² - vy*t - origin.y = 0 → t = (vy + √(vy² + 24·oy)) / 12
		var oy: float = origin.y
		var vy: float = vel.y
		var disc: float = vy * vy + (2.0 * _MIST_GRAVITY * oy)
		if disc < 0.0:
			continue
		var t_land: float = (vy + sqrt(disc)) / _MIST_GRAVITY
		if t_land <= 0.0:
			continue
		var landing: Vector3 = origin + vel * t_land + Vector3(0.0, -0.5 * _MIST_GRAVITY * t_land * t_land, 0.0)
		# Check whether a wall intercepts the line from origin to landing.
		# We use a straight ray (not the curved arc) — at the short
		# distances/times involved, the discrepancy is invisible.
		query.from = origin
		query.to = landing
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			# Clean trajectory → drop lands on the floor at the
			# ballistic landing point.
			_spawn_mist_drop_floor(parent, Vector3(landing.x, 0.0, landing.z), blood_type)
			continue
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		var hit_pos: Vector3 = hit.get("position", landing)
		if absf(normal.y) > 0.6:
			# Floor / ceiling — paint as a floor drop at the hit point.
			_spawn_mist_drop_floor(parent, Vector3(hit_pos.x, 0.0, hit_pos.z), blood_type)
		else:
			_spawn_mist_drop_wall(parent, hit_pos, normal, blood_type)


# Floor drop — 25-45 cm wide. Earlier 8-18 cm was too small to read at
# iso distance; bumped to be clearly visible while still smaller than
# the 1.4-2.5 m kill-scene main splats.
## Returns true when `world_pos`'s X/Z falls inside any active pit's
## footprint. Iterates the `pit_zones` group (populated by pit_builder
## via the kill-area Area3D, one entry per pit), reading each pit's
## BoxShape3D bounds and testing the spawn point against them. Cheap —
## levels carry ~5-15 pits, no physics queries.
static func _is_over_pit(parent: Node, world_pos: Vector3) -> bool:
	if parent == null or not (parent is Node) or parent.get_tree() == null:
		return false
	for n in parent.get_tree().get_nodes_in_group(&"pit_zones"):
		if not (n is Area3D):
			continue
		var area := n as Area3D
		var col: CollisionShape3D = null
		for child in area.get_children():
			if child is CollisionShape3D:
				col = child as CollisionShape3D
				break
		if col == null or not (col.shape is BoxShape3D):
			continue
		var box := col.shape as BoxShape3D
		var hx: float = box.size.x * 0.5
		var hz: float = box.size.z * 0.5
		var ap: Vector3 = area.global_position
		if absf(world_pos.x - ap.x) <= hx and absf(world_pos.z - ap.z) <= hz:
			return true
	return false


static func _spawn_mist_drop_floor(parent: Node, world_pos: Vector3, blood_type: StringName) -> void:
	# Mist droplets route through the same attach-or-spawn entry as
	# kill scenes — small per-hit drops on clear floor stamp tiny
	# stand-alone pools; drops near an existing pool grow it. No
	# special-case logic needed.
	spawn_blood_decal(parent, world_pos, blood_type)


# Wall drop — same size band as floor drops, projected along the
# surface normal of whatever the droplet hit.
static func _spawn_mist_drop_wall(parent: Node, world_pos: Vector3, wall_normal: Vector3, blood_type: StringName) -> void:
	if wall_normal.length_squared() < 0.0001:
		return
	var decal := Decal.new()
	var variant := _get_blood_wall_splatter_variant(blood_type)
	decal.texture_albedo = variant[&"albedo"]
	decal.texture_normal = variant[&"normal"]
	decal.texture_orm = _get_blood_orm_texture()
	decal.size = Vector3(randf_range(0.20, 0.65), 0.4, randf_range(0.20, 0.65))
	decal.modulate = _decal_color_jitter()
	decal.upper_fade = 0.05
	decal.lower_fade = 0.05
	decal.albedo_mix = BLOOD_DECAL_ALBEDO_MIX
	decal.cull_mask = BLOOD_DECAL_CULL_LAYER
	parent.add_child(decal)
	decal.global_position = world_pos + wall_normal.normalized() * 0.03
	var rot := Quaternion(Vector3.UP, wall_normal.normalized())
	# Gravity-aligned twist: aim the texture's V axis at world-down
	# projected into the wall plane, so drip streaks visibly run down.
	var twist := Basis(wall_normal.normalized(), _wall_drip_twist_angle(wall_normal))
	decal.global_basis = twist * Basis(rot)
	_track_blood_decal(decal, BLOOD_PRIORITY_WALL)


# Kill-scene splatter pattern — one big primary decal at the kill point
# plus 2-4 satellite stains at random offsets within ~2m. Looks like a
# proper "gory mess" rather than a single neat stamp. Direction biases
# the satellites away from the shooter so the spray pattern matches the
# kill direction (~70% of satellites in the away-from-shooter arc).
# Approach A: one pool per kill, animated growth, proximity attach.
#
# Each kill produces ONE central pool that tweens from a small initial
# diameter to a final diameter over POOL_GROWTH_DURATION. If the kill
# happens close to an existing pool (within POOL_ATTACH_RADIUS of its
# edge), the existing pool GROWS toward the new spawn instead of
# stamping a fresh decal — models how real liquid spreads to absorb
# nearby splatters into one continuous puddle.
#
# Models liquid spreading: no satellite stamps that overlap visually,
# no bounding-circle cascade. Far-apart kills create distinct pools;
# adjacent kills coalesce smoothly via the texture's soft alpha
# edges. Persistence comes from a slower fade and lower stamp rate.

# Pool sizing.
const POOL_INITIAL_DIAMETER: float = 0.3        # tiny "fresh splash" at spawn
const POOL_TARGET_MIN_DIAMETER: float = 0.9     # smallest final pool from a single kill
const POOL_TARGET_MAX_DIAMETER: float = 1.4     # largest before merge growth
const POOL_MAX_DIAMETER: float = 3.0            # cap on any pool's grown diameter
const POOL_GROWTH_DURATION: float = 4.5         # slow ooze — player shouldn't see the growth tween in motion
# Attach: if a new kill lands within this distance of an existing
# pool's *edge*, grow that pool to encompass the new spawn instead of
# stamping fresh. Fresh stamps still happen for kills in clear space.
const POOL_ATTACH_RADIUS: float = 0.7
# How much "buffer" we leave around the new spawn when growing — the
# pool extends past the new spawn by this much so the spawn point is
# safely inside the new bounds, not on its rim.
const POOL_GROWTH_BUFFER: float = 0.4
const _POOL_GROWTH_TWEEN_META: StringName = &"_pool_growth_tween"


static func spawn_blood_kill_scene(parent: Node, world_pos: Vector3, _spray_dir: Vector3 = Vector3.ZERO, blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	if parent == null or _blood_disabled():
		return
	# Floor pool — one per kill, with attach-or-grow.
	spawn_blood_decal(parent, world_pos, blood_type)
	# Side-paint nearby props / interactables / pillars.
	spawn_blood_on_receivers(parent, world_pos, blood_type)


# Public entry for "stamp a floor pool at world_pos OR grow the closest
# existing pool toward it". Used by kill scenes and mist droplets.
static func spawn_blood_decal(parent: Node, world_pos: Vector3, blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	if parent == null or _blood_disabled():
		return
	if _is_over_pit(parent, world_pos):
		return
	var nearest := _find_pool_near(world_pos, POOL_ATTACH_RADIUS)
	if nearest != null:
		_grow_pool_toward(nearest, world_pos)
		return
	_spawn_new_pool(parent, world_pos, blood_type)


# Returns the live floor pool whose XZ edge is closest to `world_pos`,
# OR null if no pool sits within `max_edge_dist` of its edge.
static func _find_pool_near(world_pos: Vector3, max_edge_dist: float) -> Decal:
	var best: Decal = null
	var best_edge_dist: float = max_edge_dist
	for d_var in _blood_decal_ring:
		if not is_instance_valid(d_var):
			continue
		var d := d_var as Decal
		if d == null:
			continue
		var dx: float = world_pos.x - d.global_position.x
		var dz: float = world_pos.z - d.global_position.z
		var centre_dist: float = sqrt(dx * dx + dz * dz)
		var pool_r: float = (d.size.x + d.size.z) * 0.25
		var edge_dist: float = maxf(centre_dist - pool_r, 0.0)
		if edge_dist < best_edge_dist:
			best = d
			best_edge_dist = edge_dist
	return best


# Grow `pool` so its bounds extend toward (and slightly past) `new_pos`.
# Tweens the size change so the growth is visibly animated. Kills any
# previous growth tween on this pool so the latest target wins.
static func _grow_pool_toward(pool: Decal, new_pos: Vector3) -> void:
	if not is_instance_valid(pool):
		return
	var dx: float = new_pos.x - pool.global_position.x
	var dz: float = new_pos.z - pool.global_position.z
	var centre_dist: float = sqrt(dx * dx + dz * dz)
	# Radius the pool would need to cover the new spawn + a buffer so
	# the spawn isn't on the rim.
	var needed_r: float = centre_dist + POOL_GROWTH_BUFFER
	var current_r: float = (pool.size.x + pool.size.z) * 0.25
	var target_r: float = clampf(maxf(current_r, needed_r), current_r, POOL_MAX_DIAMETER * 0.5)
	if target_r <= current_r + 0.01:
		# Already covers the new spawn — just re-sort so this pool stays
		# on top of older nearby stamps.
		_refresh_pool_sort_offset(pool)
		return
	_cancel_pool_growth_tween(pool)
	var target_diameter: float = target_r * 2.0
	var tween := pool.create_tween().set_parallel(true)
	tween.tween_property(pool, "size:x", target_diameter, POOL_GROWTH_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pool, "size:z", target_diameter, POOL_GROWTH_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pool.set_meta(_POOL_GROWTH_TWEEN_META, tween)
	_refresh_pool_sort_offset(pool)


# Spawn a fresh floor pool that animates from POOL_INITIAL_DIAMETER up
# to a randomised target in [POOL_TARGET_MIN_DIAMETER, POOL_TARGET_MAX_DIAMETER].
static func _spawn_new_pool(parent: Node, world_pos: Vector3, blood_type: StringName) -> void:
	var pool := Decal.new()
	var variant := _get_blood_splatter_variant(blood_type)
	pool.texture_albedo = variant[&"albedo"]
	pool.texture_normal = variant[&"normal"]
	pool.texture_orm = _get_blood_orm_texture()
	# Start tiny; grow to the random target over POOL_GROWTH_DURATION.
	pool.size = Vector3(POOL_INITIAL_DIAMETER, 0.6, POOL_INITIAL_DIAMETER)
	pool.modulate = _decal_color_jitter()
	pool.upper_fade = 0.15
	pool.lower_fade = 0.15
	pool.albedo_mix = BLOOD_DECAL_ALBEDO_MIX
	pool.cull_mask = BLOOD_DECAL_CULL_LAYER
	pool.rotation.y = randf() * TAU
	parent.add_child(pool)
	pool.global_position = Vector3(
		world_pos.x,
		randf_range(_DECAL_Y_JITTER_MIN, _DECAL_Y_JITTER_MAX),
		world_pos.z,
	)
	_track_blood_decal(pool)  # ring buffer + sort offset
	var target_diameter: float = randf_range(POOL_TARGET_MIN_DIAMETER, POOL_TARGET_MAX_DIAMETER)
	var tween := pool.create_tween().set_parallel(true)
	tween.tween_property(pool, "size:x", target_diameter, POOL_GROWTH_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pool, "size:z", target_diameter, POOL_GROWTH_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pool.set_meta(_POOL_GROWTH_TWEEN_META, tween)


# Kill any in-flight growth tween on `pool` so a fresh one can run.
# A second growth toward a different new_pos shouldn't blend with the
# previous one's target — the latest spawn defines the new target.
static func _cancel_pool_growth_tween(pool: Decal) -> void:
	if not pool.has_meta(_POOL_GROWTH_TWEEN_META):
		return
	var prior: Tween = pool.get_meta(_POOL_GROWTH_TWEEN_META, null) as Tween
	if prior != null and prior.is_valid():
		prior.kill()
	pool.remove_meta(_POOL_GROWTH_TWEEN_META)


# Re-stamp a pool's sort offset to the latest counter so it stays on
# top of older stamps it visually overlaps (newer blood over older).
static func _refresh_pool_sort_offset(pool: Decal) -> void:
	_blood_sort_counter += 1
	pool.sorting_offset = float(_blood_sort_counter) * _BLOOD_SORT_STEP


# Reads the world's physics space (now safely outside any signal flush)
# and resizes the decal to fit inside nearby walls. No-op if the decal
# was freed in the meantime (e.g. ring-buffer eviction). Uses await
# physics_frame because Godot 4.6.2's process_frame can still fire
# during the physics signal-flush window when called from a chain
# triggered by body_entered. Same pattern as PrototypeEnemy._try_spawn
# _wall_blood.
static func _apply_wall_clamp_deferred(decal: Decal, world_pos: Vector3, requested_size: Vector3) -> void:
	if not is_instance_valid(decal) or not decal.is_inside_tree():
		return
	await decal.get_tree().physics_frame
	if not is_instance_valid(decal) or not decal.is_inside_tree():
		return
	var parent := decal.get_parent()
	if parent == null:
		return
	decal.size = _clamp_decal_size_to_walls(parent, world_pos, requested_size)


# Wall splatter — same albedo + ORM textures as the floor splatter, but
# oriented along an arbitrary surface normal so it projects INTO a wall
# (or any non-floor surface). Caller provides the hit world position
# and the surface normal (pointing OUT of the wall).
#
# The Decal node always projects along its local -Y. To paint onto a
# vertical wall, we build a basis whose +Y axis IS the wall_normal —
# then -Y points INTO the wall and the projection lands flush on the
# face. Slight offset along the normal keeps the decal from z-fighting
# with the wall surface.
static func spawn_blood_wall_splatter(parent: Node, world_pos: Vector3, wall_normal: Vector3, blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	if parent == null or _blood_disabled():
		return
	if wall_normal.length_squared() < 0.0001:
		return
	var decal := Decal.new()
	var variant := _get_blood_wall_splatter_variant(blood_type)
	decal.texture_albedo = variant[&"albedo"]
	decal.texture_normal = variant[&"normal"]
	decal.texture_orm = _get_blood_orm_texture()
	# Slightly smaller than floor splats on average — wall splats look
	# better as a few medium hits than one huge stamp, since vertical
	# surfaces read smaller at iso distance. Wide range so multiple
	# wall splats from one fight stack visually distinct.
	decal.size = Vector3(randf_range(0.5, 1.8), 0.4, randf_range(0.5, 1.8))
	decal.modulate = _decal_color_jitter()
	decal.upper_fade = 0.05
	decal.lower_fade = 0.05
	decal.albedo_mix = BLOOD_DECAL_ALBEDO_MIX
	decal.cull_mask = BLOOD_DECAL_CULL_LAYER
	parent.add_child(decal)
	# 3cm offset along the normal keeps the decal off the wall surface
	# itself (z-fighting prevention).
	decal.global_position = world_pos + wall_normal.normalized() * 0.03
	# Build a basis whose +Y axis is the wall_normal. Quaternion(from, to)
	# rotates the from-vector to align with to-vector; applying it to
	# the default Y-up basis means the decal's local Y now points along
	# wall_normal. The twist now aligns the texture's V axis with world-
	# down (projected onto the wall plane) so drip streaks visibly run
	# down the wall — was random before, which let some splats look
	# like blood was running sideways or upward.
	var rot := Quaternion(Vector3.UP, wall_normal.normalized())
	var twist := Basis(wall_normal.normalized(), _wall_drip_twist_angle(wall_normal))
	decal.global_basis = twist * Basis(rot)
	_track_blood_decal(decal, BLOOD_PRIORITY_WALL)


# ── Character blood (decals parented to a character's visual) ────────
#
# spawn_blood_on_character() projects a small splatter onto the
# character mesh itself. The decal is a CHILD of the character's
# visual root, so it follows movement / animation / ragdoll launches
# naturally — no "decal stuck in 3D space while corpse slides away"
# bug. cull_mask = CHARACTER_BLOOD_LAYER, which only character
# meshes opt into (via `_walk_set_visual_layers(visual, 2 | 4)`),
# so the decal can't paint world geometry or other characters.
#
# Per-character cap (5 splats); a fade tween clears each one over
# CHARACTER_BLOOD_FADE_DURATION (12 s) and queue_frees on completion.
# The per-character list is stored in the visual's `_blood_decals`
# meta to avoid touching every character class.
static func spawn_blood_on_character(character_visual: Node3D, world_impact_pos: Vector3, blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	if character_visual == null or not is_instance_valid(character_visual):
		return
	if not character_visual.is_inside_tree():
		return
	if _blood_disabled():
		return
	# Per-character lifecycle list. Tracks live decals so we can evict
	# the oldest when the cap is hit and detect freed entries.
	var list: Array = character_visual.get_meta(&"_blood_decals", []) as Array
	# Compact any freed entries before measuring against the cap —
	# tweens can free decals out of order (level reset, character
	# culling) and stale references shouldn't count toward the cap.
	var live: Array = []
	for d_var in list:
		if is_instance_valid(d_var):
			live.append(d_var)
	if live.size() >= CHARACTER_BLOOD_MAX_PER_CHAR:
		# Evict the oldest decal — fade it out immediately.
		var oldest: Variant = live.pop_front()
		if oldest is Decal:
			_fade_character_blood_decal(oldest as Decal, 0.5)
	# Local-space position: project the world impact into the character's
	# frame so the decal sits on the surface of the body where the hit
	# landed. Lift Y by ~1.0 so it projects DOWN through the torso /
	# head region rather than sideways through the feet.
	var local_impact: Vector3 = character_visual.global_transform.affine_inverse() * world_impact_pos
	var decal := Decal.new()
	var variant := _get_blood_splatter_variant(blood_type)
	decal.texture_albedo = variant[&"albedo"]
	decal.texture_normal = variant[&"normal"]
	decal.texture_orm = _get_blood_orm_texture()
	# Small footprint (humanoid surface area); tall projection volume
	# so the splat covers the character even at extreme pose angles
	# (a kicked-up leg, a turning torso).
	decal.size = Vector3(randf_range(0.30, 0.55), 1.6, randf_range(0.30, 0.55))
	decal.modulate = _decal_color_jitter()
	decal.upper_fade = 0.1
	decal.lower_fade = 0.1
	decal.albedo_mix = BLOOD_DECAL_ALBEDO_MIX
	decal.cull_mask = CHARACTER_BLOOD_LAYER
	decal.rotation.y = randf() * TAU
	# Position at local impact, lifted to torso height. Clamp the XZ
	# component to a small radius around the character's local origin
	# so the splatter lands on the body even if the impact world-pos
	# was an arm-length away (e.g. ranged hits compute from the
	# character's pivot).
	var planar := Vector2(local_impact.x, local_impact.z)
	if planar.length() > 0.4:
		planar = planar.normalized() * 0.4
	decal.position = Vector3(planar.x, 1.0, planar.y)
	character_visual.add_child(decal)
	live.append(decal)
	character_visual.set_meta(&"_blood_decals", live)
	# Hold for most of the fade duration, then taper alpha to 0 and
	# queue_free. Tween hosted on the decal itself so a freed character
	# carrying it doesn't strand the tween.
	_fade_character_blood_decal(decal, CHARACTER_BLOOD_FADE_DURATION)


# Internal: kick off (or replace) a decal's fade-and-free tween.
# `duration` is the total time before queue_free.
static func _fade_character_blood_decal(decal: Decal, duration: float) -> void:
	if not is_instance_valid(decal) or not decal.is_inside_tree():
		return
	var tween := decal.create_tween()
	# Hold roughly 60% of the duration at full alpha, then fade for
	# the remaining 40%. Sustained-presence + visible-fade reads
	# better than a slow linear ramp the whole time.
	var hold := duration * 0.6
	var fade := maxf(duration - hold, 0.2)
	tween.tween_interval(hold)
	tween.tween_property(decal, "modulate:a", 0.0, fade)
	var decal_id: int = decal.get_instance_id()
	tween.tween_callback(func() -> void:
		var d := instance_from_id(decal_id) as Node
		if d != null:
			d.queue_free()
	)


# ── Object blood (props / interactables / future objects) ────────────
#
# Pipeline:
#   1. Object opt-in: register_as_blood_receiver(node) — adds to the
#      OBJECT_BLOOD_RECEIVER_GROUP, registers with SpatialGrid under
#      that group, and ORs OBJECT_BLOOD_LAYER into every MeshInstance3D
#      under the node. Call once from the object's _ready.
#   2. On enemy kill: spawn_blood_kill_scene calls
#      spawn_blood_on_receivers(kill_pos, blood_type).
#   3. That fn does a SpatialGrid radius query for nearby receivers,
#      raycasts from kill_pos to each (rejecting any blocked by walls),
#      and spawns a side-projected decal at the hit point oriented by
#      the surface normal. Decals are PARENTED to the receiver so
#      movable / destructible objects carry their blood with them.
#   4. Each decal fades out over OBJECT_BLOOD_FADE_DURATION.
#
# New paintable objects integrate with one call to
# register_as_blood_receiver — no per-class decal logic to author.

static func spawn_blood_on_receivers(parent: Node, kill_pos: Vector3, blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	if parent == null or _blood_disabled():
		return
	var node := parent as Node3D
	if node == null or not node.is_inside_tree():
		return
	# Wait for the NEXT physics_frame — direct_space_state below is locked
	# when this function is called from a body_entered chain (projectile
	# → take_damage → _die → spawn_blood_on_receivers), which is the most
	# common path. Same pattern as _paint_mist_droplets / wall-blood
	# raycast. Caller does NOT await — fire-and-forget.
	await node.get_tree().physics_frame
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	var space := node.get_world_3d().direct_space_state
	if space == null:
		return
	# Group iteration instead of SpatialGrid.query_radius — SpatialGrid
	# only allows ONE category per node, and our receivers are already
	# registered there under their primary identity (DestructibleProp →
	# "enemies", HoverableInteractable → "interactables"). The
	# `_tracked.has(node)` short-circuit in SpatialGrid.register swallowed
	# our second registration call, so the radius query came back empty
	# every time. Group iteration sees all receivers regardless.
	#
	# O(n) over total live receivers, n ~50-100 per level, distance
	# squared filter is microseconds — well below the cost of the four
	# raycasts the function will issue anyway.
	var all_receivers := node.get_tree().get_nodes_in_group(OBJECT_BLOOD_RECEIVER_GROUP)
	if all_receivers.is_empty():
		return
	var radius_sq: float = OBJECT_BLOOD_RADIUS * OBJECT_BLOOD_RADIUS
	var receivers: Array = []
	for r_var in all_receivers:
		if not (r_var is Node3D) or not is_instance_valid(r_var):
			continue
		var r := r_var as Node3D
		var d_sq := r.global_position.distance_squared_to(kill_pos)
		if d_sq <= radius_sq:
			receivers.append(r)
	if receivers.is_empty():
		return
	# Shuffle so a horde clustered next to one prop doesn't always paint
	# the same N-closest receivers — over multiple kills the paint
	# spreads naturally across the area.
	receivers.shuffle()
	var painted: int = 0
	# Visibility ray: from kill point at chest height (1 m above floor)
	# to the receiver's visual AABB center. Walls (collision layer 1)
	# block this — if the kill couldn't actually see the prop, no
	# splatter. We do NOT raycast against the prop itself: many props
	# have tiny gameplay collision shapes (the switch console is only
	# 0.7 m tall while its visible mesh is 2.5 m+), so a hit-test
	# against collision would land at floor level, not on the visible
	# geometry. Instead we trust the AABB center as the target and rely
	# on the decal's own cull_mask + projection volume to paint
	# whatever mesh-layer-8 geometry happens to be there.
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1  # WORLD only — walls block, props don't
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for receiver_var in receivers:
		if painted >= OBJECT_BLOOD_MAX_PER_KILL:
			break
		if not (receiver_var is Node3D) or not is_instance_valid(receiver_var):
			continue
		var receiver := receiver_var as Node3D
		var visual_center := _receiver_visual_center(receiver)
		# Cast from kill point at chest height to the visual center.
		# Any wall in between = skip. EXCLUDE the receiver itself —
		# decorative pillars and other receivers that opt into the
		# WORLD physics layer (so live entities collide with them)
		# would otherwise block their own visibility ray and never
		# get painted.
		# Origin near floor (0.4 m) so low ceilings in crouch tunnels
		# don't block side-paint rays through the room. The diagnostic
		# was showing kills near low-ceiling segments getting blocked
		# by overhead geometry — kill spray happens at body height,
		# below most ceiling collision.
		query.from = kill_pos + Vector3(0.0, 0.4, 0.0)
		query.to = visual_center
		query.exclude = [receiver.get_rid()] if receiver is CollisionObject3D else []
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			# Wall (or any WORLD-layer geometry) between kill and prop —
			# kill couldn't actually splatter onto it.
			continue
		# Two-decal paint per receiver:
		#   1. Side decal — horizontal kill→receiver projection. Reads on
		#      tall props (pillars, consoles, doors) where the iso camera
		#      sees the kill-facing vertical face.
		#   2. Top decal — top-down projection onto the prop's top face.
		#      Carries the splat for short flat props (loot crates,
		#      barriers, exam tables) where the iso camera mostly sees
		#      the top and the side paint lands on a barely-visible face.
		# Spawning both unconditionally means tall props get a redundant
		# top stamp on a small face (cheap, invisible) and short props
		# get the top paint they need — no per-prop classification.
		var to_recv := visual_center - kill_pos
		to_recv.y = 0.0
		var proj_normal: Vector3 = to_recv.normalized() if to_recv.length_squared() > 0.0001 else Vector3.UP
		# Side paint. Normal points OUT (toward the kill); negate so the
		# decal's +Y axis is the surface normal facing AWAY from the kill,
		# and the projection extends INTO the prop.
		_spawn_object_blood_decal(receiver, visual_center, -proj_normal, kill_pos, blood_type)
		# Top paint. Decal sits just above the AABB top-face center with
		# its +Y axis = UP. Projection depth matches the prop's height
		# (clamped) so a tall pillar's stamp doesn't reach into the floor
		# and a short crate's still covers the whole top-to-bottom range.
		var aabb := _receiver_visual_aabb(receiver)
		if aabb.size.y > 0.05:
			var top_pos := Vector3(
				visual_center.x,
				aabb.position.y + aabb.size.y,
				visual_center.z,
			)
			var top_depth := clampf(aabb.size.y, 0.4, 1.5)
			_spawn_object_blood_decal(receiver, top_pos, Vector3.UP, kill_pos, blood_type, top_depth)
		painted += 1


# AABB center of every VisualInstance3D descendant of `node`, in world
# space. Used as the splat target instead of the physics body's
# global_position because gameplay collision shapes often don't match
# visible mesh height — a console switch's 0.7 m collision box can't
# represent where its 2.5 m visible mesh actually is.
static func _receiver_visual_center(node: Node3D) -> Vector3:
	var combined := _receiver_visual_aabb(node)
	if combined.size == Vector3.ZERO:
		return node.global_position + Vector3(0.0, 0.5, 0.0)
	return combined.get_center()


# Combined world-space AABB of every VisualInstance3D descendant.
# Returns AABB(node.global_position, Vector3.ZERO) when no visuals
# resolve so the caller can detect the "no geometry" case.
static func _receiver_visual_aabb(node: Node3D) -> AABB:
	var aabbs: Array[AABB] = []
	_collect_visual_aabbs(node, aabbs)
	if aabbs.is_empty():
		return AABB(node.global_position, Vector3.ZERO)
	var combined: AABB = aabbs[0]
	for i in range(1, aabbs.size()):
		combined = combined.merge(aabbs[i])
	return combined


# Recursive walk that collects every VisualInstance3D's world-space
# AABB. AABB is a value type, so we accumulate into an Array and
# merge at the caller.
static func _collect_visual_aabbs(node: Node, out: Array[AABB]) -> void:
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		# Skip our own outline / blood copies that may have been
		# spawned earlier — they'd skew the center toward an attached
		# decal's projection volume rather than the real geometry.
		if vi.name != &"OutlineCopy":
			var aabb := vi.get_aabb()
			out.append(vi.global_transform * aabb)
	for child in node.get_children():
		_collect_visual_aabbs(child, out)


# Spawn one side-projected decal on `receiver`. Texture uses the
# wall_splatter variant (drip-oriented) because most prop hits are
# vertical surfaces; floor variants would look wrong drip-side-up on
# a chair side.
static func _spawn_object_blood_decal(receiver: Node3D, impact_pos: Vector3, impact_normal: Vector3, kill_pos: Vector3, blood_type: StringName, projection_depth: float = 1.8) -> void:
	if not is_instance_valid(receiver):
		return
	var decal := Decal.new()
	var variant := _get_blood_wall_splatter_variant(blood_type)
	decal.texture_albedo = variant[&"albedo"]
	decal.texture_normal = variant[&"normal"]
	decal.texture_orm = _get_blood_orm_texture()
	# Size falls off with distance from the kill — close hits get a big
	# stamp, farther ones get a small one. Floor at 0.6 so even max-
	# distance splats stay clearly visible.
	var dist: float = kill_pos.distance_to(impact_pos)
	var size_scale: float = clampf(1.0 - dist / (OBJECT_BLOOD_RADIUS * 1.5), 0.6, 1.0)
	# size.y is the projection DEPTH along the decal's local -Y. For
	# side projection (decal +Y = surface normal pointing back to the
	# kill), size.y is how far the projection extends INTO the prop.
	# For top-down projection (decal +Y = UP), size.y is the vertical
	# depth from the top face downward. Caller passes the right value
	# via projection_depth — 1.8 m default suits side-paint on standing
	# props; top-paint uses the AABB height clamped to a smaller cap.
	# x/z are the splat's footprint on the projected surface.
	decal.size = Vector3(
		randf_range(0.7, 1.4) * size_scale,
		projection_depth,
		randf_range(0.7, 1.4) * size_scale,
	)
	decal.modulate = _decal_color_jitter()
	decal.upper_fade = 0.08
	decal.lower_fade = 0.08
	decal.albedo_mix = OBJECT_BLOOD_ALBEDO_MIX
	decal.cull_mask = OBJECT_BLOOD_LAYER
	# Orient: decal projects along its local -Y, so build a basis whose
	# +Y axis IS the surface normal. Texture's V axis is randomly
	# twisted around that normal so adjacent stamps don't look
	# identical.
	var n := impact_normal.normalized()
	var rot := Quaternion(Vector3.UP, n)
	var twist := Basis(n, randf() * TAU)
	receiver.add_child(decal)
	decal.global_basis = twist * Basis(rot)
	# Slight push along the normal so the decal sits clear of the
	# surface (avoids z-fight on flat prop faces).
	decal.global_position = impact_pos + n * 0.03
	# Fade-and-free, same pattern as character blood.
	var tween := decal.create_tween()
	var hold: float = OBJECT_BLOOD_FADE_DURATION * 0.6
	var fade: float = maxf(OBJECT_BLOOD_FADE_DURATION - hold, 0.2)
	tween.tween_interval(hold)
	tween.tween_property(decal, "modulate:a", 0.0, fade)
	var decal_id: int = decal.get_instance_id()
	tween.tween_callback(func() -> void:
		var d := instance_from_id(decal_id) as Node
		if d != null:
			d.queue_free()
	)


# Auto-fit a collision shape to match the visible mesh's AABB. Call
# from a body's _ready when the gameplay collision should track the
# visible silhouette (most "props" — chests / consoles / pillars).
# Existing classes whose collision is INTENTIONALLY smaller / taller
# than the visible mesh (DestructibleProp's tall bullet-catch column,
# HoverableInteractable's tight click hitbox) should NOT call this —
# they author specific shapes for gameplay reasons.
#
# Behaviour:
#   1. Walk `body`'s VisualInstance3D children, union their AABBs.
#   2. Replace (or add) a CollisionShape3D child named &"AutoCollision"
#      with a BoxShape3D matching the visual AABB.
#   3. Idempotent — re-running just resizes the existing shape.
#
# If the body already has an authored CollisionShape3D, this leaves
# it alone (only the auto-collision is managed).
static func fit_collision_to_visual(body: CollisionObject3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	var aabbs: Array[AABB] = []
	_collect_visual_aabbs(body, aabbs)
	if aabbs.is_empty():
		return
	var combined: AABB = aabbs[0]
	for i in range(1, aabbs.size()):
		combined = combined.merge(aabbs[i])
	# AABB is in WORLD space — convert back to body-local for the
	# CollisionShape3D's position. body.global_transform is the body's
	# world placement; its inverse maps world → local.
	var local_center: Vector3 = body.global_transform.affine_inverse() * combined.get_center()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = combined.size
	var col := body.get_node_or_null(^"AutoCollision") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = &"AutoCollision"
		body.add_child(col)
	col.shape = shape
	col.position = local_center


# Single-call opt-in for any object that should receive blood splatter
# when an enemy dies near it. Call from the object's _ready. Handles:
#   - Group membership (OBJECT_BLOOD_RECEIVER_GROUP) for SpatialGrid queries
#   - SpatialGrid registration under that group
#   - VisualInstance3D layer opt-in (OR in OBJECT_BLOOD_LAYER on every
#     MeshInstance3D under `node`)
# Idempotent — a node already registered is a no-op. Future paintable
# object classes integrate with a single line:
#   PrototypeAttackIndicator.register_as_blood_receiver(self)
static func register_as_blood_receiver(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	# Group membership only — SpatialGrid restricts each node to a
	# single category, and our receivers are already registered there
	# under their primary identity (DestructibleProp → "enemies",
	# HoverableInteractable → "interactables", etc.). spawn_blood_on_receivers
	# iterates the group directly and filters by distance manually.
	if not node.is_in_group(OBJECT_BLOOD_RECEIVER_GROUP):
		node.add_to_group(OBJECT_BLOOD_RECEIVER_GROUP)
	_walk_or_in_visual_layer(node, OBJECT_BLOOD_LAYER)


# Single source of truth for blood decal albedo-blend factor. 1.0 =
# decal albedo fully replaces the surface; lower values let the surface
# texture/material peek through. 0.92 leaves ~8% of the underlying
# floor/prop texture visible under each splat — enough to read as
# "fluid sat on top" rather than "paint masking the surface", without
# washing out the red.
const BLOOD_DECAL_ALBEDO_MIX: float = 0.92


# Walks `node` and every descendant, ORing `layer_bit` into each
# VisualInstance3D.layers — doesn't clobber existing layer bits the
# mesh was rendered on, so the visual still renders normally and ALSO
# becomes a target for decals on the new layer.
static func _walk_or_in_visual_layer(node: Node, layer_bit: int) -> void:
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		vi.layers = vi.layers | layer_bit
	for child in node.get_children():
		_walk_or_in_visual_layer(child, layer_bit)


# ── Blood decal infrastructure ─────────────────────────────────────────

# Duration of the fade-out tween when a decal gets evicted by the ring
# buffer. Bumped 1.6 → 2.5 alongside the BLOOD_DECAL_MAX bump — at
# higher cap, more decals are evicting concurrently, and 2.5 s reads
# as a softer dissolve rather than a quick pop.
const _BLOOD_DECAL_FADE_DURATION: float = 2.5

# Visual layer that floors / walls / static world meshes occupy (default
# layer 1). Decals project onto every VisualInstance3D whose `layers`
# bit intersects this mask — so by setting every blood decal's
# cull_mask to BLOOD_DECAL_CULL_LAYER, and moving character meshes off
# that layer (see PrototypeEnemy._isolate_visual_from_decals), splats
# never paint themselves onto a moving corpse / live enemy.
const BLOOD_DECAL_CULL_LAYER: int = 1

# Character-blood decals are parented to a character's visual root so
# they follow the body as it moves. They project onto a dedicated
# visual layer (bit 3, mask = 4) that character meshes opt into via
# `_walk_set_visual_layers(visual, 2 | 4)`; world-blood decals use
# layer 1 only and ignore characters. Outline-compositor highlights
# stay on layer 20 (bit 19), unaffected. Per-character cap + fade
# tween below.
const CHARACTER_BLOOD_LAYER: int = 4
const CHARACTER_BLOOD_MAX_PER_CHAR: int = 5
const CHARACTER_BLOOD_FADE_DURATION: float = 12.0

# Object-blood pipeline. When an enemy dies, spawn_blood_on_receivers
# does a SpatialGrid radius query for nodes in OBJECT_BLOOD_RECEIVER_GROUP,
# raycasts from the kill point to each (to confirm visibility AND get
# the surface normal), then spawns a side-projected decal aimed along
# that normal onto the receiver. Each opt-in object class joins the
# group via register_as_blood_receiver() — single-line integration so
# adding new paintable objects later is friction-free.
#
# Distinct from BLOOD_DECAL_CULL_LAYER (floor — layer 1) and
# CHARACTER_BLOOD_LAYER (characters — layer 4) so the three pipelines
# don't cross-contaminate.
const OBJECT_BLOOD_LAYER: int = 8
# Higher albedo_mix specifically for object decals — props are typically
# lit much brighter than floor (no shadowing-from-ceiling, often
# direct fluorescent overhead) so the project-wide 0.92 read as
# barely-visible against bright prop materials. 0.99 pushes the decal
# nearly opaque while staying below the 1.0 "flat paint" threshold the
# memory warned about. Floor / character / wall splat decals continue
# to use BLOOD_DECAL_ALBEDO_MIX (0.92).
const OBJECT_BLOOD_ALBEDO_MIX: float = 0.96
const OBJECT_BLOOD_RECEIVER_GROUP: StringName = &"blood_receiver"
const OBJECT_BLOOD_RADIUS: float = 3.5
const OBJECT_BLOOD_MAX_PER_KILL: int = 4
const OBJECT_BLOOD_FADE_DURATION: float = 14.0
# Physics layers the kill→receiver visibility ray queries:
#   1   (WORLD)        — walls / floors (block visibility)
#   64  (INTERACTABLE) — chests / switches / doors / exits
#   128 (PILLAR)       — destructibles / decorative pillars / cover
# Without INTERACTABLE the ray passed straight through every loot
# crate / switch / door (they all sit on layer 64), so they never
# caught a hit and never painted.
const _OBJECT_BLOOD_RAY_MASK: int = 1 | 64 | 128

# Z-fight jitter range for floor decals. All floor splats sit at y=0,
# so two decals projecting onto the same floor pixel have identical
# render depth and the GPU sort is undefined — flickers when the
# camera moves. A per-spawn random Y offset in [1 mm, 15 mm] makes
# every decal's depth unique without visibly lifting them off the
# floor (the projection volume is ~40-60 cm tall, so a 1.5 cm shift
# is invisible at iso distance).
const _DECAL_Y_JITTER_MIN: float = 0.001
const _DECAL_Y_JITTER_MAX: float = 0.015
# Monotonically increasing counter applied to Decal.sorting_offset so
# every spawned blood decal has a strictly distinct sort position.
# Without this two overlapping splats compete for the same depth and
# the renderer alternates which one wins per-frame — visible as a
# z-fight flicker on settled pools. Negative step → newer decals
# render on top of older ones, which reads correctly (fresh blood
# overrides dried). Reset at level load so the counter doesn't drift
# arbitrarily far across sessions.
static var _blood_sort_counter: int = 0
const _BLOOD_SORT_STEP: float = -0.001
# Wall drip jitter — drips don't run perfectly plumb (surface texture,
# capillary action). ±15° around the vertical alignment keeps the
# downward read while looking natural.
const _WALL_DRIP_JITTER_RAD: float = PI / 12.0


# Returns the angle (radians) around `wall_normal` needed to align the
# decal's local Z axis (texture V axis) with world-down projected onto
# the wall plane — so the splatter's drip-streaks read as running down
# the wall. Returns 0 for near-horizontal surfaces (floor/ceiling
# hits) since the "down" direction has no meaning in the wall plane.
static func _wall_drip_twist_angle(wall_normal: Vector3) -> float:
	var n: Vector3 = wall_normal.normalized()
	# Horizontal surface — no gravity direction in the plane.
	if absf(n.y) > 0.95:
		return randf() * TAU
	# Default decal basis (Y-up → wall_normal via shortest-arc rotation).
	var rot_basis := Basis(Quaternion(Vector3.UP, n))
	var current_z: Vector3 = rot_basis.z
	# Project world DOWN onto the wall plane.
	var down_in_plane: Vector3 = Vector3.DOWN - n * Vector3.DOWN.dot(n)
	if down_in_plane.length_squared() < 0.0001:
		return 0.0
	down_in_plane = down_in_plane.normalized()
	var angle: float = current_z.signed_angle_to(down_in_plane, n)
	# Small twist jitter so adjacent wall splats don't look like a
	# perfectly-stenciled column of drips.
	angle += randf_range(-_WALL_DRIP_JITTER_RAD, _WALL_DRIP_JITTER_RAD)
	return angle

# Mask + margin for the wall-clamp raycasts. World layer (1) holds room
# walls, corridor walls, and ceiling. The horizontal cast at y=0.6 only
# intercepts vertical surfaces (walls + door jambs), so the floor and
# ceiling on the same layer don't interfere. Pillars sit on layer 128
# and are deliberately excluded — splatter painting on the SIDE of a
# pillar reads as "blood hit the pillar", which is fine.
const _DECAL_WALL_MASK: int = 1
# Margin pulls the clamp slightly inside the wall so the decal doesn't
# z-fight or graze the wall's collision surface.
const _DECAL_WALL_MARGIN: float = 0.1

# Returns a shrunk-to-fit decal size that won't extend past any wall
# within the requested footprint. Casts 8 rays (cardinals + diagonals)
# from the decal origin at waist height. The shortest hit distance
# determines the maximum half-extent the rotated decal can have without
# poking through a wall — sqrt(2)/2 factor accounts for the worst-case
# 45° random rotation applied at spawn.
static func _clamp_decal_size_to_walls(parent: Node, world_pos: Vector3, requested_size: Vector3) -> Vector3:
	var node := parent as Node3D
	if node == null or not node.is_inside_tree():
		return requested_size
	var space := node.get_world_3d().direct_space_state
	if space == null:
		return requested_size
	# Worst-case half-extent after a 45° Y rotation. The decal's bbox
	# corners are at half_size * sqrt(2)/2 from the center along any
	# axis after rotation, so we cast that far in every direction.
	var requested_half_extent: float = maxf(requested_size.x, requested_size.z) * 0.5 * sqrt(2.0)
	var origin := Vector3(world_pos.x, 0.6, world_pos.z)
	var dirs: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.7071, 0.0, 0.7071),
		Vector3(-0.7071, 0.0, 0.7071),
		Vector3(0.7071, 0.0, -0.7071),
		Vector3(-0.7071, 0.0, -0.7071),
	]
	var min_dist: float = requested_half_extent
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = _DECAL_WALL_MASK
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for d in dirs:
		query.from = origin
		query.to = origin + d * requested_half_extent
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_pos: Vector3 = hit["position"]
		var dist: float = origin.distance_to(hit_pos) - _DECAL_WALL_MARGIN
		if dist < min_dist:
			min_dist = dist
	# If walls are extremely close, floor the size at 0.4 m so the
	# splatter doesn't vanish entirely (a tiny dot is better than no
	# kill feedback when somebody dies pressed against a wall).
	min_dist = maxf(min_dist, 0.4)
	# Convert allowed half-extent back to axis-aligned size — divide
	# by the sqrt(2)/2 worst-case factor so the rotated bbox stays
	# within wall bounds.
	var max_axis_size: float = min_dist * 2.0 / sqrt(2.0)
	return Vector3(
		minf(requested_size.x, max_axis_size),
		requested_size.y,
		minf(requested_size.z, max_axis_size),
	)

# Stamp a new decal into the global ring. When BLOOD_DECAL_MAX is hit
# the oldest decal fades out over _BLOOD_DECAL_FADE_DURATION then
# queue_free's — no more abrupt pops when the cap is hit.
# Footprints self-free via their own tween (see spawn_blood_footprint),
# so the ring slot may hold a freed reference by the time eviction
# fires. is_instance_valid catches that before the strict-typed
# _fade_and_free signature would reject the freed Object.
# Keep-priority tiers used by the eviction scan. Higher = kept longer.
# Walls outrank floors because they're visually less likely to be
# replaced by future spawns (every future kill drops more floor blood
# but only some kills splatter the wall) AND because vertical surfaces
# carry the "this happened here" feel more strongly than yet-another
# pool on the ground.
const BLOOD_PRIORITY_FLOOR: int = 1
const BLOOD_PRIORITY_WALL: int = 2


static func _track_blood_decal(decal: Decal, keep_priority: int = BLOOD_PRIORITY_FLOOR) -> void:
	# Strictly-monotonic sorting_offset so the renderer never picks
	# between two co-positioned decals frame-to-frame. The Y jitter
	# elsewhere isn't enough — at iso distance the camera-distance
	# delta between two decals 1.5 cm apart in Y is below the depth
	# sort's practical resolution and the picker flickers. Negative
	# step → newer decals render on top of older ones, which reads
	# correctly (fresh blood overrides dried). Centralised here so
	# every spawn path (kill scene, mist droplets, wall splatter,
	# footprints) inherits the fix.
	_blood_sort_counter += 1
	decal.sorting_offset = float(_blood_sort_counter) * _BLOOD_SORT_STEP
	# Stamp the decal with keep-priority (wall vs floor), age (monotonic
	# insertion counter), and visible XZ footprint area. Eviction scan
	# sorts ascending across all three keys in that order — lowest
	# priority first (floor before wall), then smallest area (mist
	# drops before pools), then oldest (older seq before newer).
	_blood_insert_seq += 1
	decal.set_meta(&"_blood_seq", _blood_insert_seq)
	decal.set_meta(&"_blood_area", decal.size.x * decal.size.z)
	decal.set_meta(&"_blood_priority", keep_priority)
	if _blood_decal_ring.size() < BLOOD_DECAL_MAX:
		_blood_decal_ring.append(decal)
		return
	# Ring full — scan for lowest-priority entry. O(N) per eviction at
	# N = 400; ~50 decals/sec at horde scale gives ~20k comparisons/sec,
	# trivial compared to the rendering cost the eviction avoids.
	var best_idx: int = -1
	var best_priority: int = 0x7FFFFFFF
	var best_area: float = INF
	var best_seq: int = 0x7FFFFFFF
	for i in _blood_decal_ring.size():
		var slot: Variant = _blood_decal_ring[i]
		if not is_instance_valid(slot) or not (slot is Decal):
			# Stale slot (decal freed by its own tween, e.g. footprints
			# that self-free) — reuse immediately, no priority comparison.
			best_idx = i
			break
		var d := slot as Decal
		var p: int = int(d.get_meta(&"_blood_priority", BLOOD_PRIORITY_FLOOR))
		var a: float = float(d.get_meta(&"_blood_area", 0.0))
		var s: int = int(d.get_meta(&"_blood_seq", 0))
		var beats_best := false
		if p < best_priority:
			beats_best = true
		elif p == best_priority and a < best_area:
			beats_best = true
		elif p == best_priority and a == best_area and s < best_seq:
			beats_best = true
		if beats_best:
			best_priority = p
			best_area = a
			best_seq = s
			best_idx = i
	if best_idx >= 0:
		var evict: Variant = _blood_decal_ring[best_idx]
		if is_instance_valid(evict) and evict is Decal:
			_fade_and_free(evict as Decal)
		_blood_decal_ring[best_idx] = decal


# Tweens a decal's modulate.alpha to 0 over the fade duration, then
# frees it. Safe to call with a null / freed reference — the
# is_instance_valid guard short-circuits before any tween mutation.
# Detaches the decal from the ring (slot is overwritten by the caller)
# so a still-tweening decal doesn't get double-fade'd if its slot is
# re-evicted later.
static func _fade_and_free(decal: Decal) -> void:
	if not is_instance_valid(decal):
		return
	if not decal.is_inside_tree():
		decal.queue_free()
		return
	# Decals don't auto-die when the parent does; if the decal's owner
	# scene is unloading the tween would tween a soon-to-be-orphan, so
	# fall back to direct free in that case (parent removal triggers
	# free anyway).
	var tween := decal.create_tween()
	tween.tween_property(decal, ^"modulate:a", 0.0, _BLOOD_DECAL_FADE_DURATION)
	# Capture instance_id (int — value type) instead of the Decal
	# reference so the lambda doesn't trip Godot's "Lambda capture
	# freed" guard when a concurrent free path (e.g. footprint self-
	# fade) destroys the decal before this callback runs.
	var decal_id: int = decal.get_instance_id()
	tween.tween_callback(func() -> void:
		var d := instance_from_id(decal_id) as Node
		if d != null:
			d.queue_free()
	)


# ── Bloody footprints ──────────────────────────────────────────────────
#
# When the player walks through a blood splatter or pool, the next N
# footsteps leave a fading blood-stamp decal on the floor. Detection is
# distance-based against the existing _blood_decal_ring (cheap — bounded
# by BLOOD_DECAL_MAX). Footsteps.tick (called per-step by both player
# and enemy) drives the refresh + spawn cycle via two metas on the body:
# `bloody_steps_remaining` and `bloody_step_idx` (for L/R alternation
# of both lateral offset and the boot-print silhouette mirror).
# At BLOODY_FOOTSTEP_DISTANCE = 0.7 m, 10 prints cover ~7 m — about a
# room's width or one short corridor before the trail dries up. Each
# print also self-cleans via the fade timer in spawn_blood_footprint,
# so even at this count the floor doesn't accumulate trails over time.
const BLOODY_STEPS_INITIAL: int = 10
# Footprint self-fade: linger fully visible for _FOOTPRINT_HOLD seconds,
# then tween modulate.alpha to 0 over _FOOTPRINT_FADE seconds and free.
# Independent of the global _blood_decal_ring eviction so prints clean
# themselves up even when the cap hasn't been hit.
const _FOOTPRINT_HOLD: float = 6.0
const _FOOTPRINT_FADE: float = 2.5


# True if `world_pos` is inside any tracked blood decal's horizontal
# footprint. Iterates the cap-bounded ring — O(BLOOD_DECAL_MAX) which
# is ~60 distance checks max, called per-footstep so cheap.
static func is_in_blood(world_pos: Vector3) -> bool:
	for decal in _blood_decal_ring:
		if not is_instance_valid(decal):
			continue
		var dx: float = world_pos.x - decal.global_position.x
		var dz: float = world_pos.z - decal.global_position.z
		var r: float = decal.size.x * 0.5
		if dx * dx + dz * dz < r * r:
			return true
	return false


# Small floor decal at a footstep position. `intensity` (0..1) fades the
# print as the bloody-steps counter ticks down — first step after
# walking through blood is full, last step before drying is faint.
# `forward_dir` orients the print so it points along the walking
# direction (otherwise random orientation reads as "puddle drips", not
# "footprints"). `right_foot` selects between the right-foot silhouette
# and its mirror so a trail of prints alternates L/R.
static func spawn_blood_footprint(parent: Node, world_pos: Vector3, forward_dir: Vector3, intensity: float, right_foot: bool = true, blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	if parent == null or _blood_disabled():
		return
	var decal := Decal.new()
	decal.texture_albedo = _get_blood_bootprint_texture(right_foot, blood_type)
	decal.texture_orm = _get_blood_orm_texture()
	# Boot-shaped silhouette baked into the texture, so decal size is the
	# physical print footprint at iso scale: ~30 cm wide × 42 cm long.
	# Y is the vertical projection volume — kept generous so the projector
	# wraps prints onto step lips. Width tuned so the print reads as a
	# boot at iso distance, not a narrow streak.
	decal.size = Vector3(0.30, 0.4, 0.42)
	# Linear ramp from full → 10% alpha across the bloody-step counter.
	# First print after stepping in blood is full strength; each
	# successive print loses ~1/N of the alpha as the foot wipes its
	# load off, so the trail visibly dries up rather than ending
	# abruptly at a hard floor (was clamped to 0.4 — last prints looked
	# identical to mid-trail prints, making the end of the trail
	# feel like the player just stopped tracking blood).
	# Per-print brightness jitter on top of the intensity ramp — a fresh
	# print of an old foot might still vary slightly in saturation.
	decal.modulate = _decal_color_jitter(lerpf(0.1, 1.0, intensity))
	decal.upper_fade = 0.4
	decal.lower_fade = 0.4
	decal.albedo_mix = BLOOD_DECAL_ALBEDO_MIX
	decal.cull_mask = BLOOD_DECAL_CULL_LAYER
	# Orient along movement direction. forward_dir is XZ-plane; yaw is
	# atan2(x, z) so the prints point where the player is going.
	if forward_dir.length_squared() > 0.0001:
		decal.rotation.y = atan2(forward_dir.x, forward_dir.z)
	parent.add_child(decal)
	# Tiny per-spawn Y jitter to avoid z-fight against other floor decals.
	decal.global_position = Vector3(world_pos.x, randf_range(_DECAL_Y_JITTER_MIN, _DECAL_Y_JITTER_MAX), world_pos.z)
	_track_blood_decal(decal)
	# Self-fade: each print lingers for _FOOTPRINT_HOLD, then tweens
	# to alpha 0 and queue_free's. Independent of the ring buffer so
	# prints clean themselves up rather than accumulating across a
	# session — kill splatters stay (more dramatic, fewer of them),
	# footprints don't.
	var initial_alpha: float = decal.modulate.a
	var fade_tween := decal.create_tween()
	fade_tween.tween_interval(_FOOTPRINT_HOLD)
	fade_tween.tween_property(decal, ^"modulate:a", 0.0, _FOOTPRINT_FADE).from(initial_alpha)
	# Capture instance_id (int) so lambda doesn't bind to the Object —
	# see _fade_and_free for the freed-receiver race rationale.
	var decal_id: int = decal.get_instance_id()
	fade_tween.tween_callback(func() -> void:
		var d := instance_from_id(decal_id) as Node
		if d != null:
			d.queue_free()
	)


# Procedurally-baked boot print silhouette in the fluid color. Heel oval
# + arch bridge + ball/toe oval, with the bridge biased toward the outer
# edge so the arch (inner edge) curves in — that asymmetry is what
# distinguishes a right print from a left. Mirrored variant flips the
# entire shape across the centerline axis. Cached per (foot side ×
# blood_type) — at 128² each, all fluid variants together fit in a few
# hundred KB.
static func _get_blood_bootprint_texture(right_foot: bool, blood_type: StringName) -> Texture2D:
	var cache: Dictionary = _blood_bootprint_right_textures if right_foot else _blood_bootprint_left_textures
	if cache.has(blood_type):
		return cache[blood_type]
	var tex := ImageTexture.create_from_image(_make_bootprint_image(not right_foot, blood_color_for(blood_type)))
	cache[blood_type] = tex
	return tex


# Render a single 128² boot-print silhouette. Coordinate system: nx ∈
# [-1, 1] across width, ny ∈ [-1, 1] along length (ny=-1 heel, ny=+1
# toe). Combines three soft-edged primitives — heel ellipse, arch
# bridge, ball+toe ellipse — and takes the max coverage at each pixel.
# When `mirrored` is true, x is negated before evaluation, flipping the
# arch curve to the opposite side (left foot).
static func _make_bootprint_image(mirrored: bool, fluid_color: Color) -> Image:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Heel: round-ish lobe at the back.
	var heel_cx := -0.05
	var heel_cy := -0.62
	var heel_rx := 0.34
	var heel_ry := 0.30
	# Ball/toe: larger lobe at the front, offset slightly outward.
	var ball_cx := 0.06
	var ball_cy := 0.28
	var ball_rx := 0.42
	var ball_ry := 0.62
	# Arch bridge: rectangle linking heel to ball, biased toward the
	# outer edge so the inner side reads as a hollow arch.
	var bridge_y0 := -0.45
	var bridge_y1 := 0.10
	var bridge_x_inner := -0.06   # arch (inner) edge
	var bridge_x_outer := 0.22    # outer edge
	# Edge softness: ramp width over which alpha fades from 1→0. About
	# 4 px in the 128² source — projector + albedo_mix smooths further.
	var edge_ramp := 0.06
	for py in size:
		for px in size:
			var nx_raw := (float(px) / float(size - 1)) * 2.0 - 1.0
			var ny := (float(py) / float(size - 1)) * 2.0 - 1.0
			# Decal3D's V axis maps such that the image's bottom row aligns
			# with the decal's +Z (= forward_dir after the atan2 rotation
			# in spawn_blood_footprint). Place the toe at the BOTTOM of
			# the image (ny=+1) so it lands ahead of the heel along the
			# direction of travel. Using ny directly — no flip — puts
			# ball_cy=0.28 in the lower half of the image and heel_cy=-0.62
			# in the upper half.
			var ny_flipped := ny
			var x := -nx_raw if mirrored else nx_raw
			# Coverage = 1 - normalized radial distance (negative outside).
			var heel_cov: float = 1.0 - sqrt(
				pow((x - heel_cx) / heel_rx, 2.0) + pow((ny_flipped - heel_cy) / heel_ry, 2.0)
			)
			var ball_cov: float = 1.0 - sqrt(
				pow((x - ball_cx) / ball_rx, 2.0) + pow((ny_flipped - ball_cy) / ball_ry, 2.0)
			)
			# Bridge: distance to the nearest rect edge, normalized.
			var bridge_cov: float = -1.0
			if ny_flipped >= bridge_y0 and ny_flipped <= bridge_y1 and x >= bridge_x_inner and x <= bridge_x_outer:
				var dx_in := x - bridge_x_inner
				var dx_out := bridge_x_outer - x
				var dy_in := ny_flipped - bridge_y0
				var dy_out := bridge_y1 - ny_flipped
				bridge_cov = minf(minf(dx_in, dx_out), minf(dy_in, dy_out)) / 0.15
			var cov: float = maxf(maxf(heel_cov, ball_cov), bridge_cov)
			if cov <= 0.0:
				continue
			var alpha: float = clampf(cov / edge_ramp, 0.0, 1.0)
			# Fluid color comes from BLOOD_PALETTES — human red by default,
			# cyborg blue / machine oil when the source enemy bleeds those.
			img.set_pixel(px, py, Color(fluid_color.r, fluid_color.g, fluid_color.b, alpha))
	return img


# Returns one of _SPLATTER_VARIANT_COUNT cached splatter shapes for the
# blood type, picked at random. Lazily bakes every variant on first
# miss. Each variant has a matching normal map (see _get_blood_
# splatter_normal_for) keyed by the same index, so callers should use
# _get_blood_splatter_variant if they need both.
static func _get_blood_splatter_texture(blood_type: StringName) -> Texture2D:
	var variants := _ensure_splatter_variants(blood_type)
	return variants[randi() % variants.size()] as Texture2D


# Returns a {albedo, normal} pair from the variants cache — picks one
# index at random and pulls the matching textures from both arrays so
# the surface relief lines up with the splatter shape.
static func _get_blood_splatter_variant(blood_type: StringName) -> Dictionary:
	var variants := _ensure_splatter_variants(blood_type)
	var idx: int = randi() % variants.size()
	return {
		&"albedo": variants[idx],
		&"normal": (_blood_splatter_normals[blood_type] as Array)[idx],
	}


# Lazy-bakes the full variant set for a blood type. Each variant uses
# the same algorithm (lobed core + streak arms + satellite drops) with
# a different RNG seed, so they're recognizably "the same kind of
# splatter" but never identical. The normal map per variant is derived
# from the alpha gradient (see _make_splatter_normal).
static func _ensure_splatter_variants(blood_type: StringName) -> Array:
	if _blood_splatter_variants.has(blood_type):
		return _blood_splatter_variants[blood_type]
	var fluid_color := blood_color_for(blood_type)
	var albedos: Array[Texture2D] = []
	var normals: Array[Texture2D] = []
	for i in _SPLATTER_VARIANT_COUNT:
		# Coprime offset so each variant gets uncorrelated noise phases.
		var seed: int = 0x1B100D + i * 0x9E3779B9
		var albedo_img := _make_splatter_image(seed, fluid_color)
		albedos.append(ImageTexture.create_from_image(albedo_img))
		normals.append(ImageTexture.create_from_image(_make_splatter_normal(albedo_img)))
	_blood_splatter_variants[blood_type] = albedos
	_blood_splatter_normals[blood_type] = normals
	return albedos


# Wall-variant cache: same baking algorithm, but `wall_mode = true`
# pins every streak's bias direction along +V (texture down). When
# the decal's V axis is aligned with world-down at spawn (see
# _wall_drip_twist_angle), those streaks visibly run down the wall
# as gravity drips. Different seed offset from floor variants so the
# two sets don't share shapes by accident.
static func _ensure_wall_splatter_variants(blood_type: StringName) -> Array:
	if _blood_wall_splatter_variants.has(blood_type):
		return _blood_wall_splatter_variants[blood_type]
	var fluid_color := blood_color_for(blood_type)
	var albedos: Array[Texture2D] = []
	var normals: Array[Texture2D] = []
	for i in _SPLATTER_VARIANT_COUNT:
		var seed: int = 0x77A1100 + i * 0x9E3779B9
		var albedo_img := _make_splatter_image(seed, fluid_color, true)
		albedos.append(ImageTexture.create_from_image(albedo_img))
		normals.append(ImageTexture.create_from_image(_make_splatter_normal(albedo_img)))
	_blood_wall_splatter_variants[blood_type] = albedos
	_blood_wall_splatter_normals[blood_type] = normals
	return albedos


# Pulls a {albedo, normal} pair from the wall-variant cache — the wall
# equivalent of _get_blood_splatter_variant.
static func _get_blood_wall_splatter_variant(blood_type: StringName) -> Dictionary:
	var variants := _ensure_wall_splatter_variants(blood_type)
	var idx: int = randi() % variants.size()
	return {
		&"albedo": variants[idx],
		&"normal": (_blood_wall_splatter_normals[blood_type] as Array)[idx],
	}


# Bakes one splatter shape. Per-variant parameters (driven by `seed`)
# control lobe count, elongation, streak distribution, and density —
# so successive variants produce visibly different shapes instead of
# all reading as the same butterfly silhouette.
# `wall_mode` overrides the streak distribution: streaks are forced
# along the image's +V axis (downward in texture space) at near-max
# bias strength so the splat reads as gravity drips when the decal's
# V is aligned with world-down at spawn time. Used by wall splatter
# spawns; floor variants get the standard random distribution.
static func _make_splatter_image(seed: int, fluid_color: Color, wall_mode: bool = false) -> Image:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var center := Vector2(size, size) * 0.5
	# Pull per-variant shape parameters first — these are what make
	# each variant look like a different KIND of splat, not a rotation
	# of the same shape.
	# Wall mode: tighter core, more streaks, vertical elongation, and
	# nearly-pure downward bias so the splat reads as "impact blob with
	# gravity drips" rather than a radial impact.
	var core_radius_frac: float
	var primary_lobes: int
	var primary_amp: float
	var secondary_amp: float
	var elongation_axis: float
	var elongation_factor: float
	var streak_count: int
	var streak_bias_angle: float
	var streak_bias_strength: float
	var drop_count: int
	if wall_mode:
		core_radius_frac = rng.randf_range(0.10, 0.18)   # smaller blob — drips do the work
		primary_lobes = rng.randi_range(2, 5)
		primary_amp = rng.randf_range(0.10, 0.22)
		secondary_amp = rng.randf_range(0.03, 0.08)
		elongation_axis = PI * 0.5                        # force vertical elongation
		elongation_factor = rng.randf_range(1.10, 1.50)   # always elongated downward
		streak_count = rng.randi_range(10, 20)            # more drips
		streak_bias_angle = PI * 0.5                      # image-down
		streak_bias_strength = rng.randf_range(0.95, 1.0) # near-purely down
		drop_count = rng.randi_range(8, 16)
	else:
		core_radius_frac = rng.randf_range(0.14, 0.26)
		primary_lobes = rng.randi_range(2, 7)
		# Softer amplitudes than the original 0.20-0.45 / 0.05-0.18 — at
		# higher lobe counts those produced literal flower / star
		# silhouettes. 0.12-0.28 (and 0.03-0.10 secondary) reads as
		# "irregular blob" instead of "geometric petal".
		primary_amp = rng.randf_range(0.12, 0.28)
		secondary_amp = rng.randf_range(0.03, 0.10)
		# Elongation: stretches the core along a random axis. factor=1
		# is circular; factor>1 stretches that axis. Combined with
		# random lobe counts, gives ovals, peanuts, asymmetric blobs.
		elongation_axis = rng.randf() * TAU
		elongation_factor = rng.randf_range(0.75, 1.45)
		# 0 = uniform radial, 0.85 = strongly directional. Wide range so
		# some variants are balanced and some read as one-sided sprays.
		streak_count = rng.randi_range(4, 16)
		streak_bias_angle = rng.randf() * TAU
		streak_bias_strength = rng.randf_range(0.0, 0.85)
		drop_count = rng.randi_range(4, 18)
	var secondary_lobes: int = primary_lobes * 2 + rng.randi_range(0, 3)
	# Off-center core: in floor mode, the core shifts toward the spray
	# direction by a fraction of its radius — pooled blood concentrates
	# slightly past the impact point. In wall mode, the core is pinned
	# to the UPPER third of the texture so drips below it stay within
	# texture bounds.
	var core_offset_dist: float = rng.randf_range(0.0, 0.30)
	var alpha := PackedFloat32Array()
	alpha.resize(size * size)
	# ── Layer 1: lobed + elongated + off-center core ──────────────────
	var core_base_r: float = float(size) * core_radius_frac
	var phase_1: float = rng.randf() * TAU
	var phase_2: float = rng.randf() * TAU
	# Elongation basis vectors.
	var elong_dir := Vector2(cos(elongation_axis), sin(elongation_axis))
	var elong_perp := Vector2(-elong_dir.y, elong_dir.x)
	# Core position:
	#   • wall mode → upper 30% of the texture so streaks below it have
	#     room to extend down before clipping at V=1.
	#   • floor mode → near texture center, offset slightly toward the
	#     spray direction (asymmetric impact pool).
	var spray_dir := Vector2(cos(streak_bias_angle), sin(streak_bias_angle))
	var core_center: Vector2
	if wall_mode:
		core_center = Vector2(float(size) * 0.5, float(size) * 0.28)
	else:
		core_center = center + spray_dir * (core_base_r * core_offset_dist)
	for y in size:
		for x in size:
			var dx := float(x) - core_center.x
			var dy := float(y) - core_center.y
			# Project to the elongation frame, then squash the perp
			# axis by 1/elongation_factor so the splat extends along
			# elong_dir.
			var proj_along: float = dx * elong_dir.x + dy * elong_dir.y
			var proj_perp: float = (dx * elong_perp.x + dy * elong_perp.y) / elongation_factor
			var d: float = sqrt(proj_along * proj_along + proj_perp * proj_perp)
			var angle: float = atan2(proj_perp, proj_along)
			# Two harmonic components with per-variant lobe counts and
			# softened amplitudes — irregular silhouettes without
			# geometric petals.
			var perturb: float = (
				core_base_r * primary_amp * sin(angle * float(primary_lobes) + phase_1)
				+ core_base_r * secondary_amp * sin(angle * float(secondary_lobes) + phase_2)
			)
			var effective_r := core_base_r + perturb
			if d <= effective_r:
				# Softened from /3.5 → /6.0: wider alpha gradient at the
				# core's outer edge so adjacent pool stamps blend through
				# their partial-alpha rims instead of meeting at hard
				# edges. Helps the "two overlapping pools = one big pool"
				# read without changing the central body.
				var edge_t: float = clampf((effective_r - d) / 6.0, 0.0, 1.0)
				alpha[y * size + x] = maxf(alpha[y * size + x], edge_t)
	# ── Layer 2: streak arms ──────────────────────────────────────────
	# Streak origin:
	#   • wall mode → emanate from the impact blob (core_center). Drips
	#     should start at the blob's edge and trail down, not radiate
	#     from texture center.
	#   • floor mode → emanate from texture center (the impact point);
	#     core_center is the slightly-offset pool position.
	var streak_origin: Vector2 = core_center if wall_mode else center
	for i in streak_count:
		# Bias the streak direction toward streak_bias_angle by
		# streak_bias_strength. At strength 0, every streak is uniform-
		# random radial; at 0.7, most cluster within ~45° of the bias.
		var raw_angle: float = rng.randf() * TAU
		var angle: float = lerp_angle(raw_angle, streak_bias_angle, streak_bias_strength)
		# Streak length: wall drips need to be LONG (much further than
		# floor splatter streaks) to read as gravity trails; floor
		# streaks stay shorter so the splat outline isn't dominated by
		# spike arms.
		var length: float
		var base_thick: float
		if wall_mode:
			# Bounded so the drip stays inside the texture: max
			# extension = size - core_center.y - margin.
			var max_drip: float = float(size) - core_center.y - 4.0
			length = rng.randf_range(core_base_r * 1.5, max_drip)
			base_thick = rng.randf_range(0.9, 2.2)  # thin, drip-like
		else:
			length = rng.randf_range(core_base_r * 1.15, float(size) * 0.46)
			base_thick = rng.randf_range(1.4, 3.6)
		var inner: Vector2 = streak_origin + Vector2(cos(angle), sin(angle)) * (core_base_r * (0.9 if wall_mode else 0.65))
		var outer: Vector2 = streak_origin + Vector2(cos(angle), sin(angle)) * length
		var min_x: int = int(maxf(0.0, minf(inner.x, outer.x) - base_thick - 1.0))
		var max_x: int = int(minf(float(size), maxf(inner.x, outer.x) + base_thick + 1.0))
		var min_y: int = int(maxf(0.0, minf(inner.y, outer.y) - base_thick - 1.0))
		var max_y: int = int(minf(float(size), maxf(inner.y, outer.y) + base_thick + 1.0))
		var ab: Vector2 = outer - inner
		var ab_len_sq: float = maxf(ab.length_squared(), 0.0001)
		for py in range(min_y, max_y):
			for px in range(min_x, max_x):
				var p := Vector2(float(px), float(py))
				var t: float = clampf((p - inner).dot(ab) / ab_len_sq, 0.0, 1.0)
				var closest := inner + ab * t
				var d := p.distance_to(closest)
				var local_thick: float = base_thick * lerpf(1.0, 0.25, t)
				if d <= local_thick:
					var edge_t: float = clampf((local_thick - d) / 2.5, 0.0, 1.0)
					alpha[py * size + px] = maxf(alpha[py * size + px], edge_t)
		var tip_r: float = rng.randf_range(1.5, 3.5)
		var tip_min_x: int = int(maxf(0.0, outer.x - tip_r - 1.0))
		var tip_max_x: int = int(minf(float(size), outer.x + tip_r + 1.0))
		var tip_min_y: int = int(maxf(0.0, outer.y - tip_r - 1.0))
		var tip_max_y: int = int(minf(float(size), outer.y + tip_r + 1.0))
		for py in range(tip_min_y, tip_max_y):
			for px in range(tip_min_x, tip_max_x):
				var d := Vector2(float(px), float(py)).distance_to(outer)
				if d <= tip_r:
					var edge_t: float = clampf((tip_r - d) / 2.0, 0.0, 1.0)
					alpha[py * size + px] = maxf(alpha[py * size + px], edge_t)
	# ── Layer 3.5: whip streaks (the "tadpole" look) ──────────────────
	# Long, very thin curved lines ending in a small bead. These read as
	# fluid droplets that broke off the impact at high velocity and
	# stretched into a tail before landing. Distinct from Layer 2's
	# streak arms (thicker / radiating spikes) — whip streaks are 3-4×
	# longer, hair-thin, and slightly curved by a perpendicular sway.
	# Skipped on wall mode; gravity drips already cover the look there.
	if not wall_mode:
		var whip_count: int = rng.randi_range(3, 7)
		var whip_origin: Vector2 = core_center
		for i in whip_count:
			var raw_angle: float = rng.randf() * TAU
			var angle: float = lerp_angle(raw_angle, streak_bias_angle, streak_bias_strength)
			var length: float = rng.randf_range(float(size) * 0.30, float(size) * 0.48)
			var base_thick: float = rng.randf_range(0.7, 1.2)  # hair-thin
			# Perpendicular sway — small lateral arc so the whip curves
			# instead of running ruler-straight. Amplitude scales with
			# length so longer whips arc proportionally further.
			var sway_amp: float = length * rng.randf_range(0.05, 0.20)
			var sway_sign: float = 1.0 if rng.randf() < 0.5 else -1.0
			var dir := Vector2(cos(angle), sin(angle))
			var perp := Vector2(-dir.y, dir.x)
			# Sample the whip as a parametric curve; rasterize each
			# step's small thickness disc. ~24 steps gives a smooth line
			# without leaving gaps at the lowest base_thick values.
			var steps: int = 24
			var prev: Vector2 = whip_origin + dir * (core_base_r * 0.9)
			for s in range(1, steps + 1):
				var t: float = float(s) / float(steps)
				# Quadratic ease so the curve bulges outward then snaps
				# back toward the line — natural-looking whip arc.
				var sway_t: float = sin(t * PI) * sway_amp * sway_sign
				var pt: Vector2 = whip_origin + dir * (core_base_r * 0.9 + (length - core_base_r * 0.9) * t) + perp * sway_t
				# Local thickness tapers from base toward 30% of base at tail.
				var local_thick: float = base_thick * lerpf(1.0, 0.30, t)
				# Rasterize this segment as a short fat line from prev to pt.
				var seg_min_x: int = int(maxf(0.0, minf(prev.x, pt.x) - local_thick - 1.0))
				var seg_max_x: int = int(minf(float(size), maxf(prev.x, pt.x) + local_thick + 1.0))
				var seg_min_y: int = int(maxf(0.0, minf(prev.y, pt.y) - local_thick - 1.0))
				var seg_max_y: int = int(minf(float(size), maxf(prev.y, pt.y) + local_thick + 1.0))
				var ab: Vector2 = pt - prev
				var ab_len_sq: float = maxf(ab.length_squared(), 0.0001)
				for py in range(seg_min_y, seg_max_y):
					for px in range(seg_min_x, seg_max_x):
						var p := Vector2(float(px), float(py))
						var u: float = clampf((p - prev).dot(ab) / ab_len_sq, 0.0, 1.0)
						var closest := prev + ab * u
						var d := p.distance_to(closest)
						if d <= local_thick:
							var edge_t: float = clampf((local_thick - d) / 1.5, 0.0, 1.0)
							alpha[py * size + px] = maxf(alpha[py * size + px], edge_t)
				prev = pt
			# Terminal bead — bigger than the whip's tail thickness,
			# centered on the final point. Sells the "droplet at the end"
			# read.
			var bead_r: float = rng.randf_range(1.3, 2.4)
			var bead_min_x: int = int(maxf(0.0, prev.x - bead_r - 1.0))
			var bead_max_x: int = int(minf(float(size), prev.x + bead_r + 1.0))
			var bead_min_y: int = int(maxf(0.0, prev.y - bead_r - 1.0))
			var bead_max_y: int = int(minf(float(size), prev.y + bead_r + 1.0))
			for py in range(bead_min_y, bead_max_y):
				for px in range(bead_min_x, bead_max_x):
					var d := Vector2(float(px), float(py)).distance_to(prev)
					if d <= bead_r:
						var edge_t: float = clampf((bead_r - d) / 1.5, 0.0, 1.0)
						alpha[py * size + px] = maxf(alpha[py * size + px], edge_t)
	# ── Layer 3: satellite drops ──────────────────────────────────────
	# Drops follow the same directional bias as streaks so a one-sided
	# splash variant has all its drops on one side too.
	# Wall mode: drops emanate from the impact blob (not texture center)
	# and stay tightly along the downward direction — small flecks of
	# blood that broke off the main drips and ran down independently.
	var drop_origin: Vector2 = core_center if wall_mode else center
	var drop_bias_strength: float = streak_bias_strength if wall_mode else streak_bias_strength * 0.7
	for i in drop_count:
		var raw_angle: float = rng.randf() * TAU
		var angle: float = lerp_angle(raw_angle, streak_bias_angle, drop_bias_strength)
		var dist_max: float = float(size) * 0.46
		if wall_mode:
			# Cap so drops stay inside the texture below the blob.
			dist_max = minf(dist_max, float(size) - core_center.y - 4.0)
		var dist: float = rng.randf_range(core_base_r * 1.4, dist_max)
		var drop_center: Vector2 = drop_origin + Vector2(cos(angle), sin(angle)) * dist
		var drop_r: float = rng.randf_range(0.9, 2.6)
		var dx0: int = int(maxf(0.0, drop_center.x - drop_r - 1.0))
		var dx1: int = int(minf(float(size), drop_center.x + drop_r + 1.0))
		var dy0: int = int(maxf(0.0, drop_center.y - drop_r - 1.0))
		var dy1: int = int(minf(float(size), drop_center.y + drop_r + 1.0))
		for py in range(dy0, dy1):
			for px in range(dx0, dx1):
				var d := Vector2(float(px), float(py)).distance_to(drop_center)
				if d <= drop_r:
					var edge_t: float = clampf((drop_r - d) / 1.5, 0.0, 1.0)
					alpha[py * size + px] = maxf(alpha[py * size + px], edge_t)
	# ── Layer 4: micro-spray ──────────────────────────────────────────
	# Dense scatter of 1-2 pixel "specks" radiating from the impact —
	# the fine spray cloud that surrounds real splatters. Without this
	# the texture reads as "lobed blob + arms" (the flower-petal look);
	# with it, the splat gets the dotted halo that sells "high-velocity
	# fluid impact". Same directional bias as streaks/drops so a
	# one-sided variant stays one-sided.
	var spray_count: int = 80 if wall_mode else 120
	var spray_origin: Vector2 = core_center if wall_mode else center
	for i in spray_count:
		var raw_angle: float = rng.randf() * TAU
		var angle: float = lerp_angle(raw_angle, streak_bias_angle, streak_bias_strength * 0.5)
		# Distance distribution: bias toward farther distances (cube-rooted
		# uniform) so the spray clusters at the splat's outer edge rather
		# than piling in the dense core. Caps short of the texture edge.
		var dist_max: float = float(size) * 0.48
		if wall_mode:
			dist_max = minf(dist_max, float(size) - core_center.y - 3.0)
		var u: float = rng.randf()
		var dist: float = lerpf(core_base_r * 1.2, dist_max, pow(u, 0.4))
		var sp_pos: Vector2 = spray_origin + Vector2(cos(angle), sin(angle)) * dist
		var sx: int = int(sp_pos.x)
		var sy: int = int(sp_pos.y)
		if sx < 0 or sx >= size or sy < 0 or sy >= size:
			continue
		# 70% single pixel, 30% 2-pixel cluster — the bigger ones feel
		# like the smallest drops, the singles read as airborne mist.
		var speck_a: float = rng.randf_range(0.55, 1.0)
		alpha[sy * size + sx] = maxf(alpha[sy * size + sx], speck_a)
		if rng.randf() < 0.3:
			# Add one adjacent pixel at slightly lower alpha for a "soft" speck.
			var nx: int = sx + (1 if rng.randf() < 0.5 else -1)
			var ny: int = sy + (1 if rng.randf() < 0.5 else -1)
			if nx >= 0 and nx < size and ny >= 0 and ny < size:
				alpha[ny * size + nx] = maxf(alpha[ny * size + nx], speck_a * 0.7)
	for y in size:
		for x in size:
			var a: float = alpha[y * size + x]
			if a > 0.02:
				img.set_pixel(x, y, Color(fluid_color.r, fluid_color.g, fluid_color.b, a))
	return img


# Derive a tangent-space normal map from the splatter's alpha gradient.
# Where alpha is uniform (the bulk of the splat) the normal points
# straight up (0, 0, 1) — perfectly flat. Near the edge where alpha
# falls off, the gradient gives a subtle slope that reads as a wet lip
# / surface tension bead at iso angles. RGB encoding is the standard
# (x, y, z) ∈ [-1,1] → (r, g, b) ∈ [0,1] mapping Godot expects.
static func _make_splatter_normal(albedo_image: Image) -> Image:
	var size := albedo_image.get_width()
	var normal_img := Image.create(size, size, false, Image.FORMAT_RGB8)
	normal_img.fill(Color(0.5, 0.5, 1.0))  # flat normal default
	# Strength controls how pronounced the rim relief is. Subtle (1.2)
	# so the splat doesn't look 3D-modelled — just catches a hint of
	# specular at glancing angles.
	var strength: float = 1.2
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			var center_a: float = albedo_image.get_pixel(x, y).a
			if center_a < 0.05:
				continue
			var a_left: float = albedo_image.get_pixel(x - 1, y).a
			var a_right: float = albedo_image.get_pixel(x + 1, y).a
			var a_up: float = albedo_image.get_pixel(x, y - 1).a
			var a_down: float = albedo_image.get_pixel(x, y + 1).a
			var gx: float = (a_right - a_left) * 0.5
			var gy: float = (a_down - a_up) * 0.5
			# Normal slopes outward where alpha drops, giving the rim a
			# slight bevel. Negative sign so the gradient points "uphill"
			# toward the splat's interior.
			var nx: float = -gx * strength
			var ny: float = -gy * strength
			var nz: float = 1.0
			var inv_len: float = 1.0 / sqrt(nx * nx + ny * ny + nz * nz)
			nx *= inv_len
			ny *= inv_len
			nz *= inv_len
			normal_img.set_pixel(x, y, Color(
				nx * 0.5 + 0.5,
				ny * 0.5 + 0.5,
				nz,
			))
	return normal_img


# ORM texture for all blood decals. Uniform tiny image — every pixel
# carries the same surface properties because we want the entire blood
# footprint to be glossy and dielectric. The Decal node samples this
# alongside the albedo texture; where the albedo alpha is non-zero,
# this ORM data overrides the underlying floor's roughness/metallic.
# Channels: R = ambient occlusion (1 = no occlusion), G = roughness, B = metallic.
#
# Roughness history: 0.06 caught ceiling lights as bright glowing
# pixels. 0.20 softened that but on huge merged pools (post-density
# pass) the cumulative specular still read as a screen-wide mirror,
# flickering hard as the camera moved. 0.45 is a duller wet sheen —
# still reads as liquid (not matte rubber) but doesn't bake ceiling
# fluorescents into a shifting glare across pool surfaces.
static func _get_blood_orm_texture() -> Texture2D:
	if _blood_orm_texture != null:
		return _blood_orm_texture
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 0.45, 0.0))
	_blood_orm_texture = ImageTexture.create_from_image(img)
	return _blood_orm_texture


# Per-decal modulate jitter. Multiplies all three RGB channels by the
# same scalar (centered near 1.0) so the underlying palette hue is
# preserved but brightness varies across decals — simulating fresh
# arterial spray vs slightly-older venous flow. Uniform tint so
# decals still read as the same fluid. `alpha` is passed through so
# callers that already encode an intensity (footprints) preserve theirs.
static func _decal_color_jitter(alpha: float = 1.0) -> Color:
	# Narrow range (was 0.70-1.15) — the wide spread read as different
	# palettes ("dried brown" vs "fresh bright red") side by side, not
	# as subtle freshness variance. ±8% keeps a hint of variation
	# without breaking the unified red read.
	var v: float = randf_range(0.92, 1.08)
	return Color(v, v, v, alpha)


# AoE explosion burst — flipbook fireball + flash + sparks, palette-keyed
# by damage_type. All AoE projectiles route here; the elemental palette
# (kinetic / flame / cryo / electric / plasma) colors the flash, sparks,
# and omni light to match the weapon's identity.
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
# BigExplosionScene's natural visual size at scale=1 is roughly 2-3 m
# across (1 m QuadMesh × ~20 particles with small drift). RPG blasts
# at blast_radius=3-4 m should fill noticeably more than that to feel
# impactful, so the scale formula maps blast_radius directly to scale
# with a generous max — a Tactical Strike at 9 m hits the clamp and
# still reads as a huge kaboom.
const FLIPBOOK_SCALE_FLOOR: float = 1.5
const FLIPBOOK_SCALE_CEILING: float = 5.0
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
	&"plasma": {  # plasma burst — white-cyan core, cyan mid, deep teal rim
		"core": Color(0.9, 1.0, 1.0),
		"mid": Color(0.3, 0.85, 1.0),
		"outer": Color(0.05, 0.35, 0.55),
		"smoke": Color(0.10, 0.16, 0.20),
		"light": Color(0.4, 0.85, 1.0),
	},
}

static func spawn_explosion(host: Node3D, world_pos: Vector3, blast_radius: float, _color_override: Color = Color(0, 0, 0, 0), damage_type: StringName = &"") -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	# Detect enemy-sourced explosions: projectile target_group == &"player"
	# means an enemy fired it. Player hosts or non-projectile hosts stay
	# full-intensity.
	var is_enemy := false
	if host is PrototypeProjectile:
		is_enemy = (host as PrototypeProjectile).target_group == &"player"
	elif not host.is_in_group(&"player"):
		is_enemy = true
	_spawn_fireball_explosion(parent, world_pos, blast_radius, damage_type, is_enemy)


## Flipbook-driven explosion using the BigExplosionScene's pre-baked
## 8×8 sprite-sheet (smokesprite.png) + normal maps for lighting. The
## scene itself owns the GPUParticles3D and the material's UV
## animation; we just instantiate it, scale to blast radius, and
## stack the supporting layers (omni light, sparks, instant flash) on
## top. The flipbook includes its own smoke-dispersal phase as the
## sprite ages, so we don't spawn a separate procedural smoke layer.
static func _spawn_fireball_explosion(parent: Node, world_pos: Vector3, blast_radius: float, damage_type: StringName = &"", is_enemy: bool = false) -> void:
	var palette: Dictionary = FIREBALL_PALETTES.get(damage_type, FIREBALL_PALETTES[&""])
	var is_kinetic: bool = damage_type == &"" or damage_type == &"flame"

	var fx: Node3D = FLIPBOOK_EXPLOSION_SCENE.instantiate() as Node3D
	fx.scale = Vector3.ONE * clampf(blast_radius, FLIPBOOK_SCALE_FLOOR, FLIPBOOK_SCALE_CEILING)

	# Speed up the flipbook by shortening particle lifetime BEFORE the
	# node enters the tree (so the particle emits at the new speed).
	# The sprite sheet's last frames naturally fade to alpha 0, so faster
	# playback = quicker smoke that ends gracefully — no hard cuts.
	# Kinetic gets a modest speedup; energy types play ~2× faster so the
	# smoke reads as dissipating energy rather than lingering particulate.
	var particles: GPUParticles3D = fx.get_node(^"Explosion1") as GPUParticles3D
	var anim_lifetime: float = 1.4 if is_kinetic else 0.9
	if particles != null:
		# The flipbook quad faces the camera. With the OmniLight added below
		# at energy 40 and shadow_enabled, the quad's back-face threw a
		# huge wedge of shadow across everything outside the blast radius
		# — the user saw it as "the whole room goes black except the
		# smoke." Particles aren't physical shadow casters; disable.
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Also keep the quad out of SDFGI: default gi_mode is STATIC, so
		# SDFGI voxelizes the camera-facing quad as a solid wall for the
		# duration of the particle's life. That carves a 8x8m occluder
		# into the indirect-light cascade right at the explosion center,
		# which renders as a dark rectangle dimming the floor underneath
		# (the issue that appeared once SDFGI was re-enabled — explosions
		# worked fine before because SDFGI wasn't sampling the quads).
		particles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		particles.lifetime = anim_lifetime
		# Recolor the flipbook to match the palette. The shader has two
		# gradient lookups keyed on sprite brightness:
		#   tex_frg_26 → EMISSION (fire/smoke color)
		#   tex_frg_27 → ALBEDO   (base tint, default white)
		# We duplicate the material and replace both so the entire explosion
		# — fire core, mid ring, and trailing smoke — reads in-palette.
		var mat: ShaderMaterial = particles.material_override.duplicate() as ShaderMaterial
		var smoke: Color = palette["smoke"]
		var em_grad := Gradient.new()
		em_grad.offsets = PackedFloat32Array([0.0, 0.017, 0.38, 0.461, 0.55, 0.602, 1.0])
		em_grad.colors = PackedColorArray([
			Color(smoke.r, smoke.g, smoke.b, 0.0),  # very dark → smoke (transparent edge)
			Color(smoke.r, smoke.g, smoke.b, 1.0),  # dark → smoke
			palette["core"],                          # bright centre
			palette["mid"],                           # mid ring
			palette["outer"],                         # rim
			smoke,                                    # fade to smoke
			smoke,                                    # hold smoke
		])
		var em_tex := GradientTexture1D.new()
		em_tex.gradient = em_grad
		mat.set_shader_parameter(&"tex_frg_26", em_tex)
		var alb_grad := Gradient.new()
		alb_grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		alb_grad.colors = PackedColorArray([
			smoke,                      # dark → smoke tint
			Color(0.7, 0.7, 0.7, 1.0), # mid → neutral
			Color(1.0, 1.0, 1.0, 1.0), # bright → white
		])
		var alb_tex := GradientTexture1D.new()
		alb_tex.gradient = alb_grad
		mat.set_shader_parameter(&"tex_frg_27", alb_tex)
		# Enemy-sourced explosions are ~50% transparent so they don't
		# overpower player VFX. The shader's alpha_multiplier uniform
		# is authoritative here; we also halve the emission falloff so
		# the glow is proportionally dimmer.
		if is_enemy:
			mat.set_shader_parameter(&"alpha_multiplier", 0.5)
		particles.material_override = mat
		# GPU particles ignore parent node scale (local_coords=false), so
		# resize the draw pass QuadMesh directly. Energy explosions use a
		# small quad — the flash/sparks carry the blast visual; the
		# flipbook is just a brief residual puff.
		if not is_kinetic:
			var quad: QuadMesh = particles.draw_pass_1.duplicate() as QuadMesh
			quad.size = Vector2(3, 3)  # down from 8×8
			particles.draw_pass_1 = quad

	# Add to tree after configuring — particle emits on first frame.
	parent.add_child(fx)
	fx.global_position = world_pos
	fx.get_tree().create_timer(anim_lifetime + 0.3).timeout.connect(_free_later(fx))

	# Omni light pulse — surrounding floor / walls / enemies light up
	# in the explosion's color. Two-stage fade: peak holds briefly at
	# 40, drops to a sustained glow at 14 over 0.15s, then trails to
	# zero. The light is added to parent (NOT fx) because fx is scaled
	# to blast_radius and Godot scales OmniLight range with node
	# transform — parenting to the unscaled level node keeps the range
	# predictable.
	# Enemy-sourced explosions halve all visual intensity so they don't
	# overpower player VFX at horde scale.
	var intensity_mult := 0.5 if is_enemy else 1.0

	var light := _acquire_light()
	light.light_color = palette["light"]
	light.light_energy = 40.0 * intensity_mult
	# Was blast_radius * 3.5 (≈17m for an RPG). At that range the light spilled
	# through doorways into adjacent corridors and lit up rooms the player
	# hasn't explored — visible even with shadows on because the geometry is
	# line-of-sight through the door opening. The flipbook mesh + sparks already
	# carry the "this is a huge blast" visual; the light just needs to brighten
	# the immediate blast vicinity, not project 17m across the level.
	light.omni_range = blast_radius * 1.5
	light.omni_attenuation = 0.9
	# Shadows enabled (was false) so the blast doesn't pour energy through
	# walls and light up the OUTER faces of any room near the explosion.
	# The light tweens out over EXPLOSION_DURATION (~1s) so the cubemap
	# shadow render cost is bounded — only one explosion light at a time
	# per blast, with intensity tweening down fast.
	light.shadow_enabled = true
	light.shadow_bias = 0.005
	light.shadow_normal_bias = 0.5
	# Was 0.25 — caused the V-halo through walls / past void cover every
	# time an explosion fired. Volumetric fog scatter ignores shadow casters,
	# so any non-zero value here bleeds into the screen-space fog pass and
	# brightens the void around the level. The explosion's mesh/particle
	# visuals carry the "explosion is bright" cue on their own.
	light.light_volumetric_fog_energy = 0.0
	parent.add_child(light)
	light.global_position = world_pos

	var light_tween := light.create_tween()
	light_tween.tween_property(light, "light_energy", 14.0 * intensity_mult, 0.15).set_ease(Tween.EASE_OUT)
	light_tween.tween_property(light, "light_energy", 0.0, EXPLOSION_DURATION).set_ease(Tween.EASE_IN)
	light_tween.tween_callback(_release_light_later(light))

	# Instant flash sphere — bright unshaded white-hot pop that
	# precedes the flipbook's first visible frame. Reads as the
	# detonation flash at iso distance even when the flipbook quads
	# haven't fully oriented to camera yet.
	_spawn_explosion_flash(parent, world_pos, blast_radius, palette["core"], intensity_mult)
	# Sparks — bright radial dots flying outward, short lifetime, low
	# gravity. Reads as flying debris / hot fragments.
	_spawn_explosion_sparks(parent, world_pos, blast_radius, palette["mid"], intensity_mult)


# Instant white-hot pop at the impact point — separate from the
# fireball shader so it's guaranteed to register even if the shader's
# fresnel + age fade hides the orange ball at certain angles. Sphere
# uses an unshaded high-emission StandardMaterial so it bloom-glows
# regardless of palette or volumetric fog density.
static func _spawn_explosion_flash(parent: Node, world_pos: Vector3, blast_radius: float, core_tint: Color, intensity_mult: float = 1.0) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = blast_radius * 0.35
	mesh.height = blast_radius * 0.7
	mesh.radial_segments = 16
	mesh.rings = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(core_tint.r, core_tint.g, core_tint.b, 0.9 * intensity_mult)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = core_tint
	mat.emission_energy_multiplier = 6.0 * intensity_mult
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Start small so it pops into existence, scale up + fade fast.
	inst.scale = Vector3.ONE * 0.3
	parent.add_child(inst)
	inst.global_position = world_pos
	var tween := inst.create_tween().set_parallel(true)
	tween.tween_property(inst, "scale", Vector3.ONE * 1.4, EXPLOSION_FLASH_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(mat, "albedo_color:a", 0.0, EXPLOSION_FLASH_DURATION).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, EXPLOSION_FLASH_DURATION).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(_free_later(inst))


# Bright outward-spraying spark particles. One-shot burst sized to the
# blast radius. Particles don't follow the parent so they survive the
# fireball mesh's queue_free.
static func _spawn_explosion_sparks(parent: Node, world_pos: Vector3, blast_radius: float, tint: Color, intensity_mult: float = 1.0) -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = clampi(int(round(blast_radius * 6.0)), 12, 48)
	particles.lifetime = EXPLOSION_SPARK_LIFETIME
	particles.explosiveness = 1.0
	particles.local_coords = false
	# Sparks don't cast shadow — same reason the main flipbook quad doesn't:
	# the explosion's OmniLight at energy 40 would project shadow tracks
	# from each spark across the room, darkening huge swathes of geometry.
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Same SDFGI exclusion as the flipbook quad — sparks are transient,
	# voxelizing them as STATIC GI makes them carve flickering occluders
	# into the cascade.
	particles.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

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
	mat.albedo_color = Color(tint.r, tint.g, tint.b, intensity_mult)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 4.0 * intensity_mult
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if intensity_mult < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	particles.draw_pass_1 = mesh

	# Add to tree BEFORE setting global_position — the setter walks the
	# scene tree to convert into local coords, so doing it pre-parent
	# trips "!is_inside_tree()" and silently leaves the node at origin.
	parent.add_child(particles)
	particles.global_position = world_pos
	# Cleanup after the burst — lifetime is short, but pad so the tail
	# fully fades.
	particles.get_tree().create_timer(EXPLOSION_SPARK_LIFETIME + 0.2).timeout.connect(_free_later(particles))


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
	tween.chain().tween_callback(_release_light_later(light))
	tween.chain().tween_callback(_free_later(inst))


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
	tween.tween_callback(_free_later(inst))


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
	t.tween_callback(_free_later(p))


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
	tween.tween_callback(_free_later(inst))

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
	tween.chain().tween_callback(_free_later(node))

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
	tween.tween_callback(_free_later(node))

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
	tween.tween_callback(_release_light_later(light))


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
