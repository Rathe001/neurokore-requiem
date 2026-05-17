class_name PrototypeSwitch
extends HoverableInteractable

enum Action { TOGGLE, OPEN, CLOSE, UNLOCK }

const COLOR_ACTIVE := Color(1.0, 0.15, 0.1, 1.0)
const COLOR_USED := Color(0.35, 0.2, 0.2, 1.0)
const LAMP_EMISSION_ON := 12.0
const LAMP_EMISSION_OFF := 0.5
const LAMP_EMISSION_HOVER := 24.0
# Blink pattern: on for BLINK_ON seconds, off for BLINK_OFF. Short off-
# phase keeps the switch readable while the strobe grabs attention from
# across the room. Disabled once the switch is used.
const BLINK_ON := 0.6
const BLINK_OFF := 0.25
# OmniLight3D attached to the lamp so the switch actually casts colored
# light onto nearby walls / floor.
const LAMP_LIGHT_ENERGY_ON := 2.5
const LAMP_LIGHT_ENERGY_OFF := 0.15
const LAMP_LIGHT_RANGE := 6.0

@export var target_door: NodePath
@export var action: Action = Action.TOGGLE

@onready var mesh: MeshInstance3D = $Mesh
@onready var lamp: MeshInstance3D = $Lamp

var _used: bool = false
var _mat: StandardMaterial3D
var _omni: OmniLight3D
var _blink_t: float = 0.0
var _blink_on: bool = true

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = LAMP_EMISSION_ON
	lamp.material_override = _mat
	_omni = OmniLight3D.new()
	_omni.light_color = COLOR_ACTIVE
	_omni.light_energy = LAMP_LIGHT_ENERGY_ON
	_omni.omni_range = LAMP_LIGHT_RANGE
	_omni.omni_attenuation = 1.5
	_omni.shadow_enabled = false
	_omni.light_volumetric_fog_energy = 0.0
	lamp.add_child(_omni)
	super._ready()
	_refresh_lamp()
	set_process(true)
	add_to_group(&"minimap_marker")


# Public getter so the minimap marker overlay can determine whether to
# draw the switch as still-active (bright) or already-used (dim).
func is_used() -> bool:
	return _used


func _process(delta: float) -> void:
	if _used or _mat == null:
		return
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink_on = not _blink_on
		_blink_t = BLINK_ON if _blink_on else BLINK_OFF
		var em := LAMP_EMISSION_ON if _blink_on else LAMP_EMISSION_OFF
		_mat.emission_energy_multiplier = em
		if _omni != null:
			_omni.light_energy = LAMP_LIGHT_ENERGY_ON if _blink_on else LAMP_LIGHT_ENERGY_OFF

func _on_mouse_entered() -> void:
	super._on_mouse_entered()
	if _mat != null and not _used:
		_mat.emission_energy_multiplier = LAMP_EMISSION_HOVER

func _on_mouse_exited() -> void:
	super._on_mouse_exited()
	# Blink resumes on next _process tick — just reset the timer so the
	# transition from hover → blink isn't jarring.
	_blink_t = 0.0

func _get_outline_source() -> MeshInstance3D:
	return mesh

# Clear the "used" lamp state so the switch is interactable again after reset.
func reset_state() -> void:
	_used = false
	_refresh_lamp()
	_set_interactive(true)

func interact(_user: Node) -> void:
	if target_door == NodePath():
		return
	if NetState.is_in_lobby() and NetState.is_client():
		_request_interact.rpc_id(1)
		return
	var door := get_node_or_null(target_door) as PrototypeDoor
	if door == null:
		return
	# One-shot actions become inert once consumed so multi-switch puzzles can't
	# be cheesed by re-triggering the same panel. Toggle is intentionally
	# excluded — it's the only repeatable action.
	if _used and action != Action.TOGGLE:
		return
	WeaponSounds.play_generic(&"switch_click", global_position)
	_do_action(door)

func _mark_used() -> void:
	if _used:
		return
	_used = true
	_refresh_lamp()
	_set_interactive(false)
	# Mission tracker — only UNLOCK switches feed the switches phase. Other
	# actions (OPEN/CLOSE doors directly) aren't part of the boss-gating
	# puzzle chain. Resolve the door node so MissionState matches the
	# switch back to its registered puzzle.
	if action == Action.UNLOCK and target_door != NodePath():
		var door := get_node_or_null(target_door)
		if door != null:
			MissionState.notify_switch_used_for_door(door)

# Used switches drop out of mouse picking, the SpatialGrid interactable index,
# and any active hover/tooltip state so they read as inert. reset_state() flips
# this back on for NG+ runs. We toggle BOTH input_ray_pickable AND
# collision_layer because either alone is enough to leak picks in some
# Godot 4 builds — belt and suspenders.
func _set_interactive(on: bool) -> void:
	input_ray_pickable = on
	collision_layer = 1 if on else 0
	if on:
		add_to_group(&"interactables")
		SpatialGrid.register(self, &"interactables")
	else:
		SpatialGrid.unregister(self)
		remove_from_group(&"interactables")
		remove_from_group(&"hovered_clickable")
		remove_from_group(&"tooltip_target")
		if _outline != null:
			_outline.visible = false
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func _refresh_lamp() -> void:
	var c := COLOR_USED if _used else COLOR_ACTIVE
	_mat.albedo_color = c
	_mat.emission = c
	_mat.emission_energy_multiplier = 0.0 if _used else LAMP_EMISSION_ON
	if _omni != null:
		_omni.light_color = c
		_omni.light_energy = 0.0 if _used else LAMP_LIGHT_ENERGY_ON
	# Reset blink state so it starts in the "on" phase after a refresh.
	_blink_on = true
	_blink_t = BLINK_ON


func _do_action(door: PrototypeDoor) -> void:
	match action:
		Action.TOGGLE:
			door.toggle()
			if NetState.is_in_lobby():
				door._client_set_open.rpc(door.is_open())
		Action.OPEN:
			door.open()
			_mark_used()
			if NetState.is_in_lobby():
				door._client_set_open.rpc(door.is_open())
				_client_mark_used.rpc()
		Action.CLOSE:
			door.close()
			_mark_used()
			if NetState.is_in_lobby():
				door._client_set_open.rpc(door.is_open())
				_client_mark_used.rpc()
		Action.UNLOCK:
			# door.unlock() broadcasts its own _client_unlock RPC.
			door.unlock()
			_mark_used()
			if NetState.is_in_lobby():
				_client_mark_used.rpc()


# ── Multiplayer RPCs ──────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if not multiplayer.is_server():
		return
	var door := get_node_or_null(target_door) as PrototypeDoor
	if door == null:
		return
	if _used and action != Action.TOGGLE:
		return
	_do_action(door)


@rpc("authority", "call_remote", "reliable")
func _client_mark_used() -> void:
	_mark_used()
