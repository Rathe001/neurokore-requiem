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
static var _beam_core_unit_mesh: CylinderMesh = null
static var _beam_glow_unit_mesh: CylinderMesh = null
# Impact-burst shared resources — see spawn_impact_burst. Flash material
# templates + spark bundles are keyed by color (small set: class colors
# + elemental tints); the curve texture and flash mesh are singletons.
static var _impact_flash_mesh: SphereMesh = null
static var _impact_flash_mat_cache: Dictionary = {}
static var _impact_spark_cache: Dictionary = {}
static var _impact_spark_curve_tex: CurveTexture = null
# Blood-burst shared resources — keyed by blood_type (3 entries).
static var _blood_burst_cache: Dictionary = {}
static var _blood_burst_curve_tex: CurveTexture = null
# Beam material templates keyed by Color — duplicated per use for tween animation.
static var _beam_core_mat_cache: Dictionary = {}
static var _beam_glow_mat_cache: Dictionary = {}
# Reusable pool of OmniLight3D for impact/beam/explosion effects. Avoids
# creating hundreds of light nodes per frame during horde-scale combat.
static var _light_pool: Array[OmniLight3D] = []
const _LIGHT_POOL_MAX := 32

# ── Material rings ─────────────────────────────────────────────────────
# Round-robin pools of pre-duplicated materials, keyed by template RID.
# Creating a material RID mid-frame forces a ~25ms render-thread sync
# (the laser-pistol hitch, d0a92e4) — so per-event effects must NEVER
# duplicate() at spawn time. A ring hands out the next pre-made
# duplicate; an entry is only reused after `size` further spawns, long
# after these ≤0.5s effects have faded. The whole ring is built on
# first use — one sync stall per template per session instead of one
# per event. CONTRACT for callers: reset every per-instance shader
# param at spawn (a reused entry carries the previous effect's values).
static var _mat_rings: Dictionary = {}
static var _shockwave_mat_template: ShaderMaterial = null
static var _crater_mat_template: ShaderMaterial = null
static var _fireball_mat_cache: Dictionary = {}  # [damage_type, is_enemy] -> ShaderMaterial
static var _explosion_flash_mesh: SphereMesh = null
static var _explosion_flash_mat_cache: Dictionary = {}  # [tint, intensity] -> template
static var _explosion_spark_cache: Dictionary = {}  # [tint, intensity] -> {pm template, mesh}
static var _debris_unit_mesh: BoxMesh = null
static var _debris_mats: Array = []  # pre-baked grey variants

static func _ring_material(template: Material, size: int = 12) -> Material:
	var key: RID = template.get_rid()
	var ring: Dictionary = _mat_rings.get(key, {})
	if ring.is_empty():
		var mats: Array = []
		for _i in size:
			mats.append(template.duplicate())
		ring = {"mats": mats, "i": 0}
		_mat_rings[key] = ring
	var i: int = ring["i"]
	ring["i"] = (i + 1) % (ring["mats"] as Array).size()
	return ring["mats"][i]

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
	# Ring of 4 — markers live a few seconds but the skill is on a 30s
	# cooldown, so concurrent markers never approach the ring size.
	var mat: ShaderMaterial = _ring_material(_get_airstrike_marker_material_template(), 4)
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
## `attach_to_host` parents the arc plane to `host` so the arc midpoint
## tracks with the firing entity (used for taser CHAIN_LIGHTNING channel
## arcs that fire many in succession while the player moves; without
## this the arcs visibly snap to lagged positions every tick).
static func spawn_lightning_arc(host: Node3D, from_pos: Vector3, to_pos: Vector3, duration: float = LIGHTNING_ARC_DURATION, tint_override: Color = Color(0.0, 0.0, 0.0, 0.0), attach_to_host: bool = false) -> void:
	if host == null:
		return
	var parent: Node = host if attach_to_host else host.get_parent()
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
	var mat: ShaderMaterial = _ring_material(_get_lightning_arc_material_template()) as ShaderMaterial
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
	# Ring contract: ALWAYS set effect_color — a reused ring entry holds
	# the previous arc's tint. No-override falls back to the shader's
	# authored default (lightning_arc.gdshader: 0.55, 0.85, 1.0).
	if tint_override.a > 0.0:
		mat.set_shader_parameter(&"effect_color", Vector3(tint_override.r, tint_override.g, tint_override.b))
	else:
		mat.set_shader_parameter(&"effect_color", Vector3(0.55, 0.85, 1.0))
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


