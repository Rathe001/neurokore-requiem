extends Node
## Autoload that maps weapon archetypes to sound sets and plays positional audio
## alongside combat visuals. Sounds are keyed by weapon_base_id (player weapons)
## or weapon_id (enemy weapons); CombatVisuals calls into this from its spawn_*
## methods so both SP and MP peers hear the same effects.
##
## Drop .ogg/.wav files into resources/audio/sfx/weapons/{archetype}/ and
## register them below. Godot prefers .wav for short one-shots (no decode
## latency) and .ogg for longer loops.

## Sound set per weapon archetype. Each entry maps a string key to a small
## pool of AudioStreams — fire picks a random entry from the array so repeated
## shots don't sound mechanical.
##
## Keys:
##   fire      — weapon discharge / swing
##   impact    — hit lands on a target (flesh/metal)
##   miss      — whiff (melee), ricochet (ranged)
##   reload    — magazine swap (bullet weapons only)
##   alt_fire  — secondary fire mode
##
## To add sounds for a weapon:
##   1. Drop .ogg/.wav into resources/audio/sfx/weapons/{archetype}/
##   2. Preload and add to the matching array in _SOUNDS below.

# ── Sound registry ──────────────────────────────────────────────────────────
# Populated lazily on first access via _ensure_loaded(). Empty arrays until
# actual audio assets are added — the play helpers gracefully no-op when the
# array is empty, so the game runs silently until you drop files in.

var _loaded: bool = false
var _sounds: Dictionary = {}  # StringName → { fire: Array[AudioStream], impact: Array[AudioStream], hold_loop: AudioStream, ... }

# Channel-loop hold sounds — a single continuous AudioStream per weapon
# that plays for as long as the player holds fire. Kept off the per-tick
# fire path because retriggering a 2-second clip seven times a second
# (taser tick rate) produces chaos. is_channel_weapon() is used by the
# fire-time path to suppress play_fire in favor of these.

# Volume offsets per category (dB). Tune these so weapons sit right in the mix
# without touching individual asset gains.
const FIRE_DB := 0.0
const IMPACT_DB := -3.0
const MISS_DB := -6.0

# Per-play variance — gives every shot a slightly different timbre so
# repeated fires don't read as a mechanical pulse, and enemies sound
# audibly distinct from the player so the mix doesn't blur when both
# are shooting.
#
# Pitch: player stays close to 1.0 (subtle variance), enemies are
# consistently lower so the player's "voice" carries above incoming
# fire. Range is per-shot, so each tick / enemy / volley gets fresh
# randomisation.
const PLAYER_PITCH_RANGE := Vector2(0.96, 1.04)
const ENEMY_PITCH_RANGE := Vector2(0.78, 0.92)
const VOLUME_JITTER_DB := 1.5  # ± this many dB on top of the category offset

# Mapping from enemy weapon_id → player weapon_base_id so enemies reuse the
# same sound sets. Enemies that carry a weapon with no player equivalent
# (e.g. a future unique boss weapon) can be added as their own key in _SOUNDS.
const _ENEMY_TO_BASE: Dictionary = {
	&"blade": &"melee_1h",
	&"sledgehammer": &"melee_2h",
	&"smg": &"smg_1h",
	&"laser_pistol": &"ranged_1h",
	&"plasma_rifle": &"ranged_2h",
	&"sniper_rifle": &"sniper_2h",
	&"shotgun": &"shotgun_2h",
	&"taser": &"taser_2h",
}


func _ready() -> void:
	_ensure_loaded()


## Resolve a weapon key (player weapon_base_id OR enemy weapon_id) to its
## canonical sound-set key. Returns &"" if no mapping exists.
func _resolve_key(weapon_key: StringName) -> StringName:
	if _sounds.has(weapon_key):
		return weapon_key
	if _ENEMY_TO_BASE.has(weapon_key):
		return _ENEMY_TO_BASE[weapon_key]
	return &""


# ── Public API ──────────────────────────────────────────────────────────────

## Play a weapon fire sound at `pos`. `weapon_key` is weapon_base_id or
## enemy weapon_id. No-ops gracefully when no sound is registered.
## Enemy IDs (the keys of _ENEMY_TO_BASE) automatically get the lower
## pitch range so enemy fire reads distinct from player fire.
func play_fire(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"fire", pos, FIRE_DB, _is_enemy_key(weapon_key))


