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

# Distance-driven reverb send. Each frame we scan playing pool players,
# find the loudest distance contribution, and scale the SFX bus send to
# ReverbSend accordingly. Close sounds stay dry, distant sounds push
# more signal into the room reverb.
const REVERB_SEND_BUS := &"ReverbSend"
const REVERB_MIN_DISTANCE := 3.0   # below this → fully dry
const REVERB_MAX_DISTANCE := 25.0  # at/above this → maximum send
const REVERB_SEND_MIN_DB := -40.0  # effectively silent send
const REVERB_SEND_MAX_DB := -6.0   # strongest reverb contribution
var _sfx_bus_idx: int = -1
var _reverb_bus_idx: int = -1

var _pool: Array[AudioStreamPlayer3D] = []
var _idx: int = 0
var _ui_player: AudioStreamPlayer
# Reserved pool slots — _claim_player skips these so long-running sounds
# (channel hold loops) aren't evicted by rapid one-shots.
var _reserved: Dictionary = {}  # AudioStreamPlayer3D → true
# Cached listener node — resolved once via the &"audio_listener" group
# (the camera adds its top-level AudioListener3D to that group on build).
# Cleared and re-resolved on demand whenever the cached node goes invalid.
var _listener_node: AudioListener3D
# Meta key set on pool players whose source should track the listener
# every frame. Without this, the source is positioned at play-time and
# never moves, while the listener follows the player on subsequent
# frames — even one frame of mismatch is enough to pan the player's
# own sounds in the wrong stereo direction.
const _ANCHORED_META := &"sfx_anchored_to_listener"


func _ready() -> void:
	# Run AFTER scene nodes so prototype_camera._snap_to_target has already
	# moved the listener for the current frame by the time we anchor
	# listener-locked sources to it. Autoloads default to process_priority 0
	# (same as scene nodes) with autoloads ordered first, so without bumping
	# this we'd read the previous frame's listener position — re-introducing
	# the same 1-frame drift the anchor was meant to fix.
	process_priority = 100
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = DEFAULT_BUS
		p.max_distance = MAX_DISTANCE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 5.0  # tighter than the 10m default — sounds pan and attenuate noticeably within combat range
		p.panning_strength = 1.2  # slightly exaggerated stereo spread for the fixed isometric camera
		p.attenuation_filter_cutoff_hz = ATTENUATION_FILTER_CUTOFF_HZ
		p.attenuation_filter_db = ATTENUATION_FILTER_DB
		add_child(p)
		_pool.append(p)
	_install_master_chain()
	_setup_reverb_send()


# Install a limiter on the SFX bus as a safety ceiling so nothing clips.
# Idempotent so hot-reloads / editor restarts don't stack duplicates.
func _install_master_chain() -> void:
	var bus_idx := AudioServer.get_bus_index(DEFAULT_BUS)
	if bus_idx < 0:
		push_warning("[SFX] '%s' bus not found — skipping master chain." % DEFAULT_BUS)
		return
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
##
## For player-originated sounds (weapon fire, footsteps) prefer
## play_at_listener() so volume/panning stay constant regardless of
## where the player stands on the isometric map.
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
# Reserved slots are always skipped.
func _claim_player() -> AudioStreamPlayer3D:
	for offset in POOL_SIZE:
		var slot := (_idx + offset) % POOL_SIZE
		var p := _pool[slot]
		if _reserved.has(p):
			continue
		if not p.playing:
			_idx = (slot + 1) % POOL_SIZE
			p.remove_meta(_ANCHORED_META)
			return p
	# All non-reserved busy — evict the oldest unreserved slot.
	for offset in POOL_SIZE:
		var slot := (_idx + offset) % POOL_SIZE
		var p := _pool[slot]
		if not _reserved.has(p):
			_idx = (slot + 1) % POOL_SIZE
			p.remove_meta(_ANCHORED_META)
			return p
	# Degenerate: every slot reserved (shouldn't happen). Fall back.
	var fallback := _pool[_idx]
	_idx = (_idx + 1) % POOL_SIZE
	fallback.remove_meta(_ANCHORED_META)
	return fallback