## `attach_to_host` parents the beam container to `host` so the start
## tracks the firing entity as it moves during the beam's BEAM_FADE
## window. Trade-off: impact + mid lights ride along with the container
## too, so they shift slightly off the original hit point during the
## fade — at 0.18s + sprint speed that's at most ~1.4m of drift, which
## reads as a snappy laser-style sweep rather than the previous "frozen
## tracer left behind" look. Default false for enemy compat.
static func spawn_beam(host: Node3D, aim: Vector3, length: float, origin: Vector3 = Vector3.ZERO, tint_override: Color = Color(0.0, 0.0, 0.0, 0.0), attach_to_host: bool = false) -> void:
	var parent: Node = host if attach_to_host else host.get_parent()
	if parent == null:
		parent = host
	# tint_override with non-zero alpha overrides the host's class
	# color — used for elemental weapons (flame red, cryo cyan, etc.)
	# so the beam reads as the weapon's element regardless of player
	# class. Zero-alpha = "no override" and falls back to class color.
	var color := tint_override if tint_override.a > 0.0 else _color_for_host(host)

	# Core beam — bright, slightly transparent cylinder. Shared unit mesh,
	# stretched to length via instance scale (see _beam_core_mesh).
	var core_mat := _beam_core_material(color)
	var core := MeshInstance3D.new()
	core.mesh = _beam_core_mesh()
	core.scale = Vector3(1.0, length, 1.0)
	core.material_override = core_mat

	# Outer glow — wider, softer, more transparent.
	var glow_mat := _beam_glow_material(color)
	var glow := MeshInstance3D.new()
	glow.mesh = _beam_glow_mesh()
	glow.scale = Vector3(1.0, length, 1.0)
	glow.material_override = glow_mat

	# Container node — cylinder height runs along local Y, so rotate -90° on X
	# to align with local -Z (the look_at forward), then offset by half length.
	var node := Node3D.new()
	parent.add_child(node)
	# Beam emerges from the explicit `origin` (the weapon's actual muzzle
	# tip when available). Falls back to chest-height on the host when
	# the caller didn't compute one (Vector3.ZERO sentinel).
	var beam_start: Vector3 = origin if origin != Vector3.ZERO else host.global_position + Vector3(0.0, 1.0, 0.0)
	node.global_position = beam_start
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

	# Fade via per-instance transparency — the shared template materials
	# are never mutated (see _beam_core_material).
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(core, "transparency", 1.0, BEAM_FADE).set_ease(Tween.EASE_IN)
	tween.tween_property(glow, "transparency", 1.0, BEAM_FADE).set_ease(Tween.EASE_IN)
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
	# Shared mesh + per-color material template (duplicated for the fade
	# tween). This fires on EVERY hit; allocating a fresh SphereMesh +
	# material each time was part of the per-shot hitch.
	if _impact_flash_mesh == null:
		_impact_flash_mesh = SphereMesh.new()
		_impact_flash_mesh.radius = IMPACT_FLASH_RADIUS
		_impact_flash_mesh.height = IMPACT_FLASH_RADIUS * 2.0
		_impact_flash_mesh.radial_segments = 12
		_impact_flash_mesh.rings = 6
	var flash_template: StandardMaterial3D = _impact_flash_mat_cache.get(color)
	if flash_template == null:
		flash_template = StandardMaterial3D.new()
		# Core color is a brighter, desaturated version of the projectile
		# color so the pop reads as white-hot center fading to the accent.
		var core := Color(
			lerpf(color.r, 1.0, 0.6),
			lerpf(color.g, 1.0, 0.6),
			lerpf(color.b, 1.0, 0.6),
			0.9)
		flash_template.albedo_color = core
		flash_template.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flash_template.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flash_template.emission_enabled = true
		flash_template.emission = Color(core.r, core.g, core.b)
		flash_template.emission_energy_multiplier = 5.0
		flash_template.cull_mode = BaseMaterial3D.CULL_DISABLED
		_impact_flash_mat_cache[color] = flash_template
	# SHARED template — never duplicated (material RID creation per hit
	# forces a ~25ms render-thread sync; see the beam/pulse comments).
	# Fade rides GeometryInstance3D.transparency below.
	var flash_inst := MeshInstance3D.new()
	flash_inst.mesh = _impact_flash_mesh
	flash_inst.material_override = flash_template
	flash_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_inst.scale = Vector3.ONE * 0.3
	parent.add_child(flash_inst)
	flash_inst.global_position = world_pos

	var flash_tween := flash_inst.create_tween().set_parallel(true)
	flash_tween.tween_property(flash_inst, "scale", Vector3.ONE * 1.4, IMPACT_FLASH_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	flash_tween.tween_property(flash_inst, "transparency", 1.0, IMPACT_FLASH_DURATION).set_ease(Tween.EASE_IN)
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
	# Process material + draw mesh are never mutated after creation, so
	# they're fully shareable per color. The old code built a fresh
	# ParticleProcessMaterial + Curve + CurveTexture + SphereMesh +
	# StandardMaterial3D on EVERY hit — the CurveTexture alone is a GPU
	# texture upload per shot.
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = IMPACT_SPARK_COUNT
	particles.lifetime = IMPACT_SPARK_LIFETIME
	particles.explosiveness = 1.0
	particles.local_coords = false

	var spark_bundle: Dictionary = _impact_spark_cache.get(color, {})
	if spark_bundle.is_empty():
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
		if _impact_spark_curve_tex == null:
			var curve := Curve.new()
			curve.add_point(Vector2(0.0, 1.0))
			curve.add_point(Vector2(0.6, 0.4))
			curve.add_point(Vector2(1.0, 0.0))
			_impact_spark_curve_tex = CurveTexture.new()
			_impact_spark_curve_tex.curve = curve
		pm.scale_curve = _impact_spark_curve_tex
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
		spark_bundle = {"pm": pm, "mesh": spark_mesh}
		_impact_spark_cache[color] = spark_bundle
	particles.process_material = spark_bundle["pm"]
	particles.draw_pass_1 = spark_bundle["mesh"]

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
## Bumped 4 → 12. Each variant is one procedurally-generated splat
## shape (different lobe count / streak directions / drop pattern).
## At 4, clustered kills repeatedly stamped the same 4 templates and
## the eye picked up on the repetition — pools read as "fake stamps."
## 12 variants × random Y rotation × per-spawn aspect-ratio jitter
## gives enough combinations that no two pools side-by-side look the
## same. Memory cost: ~512KB extra (8 extra variants × 128² RGBA8 ×
## 2 maps each).
static var _blood_orm_texture: Texture2D = null
# Single gate for every blood spawn path. Players who flip
# AccessibilityState.config.disable_blood in settings get a clean
# combat presentation — hit-flash + damage numbers + sounds still
# fire (those carry the actual feedback information), but no decals,
# no mist particles, no bloody footprints. Hit early so we don't pay
# any setup cost for visuals that won't appear.
static func _blood_disabled() -> bool:
	return AccessibilityState.config != null and AccessibilityState.config.disable_blood


## `mist_sample_override` (default -1 = "use count_mult-derived
## sample_count") lets per-hit callers cap floor stamps at 1 drop
## while death-scene callers keep the wider 2-6 spread.
static func spawn_blood_burst(parent: Node, world_pos: Vector3, direction: Vector3 = Vector3.UP, count_mult: float = 1.0, blood_type: StringName = BLOOD_TYPE_HUMAN, mist_sample_override: int = -1) -> void:
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

	# Cached per blood_type — this fires on EVERY hit, and building a
	# fresh ParticleProcessMaterial + Curve + CurveTexture + SphereMesh
	# + StandardMaterial3D per hit was the same per-shot GPU-allocation
	# class as the laser-pistol hitch (82c37ce). The pm template is
	# DUPLICATED per burst because direction + velocity vary per call
	# and same-frame multi-hits (shotgun pellets) would stomp a shared
	# one; the duplicate is CPU-only — the shared scale-curve texture
	# and draw mesh are referenced, not copied.
	var bundle: Dictionary = _blood_burst_cache.get(blood_type, {})
	if bundle.is_empty():
		var pm_t := ParticleProcessMaterial.new()
		# Tight emission origin — small sphere reads as "from the wound"
		# at iso scale. The cone spread below is what shapes the spray.
		pm_t.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm_t.emission_sphere_radius = 0.04
		# Spread is the half-angle around `direction`, so 25° gives a
		# 50° cone — narrow enough to read as a focused exit-wound jet.
		pm_t.spread = 25.0
		# Strong gravity so droplets arc back down quickly.
		pm_t.gravity = Vector3(0.0, -12.0, 0.0)
		pm_t.damping_min = 0.5
		pm_t.damping_max = 2.0
		# scale_min/max is a MULTIPLIER on the mesh size: 0.7-1.3 gives
		# natural per-droplet variation around the 0.035m base radius.
		pm_t.scale_min = 0.7
		pm_t.scale_max = 1.3
		# Droplet color = palette base (same dark venous tone the floor
		# splatters use); visibility comes from the emission term below.
		var droplet_color := blood_color_for(blood_type)
		pm_t.color = droplet_color
		# Droplets shrink as they travel — masks the moment they vanish.
		if _blood_burst_curve_tex == null:
			var curve := Curve.new()
			curve.add_point(Vector2(0.0, 1.0))
			curve.add_point(Vector2(0.8, 0.7))
			curve.add_point(Vector2(1.0, 0.0))
			_blood_burst_curve_tex = CurveTexture.new()
			_blood_burst_curve_tex.curve = curve
		pm_t.scale_curve = _blood_burst_curve_tex
		# Sphere mesh — small droplets read as quick mist. Emission at
		# 3.5 keeps the dark blood hue readable at iso distance (2.0 was
		# invisible against dim floors, 4.0 read as detached crimson).
		var droplet_mesh := SphereMesh.new()
		droplet_mesh.radius = 0.035
		droplet_mesh.height = 0.07
		droplet_mesh.radial_segments = 5
		droplet_mesh.rings = 3
		var droplet_mat := StandardMaterial3D.new()
		droplet_mat.albedo_color = droplet_color
		droplet_mat.emission_enabled = true
		droplet_mat.emission = droplet_color
		droplet_mat.emission_energy_multiplier = 3.5
		droplet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		droplet_mesh.material = droplet_mat
		bundle = {"pm": pm_t, "mesh": droplet_mesh}
		_blood_burst_cache[blood_type] = bundle
	# Ring, not duplicate — ParticleProcessMaterial is a Material, so a
	# per-burst duplicate() was a render-thread sync ON EVERY HIT (the
	# laser-hitch class). Direction/velocity only matter on the emit
	# frame (one_shot + explosiveness=1 snapshots them per particle), so
	# ring reuse 12 bursts later can't disturb in-flight droplets.
	var pm := _ring_material(bundle["pm"]) as ParticleProcessMaterial
	pm.direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	pm.initial_velocity_min = BLOOD_BURST_SPEED_MIN * count_mult
	pm.initial_velocity_max = BLOOD_BURST_SPEED_MAX * count_mult
	particles.process_material = pm
	particles.draw_pass_1 = bundle["mesh"]

	parent.add_child(particles)
	particles.global_position = world_pos
	# Free shortly after the last particle dies. lifetime + small tail.
	particles.get_tree().create_timer(BLOOD_DROPLET_LIFETIME + 0.3).timeout.connect(_free_later(particles))
	# Per-droplet landing decals — sample N trajectories within the
	# burst cone and place a tiny drop at each predicted landing point.
	# Fire-and-forget: the function awaits a process frame internally so
	# its raycasts run safely outside any active physics-signal flush.
	_paint_mist_droplets(parent, world_pos, pm.direction, blood_type, count_mult, mist_sample_override)


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
static func _paint_mist_droplets(parent: Node, origin: Vector3, direction: Vector3, blood_type: StringName, count_mult: float, sample_override: int = -1) -> void:
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
	var sample_count: int = sample_override if sample_override >= 0 else clampi(int(round(2.0 * count_mult)), 2, 6)
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


# Per-hit wall drop — small speck routed through the same WallLiquidLayer
# pipeline as splatters. Smaller radius and reduced intensity so a
# fight's worth of specks doesn't saturate the mask.
static func _spawn_mist_drop_wall(parent: Node, world_pos: Vector3, wall_normal: Vector3, _blood_type: StringName) -> void:
	if wall_normal.length_squared() < 0.0001:
		return
	var layer := _find_wall_liquid_layer(parent)
	if layer == null:
		return
	var radius: float = randf_range(0.05, 0.10)
	layer.stamp(world_pos, wall_normal, radius, 0.7)


# ── Floor pools via LiquidLayer ───────────────────────────────────────
# Floor pools are now rasterized into a persistent SubViewport mask
# owned by LiquidLayer (one per fluid type) and rendered by a single
# floor plane through liquid_surface.gdshader. The old per-pool Decal +
# tween-grow + proximity-attach system was replaced because adjacent
# decals showed visible silhouette seams that couldn't be hidden no
# matter how the alpha falloff was tuned.
#
# Slip-zone Area3D for the Traction gameplay hook is created separately
# at corpse settle (see PrototypeEnemy._spawn_settle_pool) — it no
# longer rides on a per-pool Decal node.
#
# Mist-drop pool radii — small per-hit stamps that build up over a
# busy fight. Tuned for visibility into the LiquidLayer mask (anything
# smaller gets eaten by the shader's coverage threshold).
const _MIST_POOL_RADIUS_MIN: float = 0.10
const _MIST_POOL_RADIUS_MAX: float = 0.22
# Kill-scene central pool — bigger single stamp at the kill point.
# Settle pools (under the corpse after death-anim ends) use their own
# radius set on the PrototypeEnemy side.
const _KILL_POOL_RADIUS: float = 0.55

# ── Blood as a "ground effect" ────────────────────────────────────────
# Blood pools behave like a Divinity-style environmental floor type:
# walking through one applies a mild slow + friction loss + stumble
# chance, all mitigated by the per-surface Traction curve (see
# traction.gd's GROUND_EFFECT_PROFILES for the blood profile values
# and the half-mit `k` that drives the asymptotic decay).
#
# Future ground types (frozen, oil, fire) follow the same Area3D +
# enter/exit pattern with their own profile entry — frozen will reuse
# this slip-friction model with a much heavier `k` so endgame players
# still feel ice underfoot.
#
# Player-only by design — enemies don't have a Traction stat to
# mediate against. If we ever want slipping enemies, add the Enemy
# layer to BLOOD_POOL_PLAYER_MASK + give PrototypeEnemy an
# enter/exit_blood_pool pair.
const BLOOD_POOL_AREA_HEIGHT: float = 0.9
const BLOOD_POOL_PLAYER_MASK: int = 4      # Layer 3 = Player


static func spawn_blood_kill_scene(parent: Node, world_pos: Vector3, _spray_dir: Vector3 = Vector3.ZERO, blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	if parent == null or _blood_disabled():
		return
	# Floor pool — stamped into the LiquidLayer for the blood type.
	spawn_blood_decal(parent, world_pos, blood_type)
	# Side-paint nearby props / interactables / pillars.
	spawn_blood_on_receivers(parent, world_pos, blood_type)


# Stamp a floor pool at world_pos via the LiquidLayer for `blood_type`.
# Replaces the old decal-pool spawn path entirely — overlapping stamps
# merge in the SubViewport mask, so there's no need for the
# attach-or-grow logic the old system used to hide inter-pool seams.
#
# `parent` / `force_new` / `is_corpse_settle` retained for call-site
# compatibility but no longer drive separate code paths — every stamp
# routes through the LiquidLayer the same way.
static func spawn_blood_decal(parent: Node, world_pos: Vector3, blood_type: StringName = BLOOD_TYPE_HUMAN, _force_new: bool = false, is_corpse_settle: bool = false) -> void:
	if parent == null or _blood_disabled():
		return
	if _is_over_pit(parent, world_pos):
		return
	# Pick a radius based on caller intent: kill scenes get a chunky
	# single stamp; mist drops are small. Settle pools have their own
	# bigger stamp wired in PrototypeEnemy._spawn_settle_pool — those
	# call layer.stamp() directly and bypass this entry.
	var radius: float = randf_range(_MIST_POOL_RADIUS_MIN, _MIST_POOL_RADIUS_MAX)
	if is_corpse_settle:
		radius = _KILL_POOL_RADIUS
	_stamp_to_liquid_layer(parent, world_pos, blood_type, radius, 1.0)


# Standalone slip-zone Area3D for the Traction gameplay hook. Replaces
# the old per-decal SlipZone child — LiquidLayer stamps don't have
# per-pool nodes, so callers (e.g. PrototypeEnemy._spawn_settle_pool)
# spawn one of these alongside each settle pool. Player enter/exit
# drives the same enter_blood_pool / exit_blood_pool methods as before.
static func spawn_blood_slip_zone(parent: Node, world_pos: Vector3, radius: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var area := Area3D.new()
	area.name = &"BloodSlipZone"
	area.collision_layer = 0
	area.collision_mask = BLOOD_POOL_PLAYER_MASK
	area.monitoring = true
	area.monitorable = false
	# Group lookup target for is_in_blood() — the footstep system polls
	# this to decide whether to refresh the bloody-footprint counter.
	area.add_to_group(&"blood_slip_zone")
	# Store the cylinder radius as meta so containment checks (which
	# don't have direct access to the shape) can use it.
	area.set_meta(&"_blood_radius", maxf(radius, 0.1))
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.1)
	shape.height = BLOOD_POOL_AREA_HEIGHT
	col.shape = shape
	area.add_child(col)
	parent.add_child(area)
	area.global_position = Vector3(world_pos.x, world_pos.y + BLOOD_POOL_AREA_HEIGHT * 0.5, world_pos.z)
	area.body_entered.connect(_on_blood_pool_body_entered)
	area.body_exited.connect(_on_blood_pool_body_exited)


# Is `world_pos` inside any active blood slip zone? Used by the footstep
# system to refresh the bloody-print counter when a body steps over a
# pool. XZ-only test (cylinder shape, ignores vertical separation since
# the player's feet may sit slightly above the zone's base).
static func is_in_blood(world_pos: Vector3) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(&"blood_slip_zone"):
		if not (n is Area3D):
			continue
		var a := n as Area3D
		if not is_instance_valid(a):
			continue
		var r: float = float(a.get_meta(&"_blood_radius", 0.0))
		if r <= 0.0:
			continue
		var dx: float = world_pos.x - a.global_position.x
		var dz: float = world_pos.z - a.global_position.z
		if dx * dx + dz * dz <= r * r:
			return true
	return false


static func _on_blood_pool_body_entered(body: Node) -> void:
	# Group + method check — guards against the layer mask ever picking
	# up something that isn't a PrototypePlayer (charmed pets etc.).
	if body.is_in_group(&"player") and body.has_method(&"enter_blood_pool"):
		body.enter_blood_pool()


static func _on_blood_pool_body_exited(body: Node) -> void:
	if body.is_in_group(&"player") and body.has_method(&"exit_blood_pool"):
		body.exit_blood_pool()


# Resolve the LiquidLayer for `blood_type` and stamp a randomly-rotated
# lobed splatter at `world_pos`. Returns silently if no LiquidLayer is
# in the scene (covers test scenes that never instanced one);
# LiquidLayer.find_for surfaces a one-time warning if it falls back.
static func _stamp_to_liquid_layer(parent: Node, world_pos: Vector3, blood_type: StringName, world_radius: float, intensity: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var layer := LiquidLayer.find_for(parent.get_tree(), blood_type)
	if layer == null:
		return
	# Reuse the lobed/noise-perturbed splatter textures generated for
	# corpse settle pools — they're already chaotic stamps that read
	# as messy splatter rather than discs.
	var tex := PrototypeEnemy._get_settle_stamp_texture()
	layer.stamp(world_pos, tex, world_radius, intensity)


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
	# Routed through WallLiquidLayer (overlay quads + dual SubViewport
	# masks). The shader handles wall sampling + lighting; stamps live
	# in the persistent CLEAR_MODE_NEVER mask so multiple hits in the
	# same area accumulate without per-decal overhead.
	var layer := _find_wall_liquid_layer(parent)
	if layer == null:
		return
	# Vertical scatter so splatters spread across the wall's height
	# instead of clustering at the raycast hit point (typically the
	# enemy's chest, ~1m up). Upward bias to balance the drip-streak
	# downward spread that follows.
	var jittered_pos := world_pos + Vector3(0, randf_range(-0.25, 0.85), 0)
	var radius: float = randf_range(0.20, 0.40)
	layer.stamp(jittered_pos, wall_normal, radius, 1.0)


static func _find_wall_liquid_layer(parent: Node) -> WallLiquidLayer:
	if parent == null or not parent.is_inside_tree():
		return null
	var tree := parent.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"wall_liquid_layer") as WallLiquidLayer


# ── Wall projectile impacts (bullet holes + plasma scorches) ─────────
#
# Decals spawned when a projectile hits world geometry (walls / floors /
# ceilings). Two flavours:
#   - BULLET (is_bullet=true): small dark hole, no glow, longer-lived.
#   - PLASMA (is_bullet=false): bigger glowing patch tinted to the shot
#     color; the emission cools over ~2.5s while the albedo lingers for
#     the full lifetime, so it reads as "still molten → charred ring".
#
# Capped global ring (oldest evicted on overflow) like the blood ring,
# but smaller — wall impacts fire a lot less than blood, and the glow
# decals are HDR-enabled so each one is more expensive than a flat
# blood splat. Lives on layer 1 alongside blood so the same wall surface
# accepts both.

const WALL_IMPACT_DECAL_MAX: int = 80
# Total visible lifetime before the albedo fades + decal frees. Long
# enough to read as "I shot up this room", short enough that a 5-minute
# fight doesn't paper every wall with overlapping scorches.
const WALL_IMPACT_LIFETIME_SEC: float = 14.0
# Plasma glow cool window — emission drops to 0 over this time at the
# start of life. Albedo (the charred mark) keeps the full lifetime.
const WALL_IMPACT_PLASMA_COOL_SEC: float = 2.5
const WALL_IMPACT_BULLET_SIZE: float = 0.16
const WALL_IMPACT_PLASMA_SIZE: float = 0.32
# HDR emission energy on plasma scorches. > 1.0 puts the decal above the
# bloom threshold so it actually glows visibly during the cool window.
const WALL_IMPACT_PLASMA_EMISSION_ENERGY: float = 6.0
# Surface offset along the normal — same as blood wall splatters; keeps
# the decal from z-fighting the wall while staying close enough that the
# projection lands flush.
const WALL_IMPACT_NORMAL_OFFSET: float = 0.03

static var _wall_impact_ring: Array[Decal] = []
static var _wall_impact_bullet_texture: ImageTexture = null
static var _wall_impact_plasma_albedo_texture: ImageTexture = null
static var _wall_impact_plasma_emission_texture: ImageTexture = null


# Bullet hole — small dark disc with soft falloff. 64×64 RGBA, alpha-
# weighted radial gradient. Charcoal centre (puncture) with a slight
# brown edge ring (chipped material around the entry hole).
static func _get_wall_impact_bullet_texture() -> ImageTexture:
	if _wall_impact_bullet_texture != null:
		return _wall_impact_bullet_texture
	const SIZE: int = 64
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE * 0.5, SIZE * 0.5)
	for y in SIZE:
		for x in SIZE:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(centre) / (SIZE * 0.5)
			if d >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Dark puncture in the inner 40%; brown chip ring 40-85%;
			# fade to transparent past 85%. Smooth interpolation keeps
			# the edge from looking pixel-blocky at iso distance.
			var hole_t: float = clampf(d / 0.4, 0.0, 1.0)
			var ring_t: float = clampf((d - 0.4) / 0.45, 0.0, 1.0)
			var edge_t: float = clampf((d - 0.85) / 0.15, 0.0, 1.0)
			var c := Color(0.04, 0.03, 0.03, 0.92).lerp(Color(0.18, 0.11, 0.07, 0.75), hole_t)
			c = c.lerp(Color(0.22, 0.16, 0.12, 0.55), ring_t)
			c.a *= (1.0 - edge_t)
			img.set_pixel(x, y, c)
	_wall_impact_bullet_texture = ImageTexture.create_from_image(img)
	return _wall_impact_bullet_texture


# Plasma scorch albedo — wider, irregular charred ring. The molten glow
# is handled by the emission map; this one is the cool aftermath.
static func _get_wall_impact_plasma_albedo_texture() -> ImageTexture:
	if _wall_impact_plasma_albedo_texture != null:
		return _wall_impact_plasma_albedo_texture
	const SIZE: int = 64
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE * 0.5, SIZE * 0.5)
	for y in SIZE:
		for x in SIZE:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(centre) / (SIZE * 0.5)
			if d >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Inner 35% near-black (vaporised); 35-70% charred dark; fade
			# out beyond. The slight asymmetry from `noise` breaks the
			# perfect-circle look without needing a real noise texture.
			# (No GDScript `fract` builtin — use x - floor(x) instead;
			# `fract` is a shader-side function only.)
			var hash_f: float = sin(float(x) * 12.989 + float(y) * 78.233) * 43758.5453
			var noise: float = (hash_f - floor(hash_f)) * 0.12 - 0.06
			var dd: float = clampf(d + noise, 0.0, 1.0)
			var inner_t: float = clampf(dd / 0.35, 0.0, 1.0)
			var char_t: float = clampf((dd - 0.35) / 0.35, 0.0, 1.0)
			var edge_t: float = clampf((dd - 0.70) / 0.30, 0.0, 1.0)
			var c := Color(0.02, 0.02, 0.02, 0.88).lerp(Color(0.08, 0.05, 0.04, 0.80), inner_t)
			c = c.lerp(Color(0.15, 0.10, 0.08, 0.55), char_t)
			c.a *= (1.0 - edge_t)
			img.set_pixel(x, y, c)
	_wall_impact_plasma_albedo_texture = ImageTexture.create_from_image(img)
	return _wall_impact_plasma_albedo_texture


