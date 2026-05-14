class_name ISRDrone
extends Node3D

## Automaton ISR (Intelligence, Surveillance, Reconnaissance) drone.
## Spawned on hit by the ISR Drone talent. Lazily follows the marked target
## for DURATION seconds, increasing all incoming damage by VULN_MULT while
## active. A constant scanning laser connects the drone to the target.
##
## One drone per target — subsequent procs refresh the timer instead of
## stacking additional drones. Pooled via EntityPool.

const DURATION: float = 7.0
const VULN_MULT: float = 1.25

# Hover position: drone floats well above the target so the cone points
# down into the ground. Enemies are ~1.8m tall; 3.0m puts the drone
# roughly 1m above their heads.
const HOVER_HEIGHT: float = 3.0
const HOVER_OFFSET: float = 1.0
# Lazy follow speed — lower = more floaty/delayed.
const FOLLOW_SPEED: float = 2.5

# Scan cone visual — translucent cone from drone apex to a wide base at the
# target, plus a SpotLight3D for ground illumination and a thin ground ring.
const SCAN_COLOR := Color(0.2, 1.0, 0.3, 1.0)   # green, matching ref image
const CONE_TOP_RADIUS: float = 0.01              # near-point at the drone
const CONE_BASE_RADIUS: float = 0.65             # matches ground ring diameter
const CONE_ALPHA: float = 0.03                   # very faint shell
const CONE_EMISSION: float = 2.0
const CONE_SEGMENTS: int = 12
const SPOT_ENERGY: float = 1.5
const SPOT_RANGE: float = 5.0
const SPOT_ANGLE: float = 18.0
const RING_INNER: float = 0.62
const RING_OUTER: float = 0.67
const RING_ALPHA: float = 0.05
const RING_EMISSION: float = 2.5

const SCENE: PackedScene = preload("res://scenes/prototype/isr_drone.tscn")

# Single global ISR drone — one out at a time. Subsequent procs while a
# drone is already active either migrate it to a new target (and refresh
# the timer) or just refresh if it's the same target. Stops the player's
# screen from filling with green cones at horde scale.
static var _active_drone: ISRDrone = null

var _target: Node3D = null
var _elapsed: float = 0.0
var _cone_pivot: Node3D = null
var _cone_mesh: MeshInstance3D = null
var _spot_light: SpotLight3D = null
var _ring_mesh: MeshInstance3D = null
var _released: bool = false
# Randomized lateral offset so the drone doesn't sit directly above.
var _offset_dir: Vector3 = Vector3.ZERO

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

