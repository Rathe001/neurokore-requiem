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

static func spawn(host: Node3D, skill: Skill, aim: Vector3, attack_range: float = 0.0) -> void:
	var eff_range := attack_range if attack_range > 0.0 else skill.skill_range
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			spawn_cone(host, aim, eff_range, skill.cone_deg, skill.wind_up)
		Skill.TargetingMode.AOE_RADIAL:
			spawn_radial(host, eff_range, skill.wind_up)
		Skill.TargetingMode.PROJECTILE:
			spawn_line(host, aim, eff_range, skill.wind_up)
		Skill.TargetingMode.HITSCAN:
			spawn_line(host, aim, eff_range, skill.wind_up)

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
const BEAM_RADIUS := 0.04
const BEAM_FADE := 0.18

static func spawn_beam(host: Node3D, aim: Vector3, length: float, source_offset: Vector3 = Vector3.ZERO) -> void:
	var parent: Node = host.get_parent()
	if parent == null:
		parent = host
	var color := _color_for_host(host)

	# Core beam — bright, slightly transparent cylinder.
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
	core_mat.emission_enabled = true
	core_mat.emission = color
	core_mat.emission_energy_multiplier = 12.0
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = BEAM_RADIUS
	core_mesh.bottom_radius = BEAM_RADIUS
	core_mesh.height = length
	core_mesh.radial_segments = 6
	core_mesh.rings = 1

	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	core.material_override = core_mat

	# Outer glow — wider, softer, more transparent.
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(color.r, color.g, color.b, 0.3)
	glow_mat.emission_enabled = true
	glow_mat.emission = color
	glow_mat.emission_energy_multiplier = 6.0
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius = BEAM_RADIUS * 3.0
	glow_mesh.bottom_radius = BEAM_RADIUS * 3.0
	glow_mesh.height = length
	glow_mesh.radial_segments = 6
	glow_mesh.rings = 1

	var glow := MeshInstance3D.new()
	glow.mesh = glow_mesh
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
	var impact_light := OmniLight3D.new()
	impact_light.light_color = color
	impact_light.light_energy = 4.0
	impact_light.omni_range = 5.0
	impact_light.omni_attenuation = 2.0
	impact_light.shadow_enabled = false
	impact_light.light_volumetric_fog_energy = 0.0
	impact_light.position = Vector3(0.0, 0.0, -length)
	node.add_child(impact_light)

	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(core_mat, "albedo_color:a", 0.0, BEAM_FADE).set_ease(Tween.EASE_IN)
	tween.tween_property(glow_mat, "albedo_color:a", 0.0, BEAM_FADE).set_ease(Tween.EASE_IN)
	tween.tween_property(core_mat, "emission_energy_multiplier", 0.0, BEAM_FADE)
	tween.tween_property(glow_mat, "emission_energy_multiplier", 0.0, BEAM_FADE)
	tween.tween_property(impact_light, "light_energy", 0.0, BEAM_FADE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(node.queue_free)

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
	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	for i in range(CONE_SEGMENTS + 1):
		var t := float(i) / float(CONE_SEGMENTS)
		var angle: float = lerp(-half, half, t)
		verts.append(Vector3(sin(angle) * radius, 0.0, -cos(angle) * radius))
	verts.append(Vector3.ZERO)
	var mesh := _make_line_mesh(verts)
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