# Plasma scorch emission — bright central hotspot fading to nothing.
# Tinted at runtime via decal.modulate so the projectile's color carries
# through. Pure white grayscale here so the modulate multiplies cleanly.
static func _get_wall_impact_plasma_emission_texture() -> ImageTexture:
	if _wall_impact_plasma_emission_texture != null:
		return _wall_impact_plasma_emission_texture
	const SIZE: int = 64
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var centre := Vector2(SIZE * 0.5, SIZE * 0.5)
	for y in SIZE:
		for x in SIZE:
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(centre) / (SIZE * 0.5)
			if d >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			# Tight bright core, soft halo. Exponential falloff so the
			# centre is intensely white and the halo trails off gradually
			# — emission_energy multiplies past 1.0 so the centre pushes
			# above bloom threshold.
			var t: float = pow(1.0 - d, 2.2)
			img.set_pixel(x, y, Color(t, t, t, t))
	_wall_impact_plasma_emission_texture = ImageTexture.create_from_image(img)
	return _wall_impact_plasma_emission_texture


## Spawn a projectile-impact decal on world geometry.
##   is_bullet  — true for physical rounds (smg/sniper/shotgun/lmg) which
##                leave a dark hole; false for energy/plasma which leave
##                a glowing molten patch.
##   glow_color — tint applied to the plasma emission. Ignored when
##                is_bullet is true. Defaults to white.
static func spawn_wall_projectile_impact(parent: Node, world_pos: Vector3, wall_normal: Vector3, is_bullet: bool, glow_color: Color = Color.WHITE) -> void:
	if parent == null:
		return
	if wall_normal.length_squared() < 0.0001:
		return
	var decal := Decal.new()
	if is_bullet:
		decal.texture_albedo = _get_wall_impact_bullet_texture()
		var s := WALL_IMPACT_BULLET_SIZE * randf_range(0.85, 1.15)
		decal.size = Vector3(s, 0.3, s)
		decal.albedo_mix = 1.0
	else:
		decal.texture_albedo = _get_wall_impact_plasma_albedo_texture()
		decal.texture_emission = _get_wall_impact_plasma_emission_texture()
		# Resolved glow color. Callers pass `Color(0,0,0,0)` (sentinel from
		# _weapon_tint when the weapon has no damage_type — laser pistol
		# is the immediate case) to mean "no override, use a default."
		# Without this fallback the modulate landed at black, which then
		# multiplied the grayscale emission texture down to 0 — visible
		# charred ring but no glow at all. Default to a warm-white plasma
		# tint that reads on every wall material.
		var resolved_glow: Color = glow_color if glow_color.a > 0.0 else Color(1.0, 0.85, 0.55)
		# Also catch pure black (alpha 1 but RGB zero) — same modulate
		# wipe-out as the sentinel case. Real weapon tints always have
		# at least one channel > 0.1.
		if maxf(resolved_glow.r, maxf(resolved_glow.g, resolved_glow.b)) < 0.05:
			resolved_glow = Color(1.0, 0.85, 0.55)
		decal.modulate = Color(resolved_glow.r, resolved_glow.g, resolved_glow.b, 1.0)
		decal.emission_energy = WALL_IMPACT_PLASMA_EMISSION_ENERGY
		var s2 := WALL_IMPACT_PLASMA_SIZE * randf_range(0.9, 1.2)
		decal.size = Vector3(s2, 0.3, s2)
		decal.albedo_mix = 0.95
	decal.upper_fade = 0.1
	decal.lower_fade = 0.1
	decal.cull_mask = BLOOD_DECAL_CULL_LAYER
	parent.add_child(decal)
	decal.global_position = world_pos + wall_normal.normalized() * WALL_IMPACT_NORMAL_OFFSET
	# Decal projects along its local -Y. Rotate the default Y-up basis
	# so +Y points along the wall normal — same trick the blood wall
	# splatter uses. Random spin around the normal breaks the obvious
	# "every impact axis-aligned" look.
	var rot := Quaternion(Vector3.UP, wall_normal.normalized())
	var spin := Basis(wall_normal.normalized(), randf() * TAU)
	decal.global_basis = spin * Basis(rot)
	_track_wall_impact_decal(decal, not is_bullet)


