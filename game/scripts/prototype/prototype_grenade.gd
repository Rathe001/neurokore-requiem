class_name PrototypeGrenade
extends Area3D

## Arcing grenade projectile — travels a parabolic arc from spawn to
## target_position, then detonates with AoE damage. Subtype determines
## secondary effects (knockback, stun, cluster split).

const THROW_SPEED := 14.0
const CLUSTER_THROW_SPEED := 22.0
const CRIT_MULT := 1.5
const STUN_DURATION := 1.5
const CLUSTER_COUNT := 3
const CLUSTER_SPREAD := 2.5
const CLUSTER_DAMAGE_SCALE := 0.5
const ARC_HEIGHT_FACTOR := 0.4
const CLUSTER_ARC_HEIGHT := 1.2

var target_position: Vector3
var damage_min: int = 0
var damage_max: int = 0
var damage_mult: float = 1.0
var crit_chance: float = 0.0
var blast_radius: float = 3.0
var knockback: float = 4.0
var grenade_type: Skill.GrenadeType = Skill.GrenadeType.FRAG
var source_position: Vector3
var is_cluster_child: bool = false
var throw_speed: float = THROW_SPEED

var _start_pos: Vector3
var _flight_time: float = 0.0
var _elapsed: float = 0.0
var _arc_height: float = 0.0
var _detonated: bool = false
var _initialized: bool = false
var _trail: GPUParticles3D


func _ready() -> void:
	_build_trail()


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	if not _initialized:
		_initialized = true
		_start_pos = global_position
		var dist := _start_pos.distance_to(target_position)
		_flight_time = maxf(dist / throw_speed, 0.05)
		if is_cluster_child:
			_arc_height = CLUSTER_ARC_HEIGHT
		else:
			_arc_height = dist * ARC_HEIGHT_FACTOR
	_elapsed += delta
	var t := clampf(_elapsed / _flight_time, 0.0, 1.0)
	# Lerp XZ linearly, Y follows parabola.
	var pos := _start_pos.lerp(target_position, t)
	pos.y += _arc_height * 4.0 * t * (1.0 - t)
	global_position = pos
	if t >= 1.0:
		_detonate()


func _detonate() -> void:
	_detonated = true
	if _trail != null:
		_trail.emitting = false
	PrototypeAttackIndicator.spawn_hit_radial(self, blast_radius)
	var eff_knockback := knockback
	match grenade_type:
		Skill.GrenadeType.INCENDIARY:
			eff_knockback *= 0.4
		Skill.GrenadeType.STUN:
			eff_knockback *= 0.3
		Skill.GrenadeType.CLUSTER:
			eff_knockback *= 0.6
	for n in SpatialGrid.query_radius(global_position, blast_radius, &"enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method(&"take_damage"):
			continue
		if n.has_method(&"is_player_friendly") and n.is_player_friendly():
			continue
		var dmg := _roll_damage()
		n.take_damage(dmg, global_position, eff_knockback, 1, false)
		match grenade_type:
			Skill.GrenadeType.STUN:
				if n.has_method(&"apply_stun"):
					n.apply_stun(STUN_DURATION)
			Skill.GrenadeType.INCENDIARY:
				if n.has_method(&"take_damage"):
					var burn := maxi(1, int(round(float(dmg) * 0.5)))
					n.take_damage(burn, global_position, 0.0, 1, false)
	if grenade_type == Skill.GrenadeType.CLUSTER and not is_cluster_child:
		_spawn_cluster_children()
	queue_free()


func _spawn_cluster_children() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var base_angle := randf() * TAU
	for i in CLUSTER_COUNT:
		var angle := base_angle + float(i) * (TAU / float(CLUSTER_COUNT))
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * CLUSTER_SPREAD
		var child := (load("res://scenes/prototype/prototype_grenade.tscn") as PackedScene).instantiate() as PrototypeGrenade
		child.target_position = global_position + offset
		child.damage_min = int(round(float(damage_min) * CLUSTER_DAMAGE_SCALE))
		child.damage_max = int(round(float(damage_max) * CLUSTER_DAMAGE_SCALE))
		child.damage_mult = damage_mult
		child.crit_chance = crit_chance
		child.blast_radius = blast_radius * 0.6
		child.knockback = knockback * 0.5
		child.grenade_type = Skill.GrenadeType.FRAG
		child.source_position = global_position
		child.is_cluster_child = true
		child.throw_speed = CLUSTER_THROW_SPEED
		parent.add_child(child)
		child.global_position = global_position


func _build_trail() -> void:
	_trail = GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.0, 0.0)
	mat.spread = 0.0
	mat.initial_velocity_min = 0.0
	mat.initial_velocity_max = 0.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.08
	mat.scale_max = 0.12
	mat.color = Color(1.0, 0.6, 0.2, 0.8)
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 0.7, 0.3, 1.0), Color(1.0, 0.3, 0.1, 0.0)])
	color_ramp.gradient = grad
	mat.color_ramp = color_ramp
	_trail.process_material = mat
	_trail.amount = 12
	_trail.lifetime = 0.3
	_trail.explosiveness = 0.0
	_trail.fixed_fps = 30
	_trail.draw_pass_1 = SphereMesh.new()
	(_trail.draw_pass_1 as SphereMesh).radius = 0.06
	(_trail.draw_pass_1 as SphereMesh).height = 0.12
	(_trail.draw_pass_1 as SphereMesh).radial_segments = 4
	(_trail.draw_pass_1 as SphereMesh).rings = 2
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(_trail.draw_pass_1 as SphereMesh).material = draw_mat
	_trail.emitting = true
	add_child(_trail)


func _roll_damage() -> int:
	var base := randi_range(damage_min, damage_max) if damage_max > 0 else 10
	var dmg := int(round(float(base) * damage_mult))
	if crit_chance > 0.0 and randf() < crit_chance:
		dmg = int(round(float(dmg) * CRIT_MULT))
	return dmg