## Play an impact sound at the hit location.
func play_impact(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"impact", pos, IMPACT_DB, _is_enemy_key(weapon_key))


## Play a miss/whiff sound at the attack origin.
func play_miss(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"miss", pos, MISS_DB, _is_enemy_key(weapon_key))


## Play a reload sound at the weapon holder's position.
func play_reload(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"reload", pos, FIRE_DB, _is_enemy_key(weapon_key))


## Play alt-fire sound.
func play_alt_fire(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"alt_fire", pos, FIRE_DB, _is_enemy_key(weapon_key))


# True when `weapon_key` is an enemy weapon_id (key of _ENEMY_TO_BASE)
# rather than a player weapon_base_id. Drives the lower pitch range.
func _is_enemy_key(weapon_key: StringName) -> bool:
	return _ENEMY_TO_BASE.has(weapon_key)


# ── Channel weapons (taser hold, future accelerator hold) ──────────────────

## True when this weapon plays a continuous hold loop (gated via
## is_channel_weapon) instead of per-tick fire sounds. Callers that
## drive channel ticks should skip play_fire and rely on the loop +
## the channel-start zap.
func is_channel_weapon(weapon_key: StringName) -> bool:
	var key := _resolve_key(weapon_key)
	if key == &"":
		return false
	var set: Dictionary = _sounds.get(key, {})
	var loop = set.get(&"hold_loop", null)
	return loop is AudioStream


## One-shot zap that fires when the channel starts. Same routing as
## play_fire but kept as a separate API so the channel start can play
## a dedicated "engage" sound (e.g. taser's initial pop) without
## doubling up on the hold loop.
func play_channel_start(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"fire", pos, FIRE_DB, _is_enemy_key(weapon_key))


## Spawn a looping AudioStreamPlayer3D for the channel hold sound,
## parented to `parent_node` so it follows the firer automatically.
## Returns the player (null when no hold loop is registered) so the
## caller can fade-in / fade-out / stop on channel end.
const CHANNEL_LOOP_BUS := &"SFX"
const CHANNEL_FADE_IN := 0.10
const CHANNEL_FADE_OUT := 0.20

func play_channel_loop(weapon_key: StringName, parent_node: Node3D) -> AudioStreamPlayer3D:
	var key := _resolve_key(weapon_key)
	if key == &"":
		return null
	var set: Dictionary = _sounds.get(key, {})
	var stream = set.get(&"hold_loop", null) as AudioStream
	if stream == null or parent_node == null:
		return null
	# WAV needs LOOP_FORWARD on the stream itself for the player to repeat.
	# Done lazily on first use; loop_end stays at 0 which Godot treats as
	# "to end of sample". The Godot editor lets you set this per-import
	# instead — either path works, runtime set is just more portable.
	if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var p := AudioStreamPlayer3D.new()
	p.bus = CHANNEL_LOOP_BUS
	p.stream = stream
	p.max_distance = 30.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = -40.0
	# Stable per-channel pitch so the held loop has a consistent tone
	# the whole time. Player gets a tiny variance for character; enemies
	# sit clearly lower so the hum is identifiable as theirs.
	var range := ENEMY_PITCH_RANGE if _is_enemy_key(weapon_key) else PLAYER_PITCH_RANGE
	p.pitch_scale = randf_range(range.x, range.y)
	parent_node.add_child(p)
	p.play()
	# Brief fade-in so the engagement reads as building rather than
	# hard-cutting in over the start zap.
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", 0.0, CHANNEL_FADE_IN)
	return p