# Ring eviction + auto-fade timer. Glowing decals get a fast emission
# cool tween up front; both types get the late-life albedo fade and
# queue_free.
static func _track_wall_impact_decal(decal: Decal, is_glowing: bool) -> void:
	_wall_impact_ring.append(decal)
	if _wall_impact_ring.size() > WALL_IMPACT_DECAL_MAX:
		var oldest_var = _wall_impact_ring.pop_front()
		if oldest_var != null and is_instance_valid(oldest_var):
			(oldest_var as Decal).queue_free()
	# Tweens — both safe to start the same frame the decal was added.
	if is_glowing:
		var cool := decal.create_tween()
		cool.tween_property(decal, "emission_energy", 0.0, WALL_IMPACT_PLASMA_COOL_SEC)
	# Hold the decal at full opacity for most of the lifetime, then fade
	# over the last 30%. Keeps the visual stable enough to read as a
	# proper mark instead of constantly half-faded.
	var hold: float = WALL_IMPACT_LIFETIME_SEC * 0.7
	var fade: float = WALL_IMPACT_LIFETIME_SEC * 0.3
	var fade_tw := decal.create_tween()
	fade_tw.tween_interval(hold)
	fade_tw.tween_property(decal, "albedo_mix", 0.0, fade)
	fade_tw.tween_callback(func() -> void:
		# Drop from the ring before queue_free so subsequent eviction
		# scans don't trip over a freed entry.
		_wall_impact_ring.erase(decal)
		if is_instance_valid(decal):
			decal.queue_free()
	)


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
	# Chaotic alpha mask + dark modulate — same look as floor / wall /
	# prop blood, so a character's splatters read as the same fluid
	# rather than a brighter cartoon splat.
	decal.texture_albedo = PrototypeEnemy._get_settle_stamp_texture()
	decal.texture_orm = _get_blood_orm_texture()
	# Small footprint (humanoid surface area); tall projection volume
	# so the splat covers the character even at extreme pose angles
	# (a kicked-up leg, a turning torso).
	decal.size = Vector3(randf_range(0.30, 0.55), 1.6, randf_range(0.30, 0.55))
	decal.modulate = _dark_blood_decal_color()
	decal.upper_fade = 0.1
	decal.lower_fade = 0.1
	# Full-replace — see _spawn_object_blood_decal for rationale.
	decal.albedo_mix = 1.0
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
	# Chaotic lobed alpha mask from the LiquidLayer's stamp generator —
	# same silhouette family as floor/wall blood. modulate tints the
	# white mask to dark blood color, so a single texture pool serves
	# both prop side-paint and floor stamps consistently.
	decal.texture_albedo = PrototypeEnemy._get_settle_stamp_texture()
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
	decal.modulate = _dark_blood_decal_color()
	decal.upper_fade = 0.08
	decal.lower_fade = 0.08
	# Full-replace albedo_mix — the chaotic mask is alpha-only, so the
	# decal needs to fully replace the prop's surface color where it
	# stamps. Without this the dark color would barely register on a
	# bright prop.
	decal.albedo_mix = 1.0
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
# texture/material peek through. 0.92 used to leave ~8% of the floor
# bleeding through, which on the cool-grey facility tiles desaturated
# the red into a washed-out pink that didn't read as blood. Full
# opaque (1.0) keeps the red saturated and unambiguous — the decal
# texture's own per-pixel alpha + edge fades still feather the splat
# shape, so it doesn't read as a flat sticker.
const BLOOD_DECAL_ALBEDO_MIX: float = 1.0


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

# Mask + margin for the wall-clamp raycasts. World layer (1) holds room
# walls, corridor walls, and ceiling. The horizontal cast at y=0.6 only
# intercepts vertical surfaces (walls + door jambs), so the floor and
# ceiling on the same layer don't interfere. Pillars sit on layer 128
# and are deliberately excluded — splatter painting on the SIDE of a
# pillar reads as "blood hit the pillar", which is fine.
const _DECAL_WALL_MASK: int = 1

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
# Was 10 — the trail's last visible print was still ~0.03 alpha,
# bright enough that the cut to nothing read as abrupt. 14 prints
# combined with the steeper alpha curve below means the final two or
# three prints are well below the visible threshold, so the trail
# tapers organically into the floor rather than ending hard.
const BLOODY_STEPS_INITIAL: int = 14
# Footprint self-fade: linger fully visible for _FOOTPRINT_HOLD seconds,
# then tween modulate.alpha to 0 over _FOOTPRINT_FADE seconds and free.
# Independent of the global _blood_decal_ring eviction so prints clean
# themselves up even when the cap hasn't been hit.
const _FOOTPRINT_HOLD: float = 6.0
const _FOOTPRINT_FADE: float = 2.5


# Spawn a directional footprint into the matching LiquidLayer for
# `fluid_id`. The boot-print silhouette is a WHITE-on-alpha texture —
# the per-fluid color comes from the LiquidLayer's shader (so a single
# silhouette covers blood, oil, water, etc. with no per-fluid asset
# duplication). intensity (0..1) attenuates the stamp's alpha so a
# trail visibly fades as the foot wipes its load off.
#
# fluid_id defaults to BLOOD_TYPE_HUMAN; expand to other liquids by
# adding a LiquidLayer instance with the matching fluid_id and the
# group lookup below picks it up automatically.
static func spawn_fluid_footprint(parent: Node, world_pos: Vector3,
		forward_dir: Vector3, intensity: float, right_foot: bool = true,
		fluid_id: StringName = BLOOD_TYPE_HUMAN) -> void:
	if parent == null or _blood_disabled():
		return
	var layer := LiquidLayer.find_for(Engine.get_main_loop() as SceneTree, fluid_id)
	if layer == null:
		return
	var tex: Texture2D = _get_white_bootprint_texture(right_foot)
	var rot_y: float = 0.0
	if forward_dir.length_squared() > 0.0001:
		rot_y = atan2(forward_dir.x, forward_dir.z)
	# Boot-print silhouette oriented along walking direction. Was
	# 0.32 × 0.45m — but the shader's edge softness + density gradient
	# bleed the visible stamp outward by a noticeable margin, so the
	# rendered print read closer to ~50cm wide × 70cm long (much
	# bigger than the character's actual foot). 0.18 × 0.28m measured
	# at the silhouette bounding box puts the rendered print closer to
	# realistic boot dimensions once shader bleed is accounted for.
	#
	# Steeper power curve + longer trail (14 prints) so the tail prints
	# drop well below visibility — the cutoff to "no more prints"
	# becomes invisible rather than abrupt. pow(intensity, 2.6) at
	# 14-step granularity:
	#   step 1  (intensity 1.000) → alpha 1.00
	#   step 4  (intensity 0.786) → alpha 0.55
	#   step 7  (intensity 0.571) → alpha 0.25
	#   step 10 (intensity 0.357) → alpha 0.07
	#   step 12 (intensity 0.214) → alpha 0.02   (sub-perceptible)
	#   step 14 (intensity 0.071) → alpha 0.001  (vanishes into floor)
	var alpha: float = pow(intensity, 2.6)
	layer.stamp_oriented(world_pos, tex, Vector2(0.18, 0.28), rot_y, alpha)


