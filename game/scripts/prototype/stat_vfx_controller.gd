class_name StatVFXController
extends Node3D

# Each tier band owns a single signature; lower tiers' visuals do not carry
# upward. T1 → emissive, T2 → mist, T3 → directional particles, T4 → aura,
# T5 → halo. Stats at the same tier band still blend (e.g. two stats at T1
# blend their emissive colors).

const STAT_COLORS: Dictionary = {
	&"ort": Color(1.00, 0.85, 0.30, 1.0),  # gold
	&"ing": Color(0.10, 1.00, 0.50, 1.0),  # bioluminescent green
	&"amb": Color(0.55, 0.10, 0.90, 1.0),  # deep purple
	&"dev": Color(1.00, 0.45, 0.10, 1.0),  # orange sparks
	&"opt": Color(0.15, 0.75, 1.00, 1.0),  # cold blue
	&"cla": Color(1.00, 1.00, 0.30, 1.0),  # yellow-white
}

const EMISSIVE_ENERGY: float = 0.55
const MIST_AMOUNT: int = 22
const DIRECTIONAL_AMOUNT: int = 24
const AURA_ALPHA_PER_STAT: float = 0.18
const AURA_ALPHA_MAX: float = 0.55

var _base_mat: StandardMaterial3D = null
var _visual: Node3D = null

var _directional: Dictionary = {}   # stat_id -> GPUParticles3D
var _mists: Dictionary = {}         # stat_id -> GPUParticles3D
var _halos: Dictionary = {}         # stat_id -> MeshInstance3D
var _halo_rot: Dictionary = {}      # stat_id -> rotation speed (rad/s)
var _aura: MeshInstance3D = null
var _aura_mat: StandardMaterial3D = null
var _current_tiers: Dictionary = {}

func setup(visual: Node3D, base_mat: StandardMaterial3D) -> void:
	_base_mat = base_mat
	_visual = visual
	_base_mat.emission_enabled = true
	_base_mat.emission = Color.BLACK
	_base_mat.emission_energy_multiplier = 0.0

	for stat_id in AttributeState.ROLLABLE_STATS:
		_current_tiers[stat_id] = 0
		_build_directional_particles(stat_id, visual)
		_build_mist_particles(stat_id, visual)

	_apply_all_current_tiers()
	PlayerState.tier_changed.connect(_on_tier_changed)

func _process(delta: float) -> void:
	for stat_id in _halos:
		var halo: MeshInstance3D = _halos[stat_id]
		if halo == null or not halo.visible:
			continue
		var speed: float = _halo_rot.get(stat_id, 0.0)
		if speed != 0.0:
			halo.rotate_y(speed * delta)

func _on_tier_changed(stat_id: StringName, _old: int, new_tier: int) -> void:
	_current_tiers[stat_id] = new_tier
	_refresh_per_stat_layers(stat_id, new_tier)
	_refresh_blended_layers()

func _apply_all_current_tiers() -> void:
	if PlayerState.class_id.is_empty() or PlayerState.spec_id.is_empty():
		return
	for stat_id in AttributeState.ROLLABLE_STATS:
		var tier := AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
		_current_tiers[stat_id] = tier
		_refresh_per_stat_layers(stat_id, tier)
	_refresh_blended_layers()

func _refresh_per_stat_layers(stat_id: StringName, tier: int) -> void:
	_refresh_mist(stat_id, tier)
	_refresh_directional(stat_id, tier)
	_refresh_halo(stat_id, tier)

func _refresh_blended_layers() -> void:
	_blend_emissive()
	_blend_aura()

# ── T1: base emissive ─────────────────────────────────────────────────────────

func _blend_emissive() -> void:
	if _base_mat == null:
		return
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var count := 0
	for stat_id in _current_tiers:
		if int(_current_tiers[stat_id]) != 1:
			continue
		var col: Color = STAT_COLORS.get(stat_id, Color.WHITE)
		r += col.r
		g += col.g
		b += col.b
		count += 1
	if count == 0:
		_base_mat.emission_energy_multiplier = 0.0
		return
	var peak := maxf(r, maxf(g, b))
	if peak > 0.0:
		_base_mat.emission = Color(r / peak, g / peak, b / peak, 1.0)
	_base_mat.emission_energy_multiplier = EMISSIVE_ENERGY

