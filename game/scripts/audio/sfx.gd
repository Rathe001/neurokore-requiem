extends Node
## Fire-and-forget positional audio helper. Pools AudioStreamPlayer3D nodes so
## callers never allocate — just `SFX.play_at(stream, pos)`.
##
## Also owns the SFX bus mastering chain (EQ, compressor, limiter). Raw sound
## clips arrive with wildly different loudness, sibilance and top-end energy;
## the chain pulls them all into a consistent character so they feel like
## they belong in the game rather than stitched-in audition clips.

const POOL_SIZE := 24
const DEFAULT_BUS := &"SFX"

# Distance filter — far-away sounds lose their high end. Cheap fake of
# air absorption without needing per-source raycasts. Cutoff at
# attenuation_filter_cutoff_hz, rolling toward attenuation_filter_db
# of attenuation by max_distance.
const ATTENUATION_FILTER_CUTOFF_HZ := 5000.0
const ATTENUATION_FILTER_DB := -12.0
const MAX_DISTANCE := 30.0

var _pool: Array[AudioStreamPlayer3D] = []
var _idx: int = 0
var _ui_player: AudioStreamPlayer


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = DEFAULT_BUS
		p.max_distance = MAX_DISTANCE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = ATTENUATION_FILTER_CUTOFF_HZ
		p.attenuation_filter_db = ATTENUATION_FILTER_DB
		add_child(p)
		_pool.append(p)
	_install_master_chain()


# Install EQ → Compressor → Limiter on the SFX bus if not already present.
# Idempotent so hot-reloads / editor restarts don't stack duplicates.
#
# - Low-pass at 9 kHz softens the spiky digital top-end that makes raw
#   weapon recordings sound dry and unmixed.
# - Compressor with -16 dB threshold and 3:1 ratio catches transient
#   peaks (gunshot attack spikes) and gently lifts the body so quiet
#   and loud effects sit closer together in perceived loudness.
# - Limiter at -0.5 dB ceiling catches anything that slips through.
func _install_master_chain() -> void:
	var bus_idx := AudioServer.get_bus_index(DEFAULT_BUS)
	if bus_idx < 0:
		push_warning("[SFX] '%s' bus not found — skipping master chain." % DEFAULT_BUS)
		return
	if not _has_effect(bus_idx, "AudioEffectLowPassFilter"):
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 9000.0
		lp.resonance = 0.5
		AudioServer.add_bus_effect(bus_idx, lp)
	if not _has_effect(bus_idx, "AudioEffectCompressor"):
		var comp := AudioEffectCompressor.new()
		comp.threshold = -16.0
		comp.ratio = 3.0
		comp.attack_us = 8000.0
		comp.release_ms = 80.0
		comp.gain = 1.0
		AudioServer.add_bus_effect(bus_idx, comp)
	if not _has_effect(bus_idx, "AudioEffectLimiter"):
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -0.5
		lim.threshold_db = -1.0
		AudioServer.add_bus_effect(bus_idx, lim)


func _has_effect(bus_idx: int, class_name_str: String) -> bool:
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var fx := AudioServer.get_bus_effect(bus_idx, i)
		if fx != null and fx.get_class() == class_name_str:
			return true
	return false


## Play a sound at a world position. Returns the player so the caller can
## tweak it after the fact if needed. `pitch_scale` is reset every call
## so the previous shot's pitch doesn't leak into a pool slot when it
## gets reused.
func play_at(stream: AudioStream, pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var player := _claim_player()
	player.stream = stream
	player.global_position = pos
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


# Pick a pool slot, preferring idle players over busy ones. Pure round-
# robin (the original implementation) evicted whatever slot _idx pointed
# at, even mid-sample — so a long sniper sound got clobbered by the
# 16th rapid SMG shot wrapping around. Walks the ring from _idx once
# looking for `playing == false`; falls back to the oldest slot when
# every player is in flight. Worst case 24 cheap bool checks per shot.
func _claim_player() -> AudioStreamPlayer3D:
	for offset in POOL_SIZE:
		var slot := (_idx + offset) % POOL_SIZE
		var p := _pool[slot]
		if not p.playing:
			_idx = (slot + 1) % POOL_SIZE
			return p
	# All busy — evict the oldest. Advance _idx so the next call hits a
	# different slot, distributing the "we ran out" pain across the pool.
	var fallback := _pool[_idx]
	_idx = (_idx + 1) % POOL_SIZE
	return fallback


## Non-positional shortcut for UI sounds (menu clicks, notifications, etc.).
func play_ui(stream: AudioStream, volume_db: float = 0.0) -> void:
	if _ui_player == null:
		_ui_player = AudioStreamPlayer.new()
		_ui_player.bus = &"UI"
		add_child(_ui_player)
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()