# Back-compat shim. Existing call sites still reference this name;
# delegate to the fluid-aware path so the LiquidLayer migration is
# transparent to callers. New code should call spawn_fluid_footprint
# directly with the matching fluid_id.
static func spawn_blood_footprint(parent: Node, world_pos: Vector3,
		forward_dir: Vector3, intensity: float, right_foot: bool = true,
		blood_type: StringName = BLOOD_TYPE_HUMAN) -> void:
	spawn_fluid_footprint(parent, world_pos, forward_dir, intensity, right_foot, blood_type)


# Procedurally-baked WHITE boot silhouette in alpha — LiquidLayer's
# shader applies the per-fluid color. Cached per L/R variant; a few
# hundred KB total for both variants combined.
static var _white_bootprint_right_tex: Texture2D = null
static var _white_bootprint_left_tex: Texture2D = null
static func _get_white_bootprint_texture(right_foot: bool) -> Texture2D:
	if right_foot:
		if _white_bootprint_right_tex == null:
			_white_bootprint_right_tex = ImageTexture.create_from_image(
				_make_bootprint_image(false, Color.WHITE))
		return _white_bootprint_right_tex
	if _white_bootprint_left_tex == null:
		_white_bootprint_left_tex = ImageTexture.create_from_image(
			_make_bootprint_image(true, Color.WHITE))
	return _white_bootprint_left_tex


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
	# Packed ORM (Godot decal convention): R=Occlusion, G=Roughness,
	# B=Metallic. Roughness 0.55 = damp / wet look with visible
	# specular reflection on light sources, without the wet-vinyl
	# hotspot of the old 0.45 or the dry-paint matte of the bumped
	# 0.90. Reads as fresh blood still glistening.
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 0.55, 0.0))
	_blood_orm_texture = ImageTexture.create_from_image(img)
	return _blood_orm_texture


# Dark-blood decal tint matching the LiquidLayer's `fresh_color`
# (near-black with a faint red hint). Used by props + characters so
# their splatter visually matches floor/wall pools instead of reading
# as a brighter, more saturated red. ±20% jitter per channel so
# adjacent splats aren't identical.
static func _dark_blood_decal_color(alpha: float = 1.0) -> Color:
	var k: float = randf_range(0.85, 1.20)
	return Color(0.14 * k, 0.030 * k, 0.042 * k, alpha)