## Stop a previously-claimed channel-loop player. Fades out then frees.
## Safe to call with null (no-op) so callers can stop unconditionally.
func stop_channel_loop(player: AudioStreamPlayer3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var tw := player.create_tween()
	tw.tween_property(player, "volume_db", -40.0, CHANNEL_FADE_OUT)
	tw.tween_callback(player.queue_free)


# ── Generic sounds (not weapon-specific) ────────────────────────────────────

var _generic: Dictionary = {}  # StringName → Array[AudioStream]

## Play a generic named sound (e.g. &"explosion", &"level_up", &"pickup").
## Register via register_generic().
func play_generic(sound_name: StringName, pos: Vector3, volume_db: float = 0.0) -> void:
	var pool: Array = _generic.get(sound_name, [])
	if pool.is_empty():
		return
	SFX.play_at(pool[randi() % pool.size()], pos, volume_db)


func register_generic(sound_name: StringName, streams: Array[AudioStream]) -> void:
	_generic[sound_name] = streams


# ── Internals ───────────────────────────────────────────────────────────────

func _play_random(base_key: StringName, category: StringName, pos: Vector3, db: float, is_enemy: bool = false) -> void:
	if base_key == &"":
		return
	var set: Dictionary = _sounds.get(base_key, {})
	var pool: Array = set.get(category, [])
	if pool.is_empty():
		return
	var stream: AudioStream = pool[randi() % pool.size()]
	# Per-play variance: pitch from the side-appropriate range, volume
	# jittered around the category default. The pitch range carries
	# enough of the "this is enemy fire" signal that the player can
	# subconsciously parse who's shooting without looking.
	var range := ENEMY_PITCH_RANGE if is_enemy else PLAYER_PITCH_RANGE
	var pitch: float = randf_range(range.x, range.y)
	var vol_jitter: float = randf_range(-VOLUME_JITTER_DB, VOLUME_JITTER_DB)
	SFX.play_at(stream, pos, db + vol_jitter, pitch)


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# Register sound sets per archetype. `_streams()` filters out any path
	# whose .wav/.ogg / .import sidecar isn't present yet, so partially-
	# populated folders don't crash the autoload — missing files just
	# degrade to silence for that category.
	_register(&"melee_1h", {})
	_register(&"melee_2h", {})
	_register(&"ranged_1h", {
		fire = _streams(["res://resources/audio/sfx/weapons/laser-pistol.wav"]),
	})
	_register(&"ranged_2h", {
		fire = _streams(["res://resources/audio/sfx/weapons/plasma-rifle.wav"]),
	})
	_register(&"smg_1h", {
		fire = _streams(["res://resources/audio/sfx/weapons/smg.wav"]),
	})
	_register(&"sniper_2h", {
		fire = _streams(["res://resources/audio/sfx/weapons/sniper-rifle.wav"]),
	})
	_register(&"shotgun_2h", {})
	_register(&"rpg_2h", {})
	_register(&"lmg_2h", {
		fire = _streams(["res://resources/audio/sfx/weapons/lmg.wav"]),
	})
	# Accelerator: same channel pattern as taser — punchy zap at engage
	# (clip_11) + continuous beam loop for the duration of the stream.
	# is_channel_weapon() returns true so per-tick fire is suppressed
	# in player_combat.resolve_skill_hit.
	_register(&"accelerator_2h", {
		fire = _streams(["res://resources/audio/sfx/weapons/energy-accelerator.wav"]),
		hold_loop = _load_one("res://resources/audio/sfx/weapons/energy-accelerator-hold.wav"),
	})
	# Taser: per-attack zap on the fire array, continuous crackle on
	# hold_loop. is_channel_weapon() returns true for it, so callers
	# in the channel-tick path skip the per-tick play_fire and rely on
	# the hold loop + the channel-start zap.
	_register(&"taser_2h", {
		fire = _streams(["res://resources/audio/sfx/weapons/charged-arc-taser.wav"]),
		hold_loop = _load_one("res://resources/audio/sfx/weapons/charged-arc-taser-hold.wav"),
	})


# Load a single AudioStream by path, null if missing. For hold_loop where
# we need a single stream (not an array of random alternates).
func _load_one(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


# Load each path at runtime; skip any that fail to resolve (file missing,
# .import sidecar not generated yet, type mismatch). Returns the filtered
# AudioStream array — empty when nothing loaded, which the player path
# already handles as "play nothing." Keeps the autoload robust against
# the typical drop-files-then-test iteration loop.
func _streams(paths: Array) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	for path: String in paths:
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream != null:
			out.append(stream)
	return out


func _register(key: StringName, set: Dictionary) -> void:
	# Normalize: ensure every category key exists as an array.
	for cat in [&"fire", &"impact", &"miss", &"reload", &"alt_fire"]:
		if not set.has(cat):
			set[cat] = []
	_sounds[key] = set
