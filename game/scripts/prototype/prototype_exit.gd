class_name PrototypeExit
extends HoverableInteractable

# Freight elevator exit. Joins "boss_listeners" so PrototypeEnemy dispatches
# on_boss_died() when any boss falls. Once unlocked the status lights turn
# green, and the player can interact() to trigger a level reset.

const TINT_LOCKED := Color(0.95, 0.15, 0.15, 1.0)
const TINT_UNLOCKED := Color(0.25, 1.0, 0.45, 1.0)
const PULSE_SPEED := 2.4
const PULSE_MIN := 0.6
const PULSE_MAX := 1.0

@onready var _platform: MeshInstance3D = $Platform
var _posts: Array[MeshInstance3D] = []
var _lights: Array[MeshInstance3D] = []

var _locked: bool = true
var _platform_mat: StandardMaterial3D
var _post_mat: StandardMaterial3D
var _light_mat: StandardMaterial3D
var _pulse_t: float = 0.0


func _ready() -> void:
	add_to_group(&"boss_listeners")

	# Platform — dark industrial metal grate.
	_platform_mat = StandardMaterial3D.new()
	_platform_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_platform_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	_platform_mat.metallic = 0.7
	_platform_mat.roughness = 0.45
	_platform_mat.emission_enabled = false
	_platform.material_override = _platform_mat

	# Posts — slightly lighter steel.
	_post_mat = StandardMaterial3D.new()
	_post_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_post_mat.albedo_color = Color(0.18, 0.18, 0.2, 1.0)
	_post_mat.metallic = 0.65
	_post_mat.roughness = 0.4
	_post_mat.emission_enabled = false
	for name_id in [&"PostNW", &"PostNE", &"PostSW", &"PostSE"]:
		var p := get_node(NodePath(name_id)) as MeshInstance3D
		p.material_override = _post_mat
		_posts.append(p)

	# Crossbeams share the post material.
	for name_id in [&"BeamN", &"BeamS", &"BeamE", &"BeamW"]:
		var b := get_node(NodePath(name_id)) as MeshInstance3D
		b.material_override = _post_mat

	# Status lights — emissive indicators that change color.
	_light_mat = StandardMaterial3D.new()
	_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light_mat.emission_enabled = true
	_light_mat.emission_energy_multiplier = 3.0
	for name_id in [&"LightNW", &"LightNE", &"LightSW", &"LightSE"]:
		var l := get_node(NodePath(name_id)) as MeshInstance3D
		l.material_override = _light_mat
		_lights.append(l)

	super._ready()
	_refresh_tint()


func _process(delta: float) -> void:
	if _locked:
		return
	_pulse_t += delta * PULSE_SPEED
	var pulse := lerpf(PULSE_MIN, PULSE_MAX, 0.5 + 0.5 * sin(_pulse_t))
	_light_mat.emission_energy_multiplier = 3.0 * pulse


func _get_outline_source() -> MeshInstance3D:
	return _platform


func _get_tooltip_text() -> String:
	var key := &"EXIT_TOOLTIP_UNLOCKED" if not _locked else &"EXIT_TOOLTIP_LOCKED"
	return tr(key)


func reset_state() -> void:
	lock()


func is_locked() -> bool:
	return _locked


func unlock() -> void:
	if not _locked:
		return
	_locked = false
	_refresh_tint()
	MissionState.notify_exit_unlocked()


func lock() -> void:
	if _locked:
		return
	_locked = true
	_refresh_tint()


func on_boss_died(_boss: Node) -> void:
	if NetState.is_in_lobby() and NetState.is_client():
		return
	unlock()
	if NetState.is_in_lobby():
		_client_unlock.rpc()


func interact(_user: Node) -> void:
	if _locked:
		get_tree().call_group(&"interactable_tooltip", &"show_text", tr(&"EXIT_TOOLTIP_LOCKED"))
		return
	if NetState.is_in_lobby() and NetState.is_client():
		_request_interact.rpc_id(1)
		return
	get_tree().call_group(&"level_reset_handler", &"reset_level")


func _refresh_tint() -> void:
	var c := TINT_LOCKED if _locked else TINT_UNLOCKED
	_light_mat.albedo_color = c
	_light_mat.emission = c


# ── Multiplayer RPCs ──────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if not multiplayer.is_server():
		return
	if _locked:
		return
	get_tree().call_group(&"level_reset_handler", &"reset_level")


@rpc("authority", "call_remote", "reliable")
func _client_unlock() -> void:
	unlock()
