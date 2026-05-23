class_name ShellCasing extends Node3D

## Spent shell ejected from a firing weapon. Scripted arc rather than
## RigidBody3D — casings are visual flair, hundreds may exist across a
## firefight, and we don't want them tying up Jolt for collision tests
## the player never notices. Simple ballistic + bounce + fade pipeline,
## auto-frees at LIFETIME so nothing accumulates over a session.

const LIFETIME: float = 3.5            # total time alive before queue_free
const FADE_START: float = 2.5          # alpha decays from this point to LIFETIME
const HEAT_FLASH_DURATION: float = 0.25 # extra emission while casing is "hot" from firing
const GRAVITY: float = 9.8             # m/s²
const BOUNCE_DAMP: float = 0.25        # vertical velocity retained on bounce
const HORIZONTAL_DAMP: float = 0.4     # x/z velocity retained on bounce
const SETTLE_SPEED: float = 0.3        # below this speed after bounce, lock in place

var _vel: Vector3 = Vector3.ZERO
var _ang_vel: Vector3 = Vector3.ZERO    # radians/sec around local axes
var _age: float = 0.0
var _settled: bool = false
var _ground_y: float = 0.0              # casing settles here (player-relative floor)
var _mesh_inst: MeshInstance3D = null
var _mat: StandardMaterial3D = null


## Configures the casing's appearance + initial motion in one call so the
## caller doesn't have to drill into private fields. `mesh` is shared
## across every casing of that variant — keep it read-only.
func setup(mesh: Mesh, init_velocity: Vector3, init_angular_velocity: Vector3, ground_y: float) -> void:
	_vel = init_velocity
	_ang_vel = init_angular_velocity
	_ground_y = ground_y
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = mesh
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Brass / copper tone with metallic finish — reads as spent ammo
	# without needing a per-variant material asset. Emission peaks at
	# spawn ("hot from firing") then decays to a low settled glow over
	# HEAT_FLASH_DURATION so the casing remains catchable against dark
	# floors after the heat-pop fades.
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.95, 0.68, 0.28, 1.0)
	_mat.metallic = 0.9
	_mat.roughness = 0.28
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.55, 0.18)
	_mat.emission_energy_multiplier = 2.5
	_mesh_inst.material_override = _mat
	add_child(_mesh_inst)
	# Random starting orientation so successive casings don't all spawn
	# in identical poses.
	rotation = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	# Decay the heat-pop emission for the first quarter-second so the
	# casing reads as "fresh / hot" right at the muzzle and dims to its
	# settled metallic look by the time it hits the floor.
	if _mat != null and _age < HEAT_FLASH_DURATION:
		var heat_t: float = 1.0 - _age / HEAT_FLASH_DURATION
		_mat.emission_energy_multiplier = 0.6 + 1.9 * heat_t
	if not _settled:
		_vel.y -= GRAVITY * delta
		position += _vel * delta
		rotate_x(_ang_vel.x * delta)
		rotate_y(_ang_vel.y * delta)
		rotate_z(_ang_vel.z * delta)
		if position.y <= _ground_y and _vel.y < 0.0:
			# Bounce. Cumulative damping settles the casing within a few
			# hops — no infinite jitter at floor contact.
			_vel.y = -_vel.y * BOUNCE_DAMP
			_vel.x *= HORIZONTAL_DAMP
			_vel.z *= HORIZONTAL_DAMP
			_ang_vel *= HORIZONTAL_DAMP
			if _vel.length() < SETTLE_SPEED:
				_vel = Vector3.ZERO
				_ang_vel = Vector3.ZERO
				_settled = true
				position.y = _ground_y
	# Alpha fade over the tail of the lifetime so the casing
	# dissolves rather than pops out of existence.
	if _age >= FADE_START and _mat != null:
		var fade_t: float = 1.0 - (_age - FADE_START) / (LIFETIME - FADE_START)
		if _mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := _mat.albedo_color
		c.a = clampf(fade_t, 0.0, 1.0)
		_mat.albedo_color = c
