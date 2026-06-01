class_name PrototypeExit
extends HoverableInteractable

# Freight elevator exit. Joins "boss_listeners" so PrototypeEnemy dispatches
# on_boss_died() when any boss falls. The visual is a single Meshy GLB
# (assets/models/objects/elevator/elevator.glb); locked/unlocked state is
# communicated through the interact tooltip rather than a per-corner
# status light. on_boss_died → unlock → interact() resets the level.

@onready var _elevator: Node3D = $Elevator

var _locked: bool = true
var _outline_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group(&"boss_listeners")
	add_to_group(&"minimap_marker")
	# The GLB instance is a Node3D with one MeshInstance3D child — walk
	# down to grab it for the hover-outline raycaster.
	_outline_mesh = _find_mesh_instance(_elevator)
	super._ready()


func _get_outline_source() -> MeshInstance3D:
	return _outline_mesh


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
	MissionState.notify_exit_unlocked()


func lock() -> void:
	if _locked:
		return
	_locked = true


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


func _find_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for c in root.get_children():
		var found := _find_mesh_instance(c)
		if found != null:
			return found
	return null


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
