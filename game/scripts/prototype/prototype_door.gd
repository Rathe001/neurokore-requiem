class_name PrototypeDoor
extends HoverableInteractable

## Open/close take their full sound-effect duration to slide — feels weighty
## and matches the audio so the visual settle and the SFX tail land together.
## Tune these alongside the audio: if you swap in a different door_open.wav
## with a different length, update SLIDE_OPEN_DURATION too.
const SLIDE_OPEN_DURATION := 1.71
const SLIDE_CLOSE_DURATION := 1.19
const SLIDE_DISTANCE := 4.7
const FRAME_LOCKED := Color(1.0, 0.25, 0.2, 1.0)
const FRAME_UNLOCKED := Color(0.3, 1.0, 0.45, 1.0)
const FRAME_HOVER_BOOST := 1.6
# Door dimensions (matches the BoxMesh in prototype_door.tscn). X = thickness,
# Y = height, Z = width.
const DOOR_THICKNESS := 0.4
const DOOR_HEIGHT := 4.5
const DOOR_WIDTH := 4.0
# State-frame trim around each wide face of the door — thickness of each bar
# and how far it juts out past the door surface so it reads as a glowing rim.
const FRAME_BAR := 0.12
const FRAME_OUT := 0.04

@export var locked: bool = false

# Number of unlock() calls required before the door actually opens. Multi-switch
# puzzles set this on the door (e.g. 3 switches → 3); each switch's unlock()
# decrements the counter, and only the last call flips `locked` to false.
@export_range(1, 9) var unlocks_required: int = 1

# Listen for the boss-died group call and unlock automatically. Mutually
# compatible with multi-switch (boss kill counts as one unlock).
@export var unlock_on_boss: bool = false

@onready var mesh: MeshInstance3D = $Mesh
@onready var collision: CollisionShape3D = $Collision

var _open: bool = false
var _rest_y: float = 0.0
var _initial_locked: bool = false
var _unlocks_remaining: int = 1
var _hovered: bool = false
var _interact_cooldown: bool = false
var _tween: Tween
var _mat: ShaderMaterial
var _frame_mat: StandardMaterial3D
var _frame_bars: Array[MeshInstance3D] = []

const _DOOR_SHADER: Shader = preload("res://scripts/prototype/tech_door.gdshader")

func _ready() -> void:
	add_to_group(&"doors")
	if unlock_on_boss:
		add_to_group(&"boss_listeners")
	_rest_y = mesh.position.y
	_initial_locked = locked
	_unlocks_remaining = unlocks_required
	# Dedicated door shader — same colour palette as the walls but the
	# detailing rides with the slab as it slides (mesh-local UVs instead of
	# world-space triplanar) so the panel pattern doesn't scroll.
	_mat = ShaderMaterial.new()
	_mat.shader = _DOOR_SHADER
	mesh.material_override = _mat
	super._ready()
	_build_state_frame()
	_refresh_tint()

func _get_outline_source() -> MeshInstance3D:
	# Skip the inherited grow-and-cull-front outline; doors use _frame_bars
	# (which work even when surrounding walls would occlude the silhouette
	# halo). Hover feedback comes through the frame brightening instead.
	return null

func _get_tooltip_text() -> String:
	if not locked:
		return display_name
	if unlocks_required > 1:
		var done := unlocks_required - _unlocks_remaining
		return "%s (Locked — %d / %d)" % [display_name, done, unlocks_required]
	return "%s (Locked)" % display_name

# Configure lock state at level build time. Sets the public fields AND the
# internal counters/snapshot that reset_state() restores from, so puzzles can
# wire a door post-_ready without having to poke private state. Called by
# the puzzle layer (e.g. SwitchDoorPuzzle); designer-set values via
# RoomDef.locked_doors / unlock_required_doors take effect via the
# DoorBuilder before _ready instead.
func setup_lock(unlocks: int, lock: bool, on_boss: bool = false) -> void:
	unlocks_required = maxi(1, unlocks)
	locked = lock
	_initial_locked = lock
	_unlocks_remaining = unlocks_required
	if on_boss:
		unlock_on_boss = true
		if not is_in_group(&"boss_listeners"):
			add_to_group(&"boss_listeners")
	_refresh_tint()


# Restore initial open/locked state on level reset.
func reset_state() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_open = false
	collision.disabled = false
	mesh.position.y = _rest_y
	locked = _initial_locked
	_unlocks_remaining = unlocks_required
	_refresh_tint()

func is_open() -> bool:
	return _open

func is_locked() -> bool:
	return locked

func open() -> void:
	if _open or locked:
		return
	_open = true
	collision.disabled = true
	_animate(_rest_y + SLIDE_DISTANCE, SLIDE_OPEN_DURATION)
	_refresh_tint()
	WeaponSounds.play_generic(&"door_open", global_position)

func close() -> void:
	if not _open:
		return
	_open = false
	collision.disabled = false
	_animate(_rest_y, SLIDE_CLOSE_DURATION)
	_refresh_tint()
	WeaponSounds.play_generic(&"door_close", global_position)

func toggle() -> void:
	if _open:
		close()
	else:
		open()

func interact(_user: Node) -> void:
	if locked:
		# Surface a hint via the same tooltip channel the exit pad uses for
		# its locked state. Without this the click silently no-ops and the
		# player thinks the click missed.
		get_tree().call_group(&"interactable_tooltip", &"show_text", tr(&"DOOR_LOCKED"))
		return
	if NetState.is_in_lobby() and NetState.is_client():
		_request_interact.rpc_id(1)
		return
	toggle()
	if NetState.is_in_lobby():
		_client_set_open.rpc(_open)