# ── T2: ground mist particles ─────────────────────────────────────────────────

func _build_mist_particles(stat_id: StringName, visual: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.emitting = false
	p.amount = MIST_AMOUNT
	p.lifetime = 1.8
	p.fixed_fps = 30
	p.local_coords = false
	p.randomness = 0.6

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.6, 0.05, 0.6)
	proc.direction = Vector3.UP
	proc.spread = 30.0
	proc.gravity = Vector3.ZERO
	proc.initial_velocity_min = 0.10
	proc.initial_velocity_max = 0.25
	proc.scale_min = 1.4
	proc.scale_max = 2.6
	proc.damping_min = 0.5
	proc.damping_max = 0.9
	p.process_material = proc

	var col: Color = STAT_COLORS.get(stat_id, Color.WHITE)
	var puff := SphereMesh.new()
	puff.radius = 0.05
	puff.height = 0.10
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.emission_enabled = true
	draw_mat.emission = col
	draw_mat.emission_energy_multiplier = 2.0
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.albedo_color = Color(col.r, col.g, col.b, 0.35)
	puff.surface_set_material(0, draw_mat)
	p.draw_pass_1 = puff

	p.position = Vector3(0.0, 0.05, 0.0)
	visual.add_child(p)
	_mists[stat_id] = p

func _refresh_mist(stat_id: StringName, tier: int) -> void:
	var p: GPUParticles3D = _mists.get(stat_id)
	if p == null:
		return
	p.emitting = tier == 2

# ── T3: directional per-stat particles ────────────────────────────────────────

func _build_directional_particles(stat_id: StringName, visual: Node3D) -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.amount = DIRECTIONAL_AMOUNT
	particles.lifetime = 2.0
	particles.explosiveness = 0.0
	particles.randomness = 0.5
	particles.fixed_fps = 30
	particles.one_shot = false
	particles.local_coords = false

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.55
	proc.gravity = Vector3.ZERO
	proc.damping_min = 0.3
	proc.damping_max = 0.8
	proc.scale_min = 0.7
	proc.scale_max = 1.3
	_configure_proc_for_stat(proc, stat_id)
	particles.process_material = proc

	var mote := SphereMesh.new()
	mote.radius = 0.018
	mote.height = 0.036
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.emission_enabled = true
	draw_mat.emission = STAT_COLORS.get(stat_id, Color.WHITE)
	draw_mat.emission_energy_multiplier = 4.0
	draw_mat.albedo_color = Color(0, 0, 0, 0)
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.surface_set_material(0, draw_mat)
	particles.draw_pass_1 = mote

	visual.add_child(particles)
	_directional[stat_id] = particles

func _configure_proc_for_stat(proc: ParticleProcessMaterial, stat_id: StringName) -> void:
	match stat_id:
		&"ort":  # Golden motes rising slowly upward.
			proc.direction = Vector3.UP
			proc.spread = 50.0
			proc.initial_velocity_min = 0.40
			proc.initial_velocity_max = 0.90
		&"ing":  # Green spores drifting in all directions.
			proc.direction = Vector3.UP
			proc.spread = 90.0
			proc.initial_velocity_min = 0.20
			proc.initial_velocity_max = 0.50
		&"amb":  # Purple shadows falling from the body.
			proc.direction = Vector3(0.0, -1.0, 0.0)
			proc.spread = 40.0
			proc.initial_velocity_min = 0.30
			proc.initial_velocity_max = 0.70
		&"dev":  # Orange sparks bursting outward and falling.
			proc.direction = Vector3.UP
			proc.spread = 120.0
			proc.gravity = Vector3(0.0, -4.0, 0.0)
			proc.initial_velocity_min = 1.8
			proc.initial_velocity_max = 3.6
		&"opt":  # Cold blue data streams shooting upward in tight column.
			proc.direction = Vector3.UP
			proc.spread = 12.0
			proc.initial_velocity_min = 0.8
			proc.initial_velocity_max = 1.4
		&"cla":  # Yellow motes orbiting with angular velocity.
			proc.direction = Vector3.UP
			proc.spread = 65.0
			proc.initial_velocity_min = 0.55
			proc.initial_velocity_max = 1.10
			proc.angular_velocity_min = 80.0
			proc.angular_velocity_max = 200.0