# AoE explosion burst — flipbook fireball + flash + sparks, palette-keyed
# by damage_type. All AoE projectiles route here; the elemental palette
# (kinetic / flame / cryo / electric / plasma) colors the flash, sparks,
# and omni light to match the weapon's identity.
const EXPLOSION_DURATION := 0.8
# Spark + flash layers run alongside the flipbook for the "impact
# moment" punch — the flipbook itself handles fireball + smoke phases
# internally over its own ~2s sprite-sheet lifetime, so we don't need
# a separate procedural smoke layer.
# Was 0.45 — combined with the previous high spark velocity, that
# gave each spark a long flight path well past wall boundaries.
# Shorter lifetime helps the cloud die out inside the blast radius
# alongside the velocity/damping changes in _spawn_explosion_sparks.
const EXPLOSION_SPARK_LIFETIME := 0.32
const EXPLOSION_FLASH_DURATION: float = 0.18
# Lifetime of the flipbook GPUParticles3D scene before we queue_free
# its instance. Matches the BigExplosionScene's particle lifetime
# (2.13s) plus a small tail so trailing frames have time to finish.
const EXPLOSION_FLIPBOOK_LIFETIME: float = 2.6
# Kinetic flipbook quad size, in METERS, derived from blast radius. The
# sprite's visible fireball/smoke fills essentially the whole frame, so
# quad size ≈ cloud size — earlier mappings that multiplied a scale
# factor onto the authored 8 m quad barely changed anything (radius 2 m
# gave a 7.2 m quad vs the old fixed 8 m: visually identical). Direct
# meters keep the math honest: cloud ≈ 1.1× blast diameter.
#   rpg 2 m → 4.4 m cloud, frag 3.5 m → 7.7 m,
#   Tactical Strike 4.5 m → 9.9 m, MAX caps runaway radii at 16 m.
const FLIPBOOK_QUAD_PER_RADIUS_M: float = 2.2
const FLIPBOOK_QUAD_MIN_M: float = 3.0
const FLIPBOOK_QUAD_MAX_M: float = 16.0
# Soft-particle fade distance (the shader's Soft_limit uniform). The
# scene-default 0.10 only softens fragments within 10cm of geometry,
# which let smoke billboards rise visibly above wall tops at iso
# angles before any fade kicked in. 0.55 widens the fade zone so the
# upper portion of the column blends out against walls instead of
# clipping over their tops.
const FLIPBOOK_SOFT_LIMIT: float = 0.55
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
	# Impact crater + dust cloud + physical debris on the ground below
	# the explosion. world_pos can be airborne (projectile hits a wall
	# or chest-height enemy), so the ground anchor projects to Y=0 —
	# the prototype's floor plane. Radius matches blast_radius so the
	# visible scar tracks the damage zone. Skipping tiny blasts (<1m)
	# where these would read as noise.
	#
	# All three share the same `host`, so they spawn as siblings of the
	# fireball under the same parent and survive host queue_free after
	# spawn_explosion returns.
	#
	# MP coverage is free — CombatVisuals.spawn_explosion's RPC fires
	# spawn_explosion on every peer, so each peer's full impact set
	# spawns locally without any extra sync code.
	if blast_radius >= 1.0:
		var ground_pos := Vector3(world_pos.x, 0.0, world_pos.z)
		spawn_hammer_crater(host, ground_pos, blast_radius)
		# Use a temp Node3D anchor at ground_pos for the dust ring —
		# spawn_hammer_dust_ring reads host.global_position internally,
		# so the host has to actually be at the impact spot for the
		# ring to land in the right place (we can't pass an explicit
		# centre to it).
		var dust_anchor := Node3D.new()
		(host.get_parent() if host.get_parent() != null else host).add_child(dust_anchor)
		dust_anchor.global_position = ground_pos
		spawn_hammer_dust_ring(dust_anchor, blast_radius)
		# Anchor was only needed for the spawn — free on the next frame
		# after the particles have captured its position. spawn_hammer_dust_ring
		# uses local_coords = false so the particles don't follow the
		# anchor after spawn.
		dust_anchor.queue_free()
		# Delay debris spawn so the flipbook smoke has time to bloom
		# before the chunks fly out of it. Opaque debris meshes always
		# render before the transparent smoke, so without this delay
		# the smoke (depth-tested behind every airborne shard) was
		# discarded under each debris fragment — debris read as a
		# layer pasted on top of the cloud rather than emerging from
		# inside it. ~0.12s lets the smoke fill the impact volume
		# first; once shards spawn, they fly out of an established
		# cloud and the smoke blends correctly over the portions of
		# the shard arcs that are behind it.
		var debris_host_id := host.get_instance_id()
		var debris_pos := ground_pos
		var debris_radius := blast_radius
		var t := host.get_tree().create_timer(0.12)
		t.timeout.connect(
			func() -> void:
				var h := instance_from_id(debris_host_id) as Node3D
				if h != null and is_instance_valid(h) and h.is_inside_tree():
					spawn_explosion_debris(h, debris_pos, debris_radius),
			CONNECT_ONE_SHOT
		)


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
	# NOTE: do NOT size via fx.scale — the scene's GPUParticles3D uses
	# local_coords=false, which ignores node scale entirely. The old
	# fx.scale approach silently rendered EVERY kinetic flipbook at the
	# authored 8×8 m regardless of blast size. The quad itself is resized
	# below once we have the particles node.
	var flip_quad_m: float = clampf(
		blast_radius * FLIPBOOK_QUAD_PER_RADIUS_M, FLIPBOOK_QUAD_MIN_M, FLIPBOOK_QUAD_MAX_M)

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
		# Fully deterministic per (damage_type, is_enemy), so the
		# configured material + its gradient textures are built once and
		# cached — the old per-explosion duplicate() + 2 GradientTexture1D
		# uploads were a render-thread sync per blast (laser-hitch class).
		var fb_key := [damage_type, is_enemy]
		var mat: ShaderMaterial = _fireball_mat_cache.get(fb_key)
		if mat == null:
			mat = particles.material_override.duplicate() as ShaderMaterial
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
			# overpower player VFX.
			if is_enemy:
				mat.set_shader_parameter(&"alpha_multiplier", 0.5)
			# Wider soft-particle fade so the billboard blends out where
			# it meets wall geometry instead of clipping above wall tops.
			mat.set_shader_parameter(&"Soft_limit", FLIPBOOK_SOFT_LIMIT)
			_fireball_mat_cache[fb_key] = mat
		particles.material_override = mat
		# GPU particles ignore parent node scale (local_coords=false), so
		# resize the draw pass QuadMesh directly. Energy explosions use a
		# small fixed quad — the flash/sparks carry the blast visual; the
		# flipbook is just a brief residual puff. Kinetic explosions get
		# the blast-diameter mapping (see FLIPBOOK_SCALE_PER_RADIUS).
		var quad: QuadMesh = particles.draw_pass_1.duplicate() as QuadMesh
		if is_kinetic:
			quad.size = Vector2(flip_quad_m, flip_quad_m)
			# The authored visibility AABB only covers the 8 m quad —
			# track the quad so large blasts don't self-cull.
			var half: float = flip_quad_m * 0.5 + 1.0
			particles.visibility_aabb = AABB(
				Vector3(-half, -half, -half), Vector3(half * 2.0, half * 2.0, half * 2.0))
		else:
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
	# Shared unit sphere scaled by blast_radius + per-(tint,intensity)
	# SHARED material template; fade via instance transparency. The old
	# per-explosion SphereMesh + StandardMaterial3D were two RID
	# creations per blast (render-thread sync — laser-hitch class).
	if _explosion_flash_mesh == null:
		_explosion_flash_mesh = SphereMesh.new()
		_explosion_flash_mesh.radius = 0.35
		_explosion_flash_mesh.height = 0.7
		_explosion_flash_mesh.radial_segments = 16
		_explosion_flash_mesh.rings = 8
	var key := [core_tint, intensity_mult]
	var mat: StandardMaterial3D = _explosion_flash_mat_cache.get(key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color(core_tint.r, core_tint.g, core_tint.b, 0.9 * intensity_mult)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = core_tint
		mat.emission_energy_multiplier = 6.0 * intensity_mult
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_explosion_flash_mat_cache[key] = mat
	var inst := MeshInstance3D.new()
	inst.mesh = _explosion_flash_mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Start small so it pops into existence, scale up + fade fast.
	inst.scale = Vector3.ONE * blast_radius * 0.3
	parent.add_child(inst)
	inst.global_position = world_pos
	var tween := inst.create_tween().set_parallel(true)
	tween.tween_property(inst, "scale", Vector3.ONE * blast_radius * 1.4, EXPLOSION_FLASH_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(inst, "transparency", 1.0, EXPLOSION_FLASH_DURATION).set_ease(Tween.EASE_IN)
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

	# Cached per (tint, intensity): pm TEMPLATE (radius-dependent fields
	# set per spawn on a ring entry) + fully-shared draw mesh/material.
	# The old per-explosion ParticleProcessMaterial + Curve +
	# CurveTexture + SphereMesh + StandardMaterial3D were ~3 RID
	# creations per blast (render-thread sync — laser-hitch class).
	var spark_key := [tint, intensity_mult]
	var spark_bundle: Dictionary = _explosion_spark_cache.get(spark_key, {})
	if spark_bundle.is_empty():
		var pm_t := ParticleProcessMaterial.new()
		pm_t.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm_t.direction = Vector3(0.0, 0.3, 0.0)
		pm_t.spread = 180.0  # full radial spray
		# Velocity ~50% lower + damping ~70% higher than the original
		# tune so the spark cloud decays inside the blast radius instead
		# of flying through walls into adjacent rooms.
		pm_t.gravity = Vector3(0.0, -18.0, 0.0)
		pm_t.damping_min = 11.0
		pm_t.damping_max = 16.0
		pm_t.scale_min = 0.04
		pm_t.scale_max = 0.10
		pm_t.color = Color(tint.r, tint.g, tint.b, 1.0)
		# Scale curve fades the spark to nothing — saves an alpha tween.
		if _impact_spark_curve_tex == null:
			var curve := Curve.new()
			curve.add_point(Vector2(0.0, 1.0))
			curve.add_point(Vector2(0.6, 0.4))
			curve.add_point(Vector2(1.0, 0.0))
			_impact_spark_curve_tex = CurveTexture.new()
			_impact_spark_curve_tex.curve = curve
		pm_t.scale_curve = _impact_spark_curve_tex
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
		spark_bundle = {"pm": pm_t, "mesh": mesh}
		_explosion_spark_cache[spark_key] = spark_bundle
	# Radius-dependent fields go on a ring entry (emit-frame-only, same
	# rationale as the blood burst).
	var pm := _ring_material(spark_bundle["pm"], 4) as ParticleProcessMaterial
	pm.emission_sphere_radius = blast_radius * 0.15
	pm.initial_velocity_min = blast_radius * 2.5
	pm.initial_velocity_max = blast_radius * 4.5
	particles.process_material = pm
	particles.draw_pass_1 = spark_bundle["mesh"]

	# Add to tree BEFORE setting global_position — the setter walks the
	# scene tree to convert into local coords, so doing it pre-parent
	# trips "!is_inside_tree()" and silently leaves the node at origin.
	parent.add_child(particles)
	particles.global_position = world_pos
	# Cleanup after the burst — lifetime is short, but pad so the tail
	# fully fades.
	particles.get_tree().create_timer(EXPLOSION_SPARK_LIFETIME + 0.2).timeout.connect(_free_later(particles))


static func spawn_hit_cone(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float) -> void:
	var forward := Vector3(aim.x, 0.0, aim.z)
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = -host.global_transform.basis.z
	var pos := host.global_position + Vector3(0.0, SHOCKWAVE_BUBBLE_LIFT, 0.0)
	_spawn_shockwave(host, pos, _cone_dome_mesh(attack_range, cone_deg), forward, SHOCKWAVE_DURATION_CONE)


# ── Hammer dust / debris VFX ────────────────────────────────────────────────
# Realistic-feeling ground debris kicked up by the 2H hammer swing. Two
# variants:
#   spawn_hammer_dust_cone — LMB: fan of debris in the swing's cone
#   spawn_hammer_dust_ring — RMB: expanding donut of dust outward from
#     the player's feet
# Both reuse the soft-disc footstep texture and a brown dust palette so
# they read as ground material rather than energy / shockwave.

const HAMMER_DUST_COLOR := Color(0.62, 0.52, 0.40, 0.55)
const HAMMER_DUST_LIFETIME: float = 0.65
const HAMMER_DUST_CONE_AMOUNT: int = 22
const HAMMER_DUST_RING_AMOUNT: int = 28
const HAMMER_DUST_LIFT: float = 0.06       # spawn height above floor

static var _hammer_dust_material: StandardMaterial3D = null
static var _hammer_dust_color_ramp: Gradient = null


static func _get_hammer_dust_material() -> StandardMaterial3D:
	if _hammer_dust_material == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.albedo_color = HAMMER_DUST_COLOR
		# Reuse the footstep soft-disc texture so individual particles
		# read as feathered puffs instead of hard quads.
		mat.albedo_texture = _get_footstep_texture()
		_hammer_dust_material = mat
	return _hammer_dust_material


static func _get_hammer_dust_color_ramp() -> Gradient:
	if _hammer_dust_color_ramp == null:
		var g := Gradient.new()
		# Brief opacity peak, then long alpha-only decay so the cloud
		# lingers as it dissipates rather than popping out.
		g.set_color(0, Color(1, 1, 1, 0.85))
		g.set_color(1, Color(1, 1, 1, 0))
		g.set_offset(0, 0.0)
		g.set_offset(1, 1.0)
		_hammer_dust_color_ramp = g
	return _hammer_dust_color_ramp


## LMB 2H melee — fan-shaped dust burst ahead of the player along the
## swing direction. Particles kick up at the cone's footprint and arc
## outward + up, settling back over ~0.65s.
static func spawn_hammer_dust_cone(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	# Forward direction flattened to the ground plane.
	var forward := Vector3(aim.x, 0.0, aim.z)
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = -host.global_transform.basis.z
	var p := CPUParticles3D.new()
	p.amount = HAMMER_DUST_CONE_AMOUNT
	p.lifetime = HAMMER_DUST_LIFETIME
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.mesh = _get_footstep_quad_mesh()
	p.material_override = _get_hammer_dust_material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Box-shaped emission strip extending out in front of the player.
	# Width covers the cone's mouth; depth puts particles along the
	# whole swing reach so the fan reads as the impact arc, not a
	# point-source puff.
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var half_width: float = attack_range * tan(deg_to_rad(cone_deg * 0.5)) * 0.5
	var depth_half: float = attack_range * 0.4
	p.emission_box_extents = Vector3(half_width, 0.05, depth_half)
	# Direction biases up + slightly forward; spread fans particles
	# across the cone. Gravity pulls them back to the floor so the
	# silhouette settles cleanly.
	p.direction = (Vector3.UP * 1.2 + forward * 0.6).normalized()
	p.spread = cone_deg * 0.45
	p.flatness = 0.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.4
	p.gravity = Vector3(0, -3.2, 0)
	p.damping_min = 1.2
	p.damping_max = 2.5
	p.scale_amount_min = 0.18
	p.scale_amount_max = 0.40
	p.color_ramp = _get_hammer_dust_color_ramp()
	# Position emitter at the centre of the strip — mid-cone, floor
	# level (plus a small lift to avoid z-fighting with the ground).
	p.top_level = true
	# Set position BEFORE add_child — see footstep comment.
	var centre := host.global_position + forward * attack_range * 0.4 + Vector3(0.0, HAMMER_DUST_LIFT, 0.0)
	p.position = centre
	# Rotate the emission box so its long axis aligns with the swing
	# direction. Otherwise the strip is world-axis-aligned and looks
	# wrong when the player faces diagonally.
	var basis := Basis.looking_at(forward, Vector3.UP)
	p.transform.basis = basis
	parent.add_child(p)
	p.emitting = true
	var t := p.create_tween()
	t.tween_interval(HAMMER_DUST_LIFETIME + 0.2)
	t.tween_callback(_free_later(p))


# ── Hammer-strike crater (PBR model from Blenderkit) ─────────────────────────
# Replaces the earlier procedural PlaneMesh + displacement shader with
# the imported "Crater Dry Hills" asset — real geometry, real PBR
# textures (albedo / normal / roughness). Spawn:
#   1. Instantiate the glb once and cache it.
#   2. Auto-scale: source mesh is ~40m across, scale to per-strike
#      radius (passed in world meters).
#   3. Tween albedo alpha 1 → 0 over the lifetime to fade out cleanly;
#      free the instance at the end.

const HAMMER_CRATER_SCENE: PackedScene = preload("res://assets/models/vfx/crater/crater.glb")
const HAMMER_CRATER_SHADER: Shader = preload("res://scripts/prototype/hammer_crater.gdshader")
const HAMMER_CRATER_LIFETIME: float = 8.0
const HAMMER_CRATER_FADE_START: float = 5.0     # delay before alpha starts ramping down
const HAMMER_CRATER_LIFT: float = 0.04          # above floor; avoids z-fight


static func spawn_hammer_crater(host: Node3D, world_pos: Vector3, radius: float) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var inst := HAMMER_CRATER_SCENE.instantiate() as Node3D
	if inst == null:
		return
	# Auto-scale to `radius * 2` metres on the longest footprint axis.
	# Measured from the actual mesh AABB at runtime AND folded through
	# every Node3D transform between the MeshInstance3D and inst so the
	# correct footprint comes out even when the glb has inner scale nodes
	# (which is what was making the crater render at 30m+ instead of the
	# intended 5-7m — `get_aabb()` is mesh-local and ignores wrapper
	# transforms).
	var footprint: float = 0.0
	for vi in _all_visual_instances_of(inst):
		if not (vi is MeshInstance3D):
			continue
		var mi := vi as MeshInstance3D
		var ab := mi.get_aabb()  # AABB in mi's local space
		var xform := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != inst and n is Node3D:
			xform = (n as Node3D).transform * xform
			n = n.get_parent()
		var ab_in_inst := xform * ab
		footprint = max(footprint, max(ab_in_inst.size.x, ab_in_inst.size.z))
	if footprint < 0.001:
		footprint = 1.0
	var s: float = (radius * 2.0) / footprint
	inst.scale = Vector3.ONE * s
	# Top-level so the crater stays fixed in world space rather than
	# following the parent's transform (the player walks away from it).
	inst.top_level = true
	inst.position = world_pos + Vector3(0.0, HAMMER_CRATER_LIFT, 0.0)
	# Random Y rotation so successive craters don't look identical.
	inst.rotation.y = randf() * TAU
	parent.add_child(inst)
	# Replace each sub-mesh's material with a ShaderMaterial that wraps
	# the original PBR maps (albedo / normal / roughness) in a radial
	# alpha vignette. Without the vignette the rectangular mesh edge
	# reads as a hard sticker on the floor — the vignette fades the
	# perimeter into the surrounding surface so the crater "becomes
	# part of" the ground texture rather than sitting on top of it.
	# Also disables shadow casting; decal-style VFX shouldn't bloat
	# the shadow atlas.
	var fade_mat: ShaderMaterial = null
	for vi in _all_visual_instances_of(inst):
		if not (vi is MeshInstance3D):
			continue
		var mi := vi as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		# fade_radius is in MESH-local space (VERTEX.xz space in the
		# shader), so it comes from the mesh's own AABB, not the
		# transformed inst-local footprint. Otherwise an inner glb
		# wrapper-scale would mismatch the shader-side coordinate frame
		# and the vignette would land at the wrong radius.
		var mesh_aabb := mi.mesh.get_aabb()
		var mesh_fade_radius: float = max(mesh_aabb.size.x, mesh_aabb.size.z) * 0.5
		if mesh_fade_radius < 0.01:
			mesh_fade_radius = 1.0
		# Shader uses SCREEN_TEXTURE for albedo (so the floor colour comes
		# through the crater), but it still needs the normal + roughness
		# maps from the glb's StandardMaterial3D. Albedo on the source
		# is intentionally NOT carried over — that's the orange "sticker"
		# look we're trying to replace.
		var src_mat: Material = mi.mesh.surface_get_material(0)
		var normal_tex: Texture2D = null
		var rough_tex: Texture2D = null
		if src_mat is StandardMaterial3D:
			var sm := src_mat as StandardMaterial3D
			normal_tex = sm.normal_texture
			rough_tex = sm.roughness_texture
		# Ring of 4 — craters fade over a long window but spawn rarely
		# (hammer finisher / explosions); ring reuse only matters with
		# 4+ craters alive in their fade window, where an early pop is
		# acceptable. Reset every param per spawn (ring contract).
		if _crater_mat_template == null:
			_crater_mat_template = ShaderMaterial.new()
			_crater_mat_template.shader = HAMMER_CRATER_SHADER
		var sh_mat := _ring_material(_crater_mat_template, 4) as ShaderMaterial
		sh_mat.set_shader_parameter(&"normal_tex", normal_tex)
		sh_mat.set_shader_parameter(&"roughness_tex", rough_tex)
		sh_mat.set_shader_parameter(&"fade", 1.0)
		sh_mat.set_shader_parameter(&"fade_radius", mesh_fade_radius)
		mi.set_surface_override_material(0, sh_mat)
		# All sub-meshes share a single material reference so the lifetime
		# tween fades all of them in lock-step. (The crater glb usually
		# is a single mesh anyway, but be safe.)
		if fade_mat == null:
			fade_mat = sh_mat
	# Hold full opacity for the first stretch of the lifetime, then ramp
	# the `fade` shader parameter 1 → 0 over the remaining window. Tween
	# callback at the end frees the instance.
	var tween := inst.create_tween()
	tween.tween_interval(HAMMER_CRATER_FADE_START)
	if fade_mat != null:
		tween.tween_method(func(v: float) -> void:
			fade_mat.set_shader_parameter(&"fade", v),
			1.0, 0.0, HAMMER_CRATER_LIFETIME - HAMMER_CRATER_FADE_START) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_interval(HAMMER_CRATER_LIFETIME - HAMMER_CRATER_FADE_START)
	tween.tween_callback(_free_later(inst))


# Recursive walk for any VisualInstance3D under `root`. Local helper so
# the crater spawn doesn't depend on WeaponAttachment's identical
# private routine.
static func _all_visual_instances_of(root: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if root is VisualInstance3D:
		out.append(root as VisualInstance3D)
	for child in root.get_children():
		out.append_array(_all_visual_instances_of(child))
	return out


## RMB 2H melee (AoE Burst) — expanding donut of dust radiating outward
## from the player's feet. Uses DIRECTED_POINTS so each particle's
## direction can be pre-baked outward from the centre rather than
## sharing a single direction vector.
static func spawn_hammer_dust_ring(host: Node3D, radius: float) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var p := CPUParticles3D.new()
	p.amount = HAMMER_DUST_RING_AMOUNT
	p.lifetime = HAMMER_DUST_LIFETIME
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.mesh = _get_footstep_quad_mesh()
	p.material_override = _get_hammer_dust_material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Pre-bake N emission points around a ring with their per-point
	# velocity pointing outward + up. Inner radius is small (debris
	# kicks up near the impact); particles travel toward the outer
	# edge over their lifetime.
	var inner_radius: float = radius * 0.25
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in HAMMER_DUST_RING_AMOUNT:
		var angle: float = TAU * float(i) / float(HAMMER_DUST_RING_AMOUNT)
		# Add a small angle jitter so the ring doesn't look mechanical.
		angle += randf_range(-0.08, 0.08)
		var dir_h := Vector3(cos(angle), 0.0, sin(angle))
		# Emit just inside the inner radius to give the cloud room to
		# expand. The "normal" vector for DIRECTED_POINTS is the per-
		# point velocity direction — bias outward + slightly up.
		points.append(dir_h * inner_radius)
		normals.append((dir_h * 1.5 + Vector3.UP * 0.4).normalized())
		colors.append(Color.WHITE)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
	p.emission_points = points
	p.emission_normals = normals
	p.emission_colors = colors
	p.spread = 12.0
	p.flatness = 0.0
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -2.8, 0)
	p.damping_min = 1.5
	p.damping_max = 2.8
	p.scale_amount_min = 0.20
	p.scale_amount_max = 0.45
	p.color_ramp = _get_hammer_dust_color_ramp()
	p.top_level = true
	p.position = host.global_position + Vector3(0.0, HAMMER_DUST_LIFT, 0.0)
	parent.add_child(p)
	p.emitting = true
	var t := p.create_tween()
	t.tween_interval(HAMMER_DUST_LIFETIME + 0.2)
	t.tween_callback(_free_later(p))


## Scatter physical debris chunks outward from an explosion impact.
## `radius` controls both the spread and the per-chunk size so larger
## blasts make heavier-looking debris. Uses the same DebrisShard helper
## that DestructibleProp uses on break — hand-rolled tumble + gravity,
## no RigidBody3D cost. Each shard is a tinted dark grey box; varied
## sizes + spins read as concrete/floor chunks rather than uniform
## particle confetti. Mixed with the dust cloud below the call site,
## the impact reads as a real ground-shattering event.
const _EXPLOSION_DEBRIS_COUNT: int = 8
const _EXPLOSION_DEBRIS_LIFETIME: float = 1.6
const _EXPLOSION_DEBRIS_GRAVITY: float = 12.0
static func spawn_explosion_debris(host: Node3D, world_pos: Vector3, radius: float) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	# Per-chunk size scales with blast radius — small blasts kick up
	# pebbles, big ones throw chunks. Half-metre clamp on the top end
	# so we don't get absurd debris boulders.
	var chunk_scale: float = clampf(radius * 0.06, 0.05, 0.16)
	# Shared unit box + pre-baked grey variants — the old per-chunk
	# BoxMesh + StandardMaterial3D were 16 RID creations per explosion
	# (render-thread sync — laser-hitch class). Per-chunk size variation
	# moves to the shard's node scale; color variation picks from the
	# baked palette.
	if _debris_unit_mesh == null:
		_debris_unit_mesh = BoxMesh.new()
		_debris_unit_mesh.size = Vector3.ONE
		for vi in 6:
			var dmat := StandardMaterial3D.new()
			# Dark concrete grey with mild variation; slight warmth picks
			# up the scorched-impact palette.
			var v := lerpf(0.20, 0.38, float(vi) / 5.0)
			dmat.albedo_color = Color(v * 1.05, v, v * 0.9, 1.0)
			dmat.roughness = 0.85
			dmat.metallic = 0.05
			_debris_mats.append(dmat)
	for i in _EXPLOSION_DEBRIS_COUNT:
		var sx: float = randf_range(0.6, 1.2) * chunk_scale
		var sy: float = randf_range(0.5, 1.0) * chunk_scale
		var sz: float = randf_range(0.6, 1.2) * chunk_scale
		var shard := DebrisShard.new()
		shard.mesh_resource = _debris_unit_mesh
		shard.material_override = _debris_mats[randi() % _debris_mats.size()]
		shard.scale = Vector3(sx, sy, sz)
		shard.lifetime = _EXPLOSION_DEBRIS_LIFETIME
		shard.gravity = _EXPLOSION_DEBRIS_GRAVITY
		shard.floor_y = world_pos.y  # land where the explosion fired
		# 360° outward kick with strong vertical bias so chunks arc
		# visibly before landing. Out-speed scales with radius so big
		# blasts throw debris further. Spin axes randomised for chaos.
		var angle: float = randf() * TAU
		var out_speed: float = randf_range(1.5, 3.5) * clampf(radius * 0.5, 0.6, 2.0)
		var up_speed: float = randf_range(3.5, 6.5)
		shard.velocity = Vector3(cos(angle) * out_speed, up_speed, sin(angle) * out_speed)
		shard.angular_velocity = Vector3(
			randf_range(-9.0, 9.0),
			randf_range(-6.0, 6.0),
			randf_range(-9.0, 9.0))
		parent.add_child(shard)
		# Spawn tightly clustered at the impact point — they'll spread
		# out via the outward velocity over their lifetime.
		var jitter: float = chunk_scale * 0.6
		shard.global_position = world_pos + Vector3(
			randf_range(-jitter, jitter),
			randf_range(0.0, jitter * 0.5),
			randf_range(-jitter, jitter))


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


## Shockwave ring around the host. `radius` overrides the cached default
## (HAMMER_IMPACT_RADIUS) — pass the skill's eff_range so the ring's
## visible reach matches the actual damage radius. Default keeps the
## prior 4m behaviour for any caller that doesn't have a range handy.
static func spawn_hammer_impact(host: Node3D, radius: float = HAMMER_IMPACT_RADIUS) -> void:
	if host == null:
		return
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var mat: ShaderMaterial = _ring_material(_get_hammer_impact_material_template()) as ShaderMaterial
	mat.set_shader_parameter(&"progress", 0.0)
	var inst := MeshInstance3D.new()
	inst.mesh = _get_hammer_impact_mesh()
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cached PlaneMesh is sized for HAMMER_IMPACT_RADIUS — scale the
	# instance transform to reach `radius` instead of changing the shared
	# mesh resource (would invalidate the cache for other callers).
	var scale_factor: float = max(radius, 0.1) / HAMMER_IMPACT_RADIUS
	inst.scale = Vector3.ONE * scale_factor
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
	var mat: ShaderMaterial = _ring_material(_get_slash_material_template()) as ShaderMaterial
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
	# Constant params live on the cached template; only the tweened
	# intensity is per-instance (reset every spawn — ring contract).
	if _shockwave_mat_template == null:
		_shockwave_mat_template = ShaderMaterial.new()
		_shockwave_mat_template.shader = SHOCKWAVE_BUBBLE_SHADER
		_shockwave_mat_template.set_shader_parameter(&"distortion", SHOCKWAVE_BUBBLE_DISTORTION)
		_shockwave_mat_template.set_shader_parameter(&"chroma", SHOCKWAVE_BUBBLE_CHROMA)
		_shockwave_mat_template.set_shader_parameter(&"rim_strength", SHOCKWAVE_BUBBLE_RIM)
	var mat := _ring_material(_shockwave_mat_template) as ShaderMaterial
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
	else:
		# Ring contract: a reused material carries the previous
		# telegraph's faded-out alpha — restore full before fading.
		mat.albedo_color.a = 1.0
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

# UNIT-height cylinders, stretched per instance via MeshInstance3D.scale.y.
# The old cache was keyed by raw float length — beam length varies
# continuously with cursor/wall distance, so virtually every shot was a
# cache miss: two fresh CylinderMeshes (with their GPU vertex buffers)
# allocated AND retained forever per shot. Two shared unit meshes + a
# scale write costs nothing.
static func _beam_core_mesh() -> CylinderMesh:
	if _beam_core_unit_mesh == null:
		_beam_core_unit_mesh = CylinderMesh.new()
		_beam_core_unit_mesh.top_radius = BEAM_RADIUS
		_beam_core_unit_mesh.bottom_radius = BEAM_RADIUS
		_beam_core_unit_mesh.height = 1.0
		_beam_core_unit_mesh.radial_segments = 6
		_beam_core_unit_mesh.rings = 1
	return _beam_core_unit_mesh

static func _beam_glow_mesh() -> CylinderMesh:
	if _beam_glow_unit_mesh == null:
		_beam_glow_unit_mesh = CylinderMesh.new()
		_beam_glow_unit_mesh.top_radius = BEAM_RADIUS * 3.0
		_beam_glow_unit_mesh.bottom_radius = BEAM_RADIUS * 3.0
		_beam_glow_unit_mesh.height = 1.0
		_beam_glow_unit_mesh.radial_segments = 6
		_beam_glow_unit_mesh.rings = 1
	return _beam_glow_unit_mesh

# SHARED per-color templates — never duplicated. Material RID creation
# per shot forced a ~25ms render-thread sync (the laser-pistol hitch);
# beams fade via GeometryInstance3D.transparency on the instance, so
# the material is never mutated.
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
	return template

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
	return template

# ── Muzzle flash ─────────────────────────────────────────────────────────────
# Quick OmniLight3D pulse at the barrel position on weapon fire. No mesh —
# just a point light pop that illuminates nearby surfaces for 1-2 frames.
# Reuses the existing light pool so no allocations at horde scale.

const MUZZLE_FLASH_DURATION: float = 0.08
# Energy + range bumped 2026-05-25 — the previous 5.0/4.0 read as a
# subtle ambient lift rather than a discrete "the gun just fired" pop.
# 10.0 energy pushes well above bloom threshold so the flash glows
# brightly through the post-process; 6.0m range floods enough nearby
# floor + walls that the surrounding geometry briefly catches the
# light. Combined with the visual_muzzle anchor (flash now lands at
# the gun barrel tip, not the chest), each shot reads as a real-world
# muzzle discharge.
const MUZZLE_FLASH_ENERGY: float = 10.0
const MUZZLE_FLASH_RANGE: float = 6.0
# Per-archetype flash color. Bullet weapons flash warm orange-white (muzzle
# fire); energy weapons flash their damage-type tint.
const MUZZLE_FLASH_BULLET_COLOR := Color(1.0, 0.8, 0.45)
const MUZZLE_FLASH_ENERGY_COLOR := Color(0.6, 0.85, 1.0)


## `attach_to_host` parents the flash to `host` instead of host.get_parent(),
## so when the firing entity moves during the flash's lifetime the light
## tracks along with it. Default is false to preserve the world-parented
## behavior for enemy callers (their hosts can be pool-recycled mid-fade,
## which would clip the visual). Player call sites opt in.
static func spawn_muzzle_flash(host: Node3D, barrel_pos: Vector3, is_bullet: bool = true, tint: Color = Color(0, 0, 0, 0), attach_to_host: bool = false) -> void:
	if host == null:
		return
	var parent: Node = host if attach_to_host else host.get_parent()
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


# ── Energy pulse — visible glowing sphere at the muzzle ──────────────────
# Companion to spawn_muzzle_flash, which is invisible (just an OmniLight
# pop). Energy pulse spawns a brief unshaded emissive sphere so the
# player actually SEES the muzzle event — used by the taser to sell the
# arc emerging from a discharge instead of materialising mid-air. Lives
# ~0.18s, expands while fading. No pool — these are short-lived enough
# that allocation cost is negligible compared to chain-lightning's own
# spawn overhead.
const ENERGY_PULSE_DURATION: float = 0.18
const ENERGY_PULSE_START_RADIUS: float = 0.08
const ENERGY_PULSE_END_SCALE: float = 2.4
const ENERGY_PULSE_DEFAULT_COLOR := Color(0.55, 0.8, 1.0)


## `attach_to_host` parents the pulse + light to `host` so they track the
## firing entity through their lifetime. Used by player energy-weapon
## shots (laser pistol, plasma rifle) so the muzzle pulse stays glued
## to the gun barrel even while the player runs.
static var _energy_pulse_mesh: SphereMesh = null
static var _energy_pulse_mat_cache: Dictionary = {}


static func spawn_energy_pulse(host: Node3D, barrel_pos: Vector3, tint: Color = Color(0, 0, 0, 0), attach_to_host: bool = false) -> void:
	if host == null:
		return
	var parent: Node = host if attach_to_host else host.get_parent()
	if parent == null:
		parent = host
	var mesh_inst := MeshInstance3D.new()
	# Shared sphere — a fresh SphereMesh per shot meant a fresh GPU
	# vertex buffer per shot on the fast-firing laser pistol.
	if _energy_pulse_mesh == null:
		_energy_pulse_mesh = SphereMesh.new()
		_energy_pulse_mesh.radius = ENERGY_PULSE_START_RADIUS
		_energy_pulse_mesh.height = ENERGY_PULSE_START_RADIUS * 2.0
		_energy_pulse_mesh.radial_segments = 16
		_energy_pulse_mesh.rings = 8
	mesh_inst.mesh = _energy_pulse_mesh
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fallback matches spawn_beam: no elemental tint → the host's class
	# color, so the muzzle pulse and the beam always agree. (They used to
	# diverge — magenta class beam with a hardcoded light-blue pulse.)
	var col: Color = tint if tint.a > 0.0 else _color_for_host(host)
	if col.a <= 0.0:
		col = ENERGY_PULSE_DEFAULT_COLOR
	# Per-color SHARED template — never duplicated. Creating a material
	# RID per shot (duplicate()) forces a render-thread sync: ~25ms
	# stall per call on a separate-thread renderer, which WAS the
	# laser-pistol per-shot hitch (instrumented 2026-06-10: 'setup'
	# segment 25ms, all node/tween work 0.1ms). The fade tween below
	# uses GeometryInstance3D.transparency (per-instance, no material
	# objects touched) instead of mutating albedo/emission.
	var template: StandardMaterial3D = _energy_pulse_mat_cache.get(col)
	if template == null:
		template = StandardMaterial3D.new()
		template.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		template.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		template.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		template.albedo_color = Color(col.r, col.g, col.b, 0.9)
		template.emission_enabled = true
		template.emission = col
		template.emission_energy_multiplier = 4.0
		template.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		template.cull_mode = BaseMaterial3D.CULL_DISABLED
		_energy_pulse_mat_cache[col] = template
	mesh_inst.material_override = template
	# Also kick a quick OmniLight3D so the surrounding floor briefly
	# catches the arc light — sells the energy without needing a
	# separate spawn_muzzle_flash call alongside.
	var light := _acquire_light()
	light.light_color = col
	light.light_energy = MUZZLE_FLASH_ENERGY
	light.omni_range = MUZZLE_FLASH_RANGE
	light.omni_attenuation = 2.0
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	parent.add_child(light)
	light.global_position = barrel_pos
	parent.add_child(mesh_inst)
	mesh_inst.global_position = barrel_pos
	mesh_inst.scale = Vector3.ONE
	var tween := mesh_inst.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_inst, "scale", Vector3.ONE * ENERGY_PULSE_END_SCALE, ENERGY_PULSE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mesh_inst, "transparency", 1.0, ENERGY_PULSE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(light, "light_energy", 0.0, ENERGY_PULSE_DURATION * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(_release_light_later(light))
	tween.tween_callback(mesh_inst.queue_free)


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
	# Telegraph cones spawn per enemy attack windup — per-call duplicate()
	# was a render-thread sync each time. Ring entries get their alpha
	# reset by _play_fade at spawn. Ring of 24: at horde scale a dozen
	# concurrent enemy windups is realistic, and a stomped ring entry
	# would make an older telegraph's fade visibly restart.
	return _ring_material(template, 24) as StandardMaterial3D
