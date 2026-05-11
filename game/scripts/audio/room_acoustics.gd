extends Node
## Tracks the player's current acoustic zone and crossfades the reverb effect
## on the ReverbSend audio bus. Zones are registered by LevelBuilder during the
## build pass; each zone carries an AcousticProfile (authored or auto-derived
## from room area).
##
## Player room detection uses the same cell-gated approach as ProximityLighting:
## zone membership is only re-evaluated when the player crosses a 4 m cell
## boundary, so the per-frame cost is a single lerp toward target reverb params.

const CELL_SIZE := 4.0
const _INV_CELL := 1.0 / CELL_SIZE
const _UNSET_CELL := Vector2i(2147483647, 2147483647)
const CROSSFADE_SPEED := 2.0  # inverse seconds — ~0.5 s full transition
const REVERB_BUS_NAME := &"ReverbSend"

# Default profile used when the player is outside every registered zone
# (transition seam or before any level is built). Moderate, neutral reverb.
var _default_profile: AcousticProfile = AcousticProfile.from_area(40.0)

var _zones: Array[Dictionary] = []  # {center: Vector3, half_ext: Vector2, profile: AcousticProfile}
var _last_cell: Vector2i = _UNSET_CELL
var _current: AcousticProfile       # what the reverb currently sounds like
var _target: AcousticProfile         # what we're fading toward
var _lerp_t: float = 1.0            # 0 = just started fading, 1 = arrived
var _reverb: AudioEffectReverb
var _bus_idx: int = -1
var _cached_player: Node3D


func _ready() -> void:
	_find_reverb_effect()
	_current = _default_profile
	_target = _default_profile
	_apply_profile(_current)


func register_zone(center: Vector3, half_ext: Vector2, profile: AcousticProfile) -> void:
	_zones.append({center = center, half_ext = half_ext, profile = profile})


func clear_zones() -> void:
	_zones.clear()
	_last_cell = _UNSET_CELL
	_current = _default_profile
	_target = _default_profile
	_lerp_t = 1.0
	_apply_profile(_current)


func _process(delta: float) -> void:
	if _reverb == null:
		return
	# Refresh player reference when stale (scene change, respawn).
	if not is_instance_valid(_cached_player) or not _cached_player.is_inside_tree():
		_cached_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _cached_player == null:
		return

	var p := _cached_player.global_position
	var cell := Vector2i(int(floor(p.x * _INV_CELL)), int(floor(p.z * _INV_CELL)))

	# Only re-check zone membership on cell crossing.
	if cell != _last_cell:
		_last_cell = cell
		var prof := _zone_at(p)
		if prof != _target:
			_current = _snapshot()
			_target = prof
			_lerp_t = 0.0

	# Advance crossfade.
	if _lerp_t < 1.0:
		_lerp_t = minf(_lerp_t + delta * CROSSFADE_SPEED, 1.0)
		_apply_lerped(_current, _target, _lerp_t)


## Returns the AcousticProfile for the zone the player is inside, or
## _default_profile if the player is between zones.
func _zone_at(pos: Vector3) -> AcousticProfile:
	for z: Dictionary in _zones:
		var c: Vector3 = z.center
		var he: Vector2 = z.half_ext
		if absf(pos.x - c.x) <= he.x and absf(pos.z - c.z) <= he.y:
			return z.profile
	return _default_profile


## Snapshot the reverb effect's current state into a temporary profile so we
## can lerp away from it smoothly even if we were mid-fade.
func _snapshot() -> AcousticProfile:
	var s := AcousticProfile.new()
	s.room_size = _reverb.room_size
	s.damping = _reverb.damping
	s.spread = _reverb.spread
	s.wet = _reverb.wet
	s.dry = _reverb.dry
	s.pre_delay_ms = _reverb.predelay_msec
	return s


func _apply_profile(prof: AcousticProfile) -> void:
	if _reverb == null:
		return
	_reverb.room_size = prof.room_size
	_reverb.damping = prof.damping
	_reverb.spread = prof.spread
	_reverb.wet = prof.wet
	_reverb.dry = prof.dry
	_reverb.predelay_msec = prof.pre_delay_ms


func _apply_lerped(from: AcousticProfile, to: AcousticProfile, t: float) -> void:
	if _reverb == null:
		return
	_reverb.room_size = lerpf(from.room_size, to.room_size, t)
	_reverb.damping = lerpf(from.damping, to.damping, t)
	_reverb.spread = lerpf(from.spread, to.spread, t)
	_reverb.wet = lerpf(from.wet, to.wet, t)
	_reverb.dry = lerpf(from.dry, to.dry, t)
	_reverb.predelay_msec = lerpf(from.pre_delay_ms, to.pre_delay_ms, t)


func _find_reverb_effect() -> void:
	_bus_idx = AudioServer.get_bus_index(REVERB_BUS_NAME)
	if _bus_idx < 0:
		push_warning("[RoomAcoustics] Bus '%s' not found — reverb disabled." % REVERB_BUS_NAME)
		return
	for i in AudioServer.get_bus_effect_count(_bus_idx):
		var fx := AudioServer.get_bus_effect(_bus_idx, i)
		if fx is AudioEffectReverb:
			_reverb = fx
			return
	push_warning("[RoomAcoustics] No AudioEffectReverb on bus '%s'." % REVERB_BUS_NAME)