func unlock() -> void:
	if not locked:
		return
	_unlocks_remaining = maxi(0, _unlocks_remaining - 1)
	if _unlocks_remaining > 0:
		# Partial progress — keep locked but refresh in case UI shows count.
		_refresh_tint()
		if NetState.is_in_lobby():
			_client_unlock.rpc(_unlocks_remaining)
		return
	locked = false
	_refresh_tint()
	if NetState.is_in_lobby():
		_client_unlock.rpc(0)


## Re-increment the lock counter by one. Used by ClearRoomPuzzle when a
## charmed guard reverts to hostile — the door counted the charm as a
## "kill" and needs to un-count it. No-op when the door is already
## physically open (player already walked through).
func relock_one() -> void:
	if _open:
		return
	_unlocks_remaining += 1
	locked = true
	_refresh_tint()
	if NetState.is_in_lobby():
		_client_relock.rpc()

# Group dispatch from PrototypeEnemy._die() when a boss falls. Only doors
# flagged with unlock_on_boss subscribe.
func on_boss_died(_boss: Node) -> void:
	if NetState.is_in_lobby() and NetState.is_client():
		return
	unlock()

func _animate(target_y: float, duration: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(mesh, "position:y", target_y, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

func _on_mouse_entered() -> void:
	_hovered = true
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	var text := _get_tooltip_text()
	if text != "":
		get_tree().call_group(&"interactable_tooltip", &"show_text", text)
	_refresh_tint()

func _on_mouse_exited() -> void:
	_hovered = false
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
	_refresh_tint()

# Builds an emissive trim frame on each wide face of the door so the locked /
# unlocked state is readable from any angle. The grow-and-cull-front outline
# trick is unreliable here because the doorway walls occlude the silhouette
# halo; explicit bars sit out past the door surface and stay visible.
func _build_state_frame() -> void:
	_frame_mat = StandardMaterial3D.new()
	_frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_mat.emission_enabled = true
	_frame_mat.emission_energy_multiplier = 2.0
	var half_thick := DOOR_THICKNESS * 0.5 + FRAME_OUT * 0.5
	var inner_h := DOOR_HEIGHT - FRAME_BAR * 2.0
	for s: int in [1, -1]:
		var x := float(s) * half_thick
		# Top, bottom (full width)
		_add_frame_bar(Vector3(x, (DOOR_HEIGHT - FRAME_BAR) * 0.5, 0.0), Vector3(FRAME_OUT, FRAME_BAR, DOOR_WIDTH))
		_add_frame_bar(Vector3(x, -(DOOR_HEIGHT - FRAME_BAR) * 0.5, 0.0), Vector3(FRAME_OUT, FRAME_BAR, DOOR_WIDTH))
		# Left, right (between top and bottom bars so corners don't overlap)
		_add_frame_bar(Vector3(x, 0.0, -(DOOR_WIDTH - FRAME_BAR) * 0.5), Vector3(FRAME_OUT, inner_h, FRAME_BAR))
		_add_frame_bar(Vector3(x, 0.0, (DOOR_WIDTH - FRAME_BAR) * 0.5), Vector3(FRAME_OUT, inner_h, FRAME_BAR))

func _add_frame_bar(pos: Vector3, size: Vector3) -> void:
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	bar.mesh = box
	bar.position = pos
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.material_override = _frame_mat
	mesh.add_child(bar)
	_frame_bars.append(bar)

func _refresh_tint() -> void:
	if _frame_mat == null:
		return
	# Hide the frame when the door is up — there's no surface to rim.
	for bar in _frame_bars:
		bar.visible = not _open
	var oc := FRAME_LOCKED if locked else FRAME_UNLOCKED
	if _hovered:
		oc = Color(
			minf(oc.r * FRAME_HOVER_BOOST, 1.0),
			minf(oc.g * FRAME_HOVER_BOOST, 1.0),
			minf(oc.b * FRAME_HOVER_BOOST, 1.0),
			1.0,
		)
	_frame_mat.albedo_color = oc
	_frame_mat.emission = oc


# ── Multiplayer RPCs ──────────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if not multiplayer.is_server():
		return
	if locked or _interact_cooldown:
		return
	_interact_cooldown = true
	toggle()
	_client_set_open.rpc(_open)
	# Brief cooldown prevents two near-simultaneous RPCs from toggling twice.
	get_tree().create_timer(0.15).timeout.connect(func() -> void: _interact_cooldown = false)


@rpc("authority", "call_remote", "reliable")
func _client_set_open(is_open: bool) -> void:
	if is_open:
		if not _open:
			_open = true
			collision.disabled = true
			_animate(_rest_y + SLIDE_DISTANCE, SLIDE_OPEN_DURATION)
			_refresh_tint()
	else:
		if _open:
			_open = false
			collision.disabled = false
			_animate(_rest_y, SLIDE_CLOSE_DURATION)
			_refresh_tint()


@rpc("authority", "call_remote", "reliable")
func _client_unlock(remaining: int) -> void:
	_unlocks_remaining = remaining
	if remaining <= 0:
		locked = false
	_refresh_tint()


@rpc("authority", "call_remote", "reliable")
func _client_relock() -> void:
	_unlocks_remaining += 1
	locked = true
	_refresh_tint()