## Claim a pool player and mark it reserved so it won't be evicted.
## Caller MUST call release_player() when done.
func claim_reserved(stream: AudioStream, pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var player := _claim_player()
	_reserved[player] = true
	player.stream = stream
	player.global_position = pos
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return player


## Release a previously reserved player back to the pool.
func release_player(player: AudioStreamPlayer3D) -> void:
	_reserved.erase(player)
	player.stop()


## Play a sound at the active AudioListener3D position — zero distance
## attenuation, stable stereo center. Use for the local player's own
## weapon fire, footsteps, and channel loops so movement across the
## isometric map doesn't shift their volume or panning.
##
## The returned pool player is flagged with _ANCHORED_META so _process
## keeps its position locked to the live listener position. Without
## that follow, the source stays where it was at play-time while the
## listener moves with the player on the next frame, and the relative
## offset causes the source to pan opposite to player movement.
func play_at_listener(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var player := play_at(stream, _listener_pos(), volume_db, pitch_scale)
	if player != null:
		player.set_meta(_ANCHORED_META, true)
	return player


## Like claim_reserved but at the listener position. The returned player
## is anchored — see play_at_listener for why.
func claim_reserved_at_listener(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var player := claim_reserved(stream, _listener_pos(), volume_db, pitch_scale)
	if player != null:
		player.set_meta(_ANCHORED_META, true)
	return player


## Resolve the current AudioListener3D node (the one prototype_camera
## marks current=true). Cached to avoid the per-frame group walk; the
## cache invalidates on listener disposal or current=false.
func _resolve_listener_node() -> AudioListener3D:
	if _listener_node != null and is_instance_valid(_listener_node) and _listener_node.current:
		return _listener_node
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(&"audio_listener"):
		var l := node as AudioListener3D
		if l != null and l.current:
			_listener_node = l
			return l
	return null


## Resolve the AudioListener3D position. Prefers the actual listener
## node (camera-owned, sits at player chest height) so listener-anchored
## sources can be co-located exactly; falls back to player or camera
## position if the listener hasn't been built yet.
func _listener_pos() -> Vector3:
	var listener := _resolve_listener_node()
	if listener != null:
		return listener.global_position
	var tree := get_tree()
	if tree != null:
		var player := tree.get_first_node_in_group(&"player") as Node3D
		if player != null:
			return player.global_position
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			return cam.global_position
	return Vector3.ZERO


## Non-positional shortcut for UI sounds (menu clicks, notifications, etc.).
func play_ui(stream: AudioStream, volume_db: float = 0.0) -> void:
	if _ui_player == null:
		_ui_player = AudioStreamPlayer.new()
		_ui_player.bus = &"UI"
		add_child(_ui_player)
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()


# ── Distance-driven reverb send ─────────────────────────────────────────────

func _setup_reverb_send() -> void:
	_sfx_bus_idx = AudioServer.get_bus_index(DEFAULT_BUS)
	_reverb_bus_idx = AudioServer.get_bus_index(REVERB_SEND_BUS)
	if _sfx_bus_idx < 0 or _reverb_bus_idx < 0:
		push_warning("[SFX] Could not find SFX or ReverbSend bus — distance reverb disabled.")
		return
	# Enable the SFX → ReverbSend send. Godot's bus send copies the
	# signal to the target bus (SFX still routes to Master as normal).
	# We control how much reverb is audible by scaling ReverbSend's
	# volume each frame based on the farthest active sound.
	AudioServer.set_bus_send(_sfx_bus_idx, REVERB_SEND_BUS)
	# Start fully dry.
	AudioServer.set_bus_volume_db(_reverb_bus_idx, REVERB_SEND_MIN_DB)
	# Godot requires the send to be explicitly enabled on the source bus.
	AudioServer.set_bus_mute(_reverb_bus_idx, false)


func _process(_delta: float) -> void:
	# Listener-anchored sources: snap every flagged pool player to the
	# current listener position before the audio mix reads positions for
	# the upcoming frame. Without this, panning drifts opposite to player
	# movement (source set once at play-time, listener follows each frame).
	var listener := _resolve_listener_node()
	if listener != null:
		var lpos := listener.global_position
		for p: AudioStreamPlayer3D in _pool:
			if p.playing and p.has_meta(_ANCHORED_META):
				p.global_position = lpos

	if _reverb_bus_idx < 0:
		return
	var cam_pos := Vector3.ZERO
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null:
			cam_pos = cam.global_position
	# Find the farthest currently-playing sound and scale reverb send
	# accordingly. Max-of-all approach so a single distant gunshot pushes
	# the reverb up even if nearby sounds are also playing — this reads
	# more natural than averaging, which dilutes distant cues.
	var max_t: float = 0.0
	for p: AudioStreamPlayer3D in _pool:
		if not p.playing:
			continue
		var dist := p.global_position.distance_to(cam_pos)
		var t := clampf((dist - REVERB_MIN_DISTANCE) / (REVERB_MAX_DISTANCE - REVERB_MIN_DISTANCE), 0.0, 1.0)
		if t > max_t:
			max_t = t
	var send_db := lerpf(REVERB_SEND_MIN_DB, REVERB_SEND_MAX_DB, max_t)
	AudioServer.set_bus_volume_db(_reverb_bus_idx, send_db)