func _refresh_directional(stat_id: StringName, tier: int) -> void:
	var particles: GPUParticles3D = _directional.get(stat_id)
	if particles == null:
		return
	particles.emitting = tier == 3

# ── T4: aura sphere ───────────────────────────────────────────────────────────

func _blend_aura() -> void:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var count := 0
	for stat_id in _current_tiers:
		if int(_current_tiers[stat_id]) != 4:
			continue
		var col: Color = STAT_COLORS.get(stat_id, Color.WHITE)
		r += col.r
		g += col.g
		b += col.b
		count += 1
	if count == 0:
		if _aura != null:
			_aura.visible = false
		return
	if _aura == null:
		_build_aura()
	_aura.visible = true
	var peak := maxf(r, maxf(g, b))
	var color := Color.WHITE
	if peak > 0.0:
		color = Color(r / peak, g / peak, b / peak, 1.0)
	_aura_mat.emission = color
	var alpha := minf(AURA_ALPHA_PER_STAT * count, AURA_ALPHA_MAX)
	_aura_mat.albedo_color = Color(color.r, color.g, color.b, alpha)

func _build_aura() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.7
	_aura_mat = StandardMaterial3D.new()
	_aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_aura_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aura_mat.emission_enabled = true
	_aura_mat.emission_energy_multiplier = 1.5
	sphere.surface_set_material(0, _aura_mat)
	_aura = MeshInstance3D.new()
	_aura.mesh = sphere
	_aura.position = Vector3(0.0, 1.0, 0.0)
	if _visual != null:
		_visual.add_child(_aura)
	else:
		add_child(_aura)

# ── T5: per-stat halo meshes ──────────────────────────────────────────────────

func _refresh_halo(stat_id: StringName, tier: int) -> void:
	var halo: MeshInstance3D = _halos.get(stat_id)
	if tier != 5:
		if halo != null:
			halo.visible = false
		return
	if halo == null:
		halo = _build_halo(stat_id)
		_halos[stat_id] = halo
	halo.visible = true

func _build_halo(stat_id: StringName) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var col: Color = STAT_COLORS.get(stat_id, Color.WHITE)
	var rot_speed := 0.0

	match stat_id:
		&"ort":  # Gold ring above head.
			var torus := TorusMesh.new()
			torus.inner_radius = 0.42
			torus.outer_radius = 0.50
			torus.rings = 32
			torus.ring_segments = 8
			inst.mesh = torus
			inst.position = Vector3(0.0, 2.0, 0.0)
			rot_speed = 0.4
		&"cla":  # Yellow ring orbiting vertically at chest.
			var torus := TorusMesh.new()
			torus.inner_radius = 0.55
			torus.outer_radius = 0.62
			torus.rings = 32
			torus.ring_segments = 8
			inst.mesh = torus
			inst.position = Vector3(0.0, 1.2, 0.0)
			inst.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
			rot_speed = 1.5
		&"opt":  # Cold blue thin pillar above head.
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.04
			cyl.bottom_radius = 0.04
			cyl.height = 1.2
			inst.mesh = cyl
			inst.position = Vector3(0.0, 2.6, 0.0)
		&"ing":  # Green ring at feet, slowly turning.
			var torus := TorusMesh.new()
			torus.inner_radius = 0.65
			torus.outer_radius = 0.72
			torus.rings = 32
			torus.ring_segments = 8
			inst.mesh = torus
			inst.position = Vector3(0.0, 0.05, 0.0)
			rot_speed = -0.3
		&"amb":  # Purple downward cone shadow at feet.
			var cone := CylinderMesh.new()
			cone.top_radius = 0.55
			cone.bottom_radius = 0.05
			cone.height = 0.7
			inst.mesh = cone
			inst.position = Vector3(0.0, 0.4, 0.0)
		&"dev":  # Orange tilted ring at hips, fast spin.
			var torus := TorusMesh.new()
			torus.inner_radius = 0.45
			torus.outer_radius = 0.52
			torus.rings = 32
			torus.ring_segments = 8
			inst.mesh = torus
			inst.position = Vector3(0.0, 1.0, 0.0)
			inst.rotation = Vector3(deg_to_rad(35.0), 0.0, deg_to_rad(20.0))
			rot_speed = 2.0

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 6.0
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	inst.mesh.surface_set_material(0, mat)

	add_child(inst)
	_halo_rot[stat_id] = rot_speed
	return inst