static func spawn_on(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	# One drone in flight at a time. While a proc is running, additional
	# spawn calls are ignored — the existing drone keeps its target and
	# its timer, and the next proc only lands once the current one
	# releases. Acts as a natural cooldown gated by the active state
	# rather than a separate timer. Previous behavior re-targeted the
	# drone mid-flight, which made the green cone hop around the screen
	# at horde scale and burned the proc on whatever was hit most
	# recently rather than the original mark.
	if _active_drone != null and is_instance_valid(_active_drone) and not _active_drone._released:
		return
	var drone: ISRDrone = EntityPool.acquire(SCENE)
	if drone == null:
		return
	drone._target = target
	drone._elapsed = 0.0
	drone._released = false
	# Random lateral offset direction so the drone doesn't stack on center.
	var angle := randf() * TAU
	drone._offset_dir = Vector3(cos(angle), 0.0, sin(angle))
	var world := target.get_parent()
	if drone.get_parent() != world:
		if drone.get_parent() != null:
			drone.get_parent().remove_child(drone)
		world.add_child(drone)
	drone.global_position = target.global_position + Vector3(0.0, HOVER_HEIGHT, 0.0) + drone._offset_dir * HOVER_OFFSET
	drone.visible = true
	drone.set_process(true)
	_active_drone = drone
	# Apply the vulnerability mark on the target.
	if target.has_method(&"apply_isr_mark"):
		target.apply_isr_mark()
	drone._ensure_scan_cone()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _released:
		return
	_elapsed += delta
	if _elapsed >= DURATION or _target == null or not is_instance_valid(_target):
		_release()
		return
	if not _target.is_in_group(&"enemies"):
		_release()
		return
	# Lazy follow — lerp toward a hover point above the target.
	var goal := _target.global_position + Vector3(0.0, HOVER_HEIGHT, 0.0) + _offset_dir * HOVER_OFFSET
	global_position = global_position.lerp(goal, clampf(FOLLOW_SPEED * delta, 0.0, 1.0))
	_update_scan_cone()

func _release() -> void:
	if _released:
		return
	_released = true
	if _active_drone == self:
		_active_drone = null
	if _target != null and is_instance_valid(_target):
		if _target.has_method(&"remove_isr_mark"):
			_target.remove_isr_mark()
	_target = null
	_hide_scan_cone()
	set_process(false)
	EntityPool.release(self)

func _pool_release() -> void:
	_target = null
	_elapsed = 0.0
	_released = false
	_hide_scan_cone()

# ---------------------------------------------------------------------------
# Scan cone visual — translucent cone + spotlight + ground ring
# ---------------------------------------------------------------------------

func _ensure_scan_cone() -> void:
	if _cone_pivot == null:
		_cone_pivot = Node3D.new()
		add_child(_cone_pivot)
	if _cone_mesh == null:
		_cone_mesh = _build_cone()
		_cone_pivot.add_child(_cone_mesh)
	if _spot_light == null:
		_spot_light = SpotLight3D.new()
		_spot_light.light_color = SCAN_COLOR
		_spot_light.light_energy = SPOT_ENERGY
		_spot_light.spot_range = SPOT_RANGE
		_spot_light.spot_angle = SPOT_ANGLE
		_spot_light.spot_attenuation = 0.8
		_spot_light.shadow_enabled = false
		_spot_light.light_volumetric_fog_energy = 0.0
		_cone_pivot.add_child(_spot_light)
	if _ring_mesh == null:
		_ring_mesh = _build_ground_ring()
		add_child(_ring_mesh)
	_cone_pivot.visible = true
	_ring_mesh.visible = true
	_update_scan_cone()


func _build_cone() -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = CONE_BASE_RADIUS
	m.bottom_radius = CONE_TOP_RADIUS
	m.height = 1.0
	m.radial_segments = CONE_SEGMENTS
	m.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(SCAN_COLOR.r, SCAN_COLOR.g, SCAN_COLOR.b, CONE_ALPHA)
	mat.emission_enabled = true
	mat.emission = SCAN_COLOR
	mat.emission_energy_multiplier = CONE_EMISSION
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inst := MeshInstance3D.new()
	inst.mesh = m
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


func _build_ground_ring() -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = RING_INNER
	m.outer_radius = RING_OUTER
	m.rings = 32
	m.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(SCAN_COLOR.r, SCAN_COLOR.g, SCAN_COLOR.b, RING_ALPHA)
	mat.emission_enabled = true
	mat.emission = SCAN_COLOR
	mat.emission_energy_multiplier = RING_EMISSION
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	var inst := MeshInstance3D.new()
	inst.mesh = m
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


func _update_scan_cone() -> void:
	if _target == null or not is_instance_valid(_target) or _cone_pivot == null:
		_hide_scan_cone()
		return
	var target_pos := _target.global_position + Vector3(0.0, 0.1, 0.0)
	var aim := target_pos - global_position
	var length := aim.length()
	if length < 0.01:
		_hide_scan_cone()
		return
	_cone_pivot.global_position = global_position
	_cone_pivot.look_at(global_position + aim, Vector3.UP)
	var cm := _cone_mesh.mesh as CylinderMesh
	cm.height = length
	_cone_mesh.position = Vector3(0.0, 0.0, -length * 0.5)
	# Shimmer — pulse alpha + emission and spin the cone around its axis.
	var t := _elapsed
	var pulse := 0.7 + 0.3 * sin(t * 5.0)
	var emission_pulse := CONE_EMISSION * (0.8 + 0.4 * sin(t * 7.0))
	var spin := t * 2.0
	var mat := _cone_mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color.a = CONE_ALPHA * pulse
		mat.emission_energy_multiplier = emission_pulse
	var b := Basis(Vector3.RIGHT, deg_to_rad(-90.0)) * Basis(Vector3.UP, spin)
	_cone_mesh.basis = b
	_cone_pivot.visible = true
	if _ring_mesh != null:
		_ring_mesh.global_position = _target.global_position + Vector3(0.0, 0.05, 0.0)
		_ring_mesh.global_rotation = Vector3(0.0, t * 1.5, 0.0)
		_ring_mesh.visible = true


func _hide_scan_cone() -> void:
	if _cone_pivot != null:
		_cone_pivot.visible = false
	if _ring_mesh != null:
		_ring_mesh.visible = false
