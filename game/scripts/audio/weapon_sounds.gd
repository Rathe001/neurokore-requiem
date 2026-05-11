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
var _sounds: Dictionary = {}  # StringName → { fire: Array[AudioStream], impact: Array[AudioStream], ... }

# Volume offsets per category (dB). Tune these so weapons sit right in the mix
# without touching individual asset gains.
const FIRE_DB := 0.0
const IMPACT_DB := -3.0
const MISS_DB := -6.0

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
func play_fire(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"fire", pos, FIRE_DB)


## Play an impact sound at the hit location.
func play_impact(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"impact", pos, IMPACT_DB)


## Play a miss/whiff sound at the attack origin.
func play_miss(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"miss", pos, MISS_DB)


## Play a reload sound at the weapon holder's position.
func play_reload(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"reload", pos, FIRE_DB)


## Play alt-fire sound.
func play_alt_fire(weapon_key: StringName, pos: Vector3) -> void:
	_play_random(_resolve_key(weapon_key), &"alt_fire", pos, FIRE_DB)


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

func _play_random(base_key: StringName, category: StringName, pos: Vector3, db: float) -> void:
	if base_key == &"":
		return
	var set: Dictionary = _sounds.get(base_key, {})
	var pool: Array = set.get(category, [])
	if pool.is_empty():
		return
	var stream: AudioStream = pool[randi() % pool.size()]
	SFX.play_at(stream, pos, db)


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# Register empty sound sets for every known weapon archetype. When you
	# add audio assets, preload them and append to the appropriate array.
	#
	# Example (once you have assets):
	#   _register(&"melee_1h", {
	#       fire = [preload("res://resources/audio/sfx/weapons/melee_1h/slash_01.wav")],
	#       impact = [preload("res://resources/audio/sfx/weapons/melee_1h/hit_01.wav")],
	#   })
	_register(&"melee_1h", {})
	_register(&"melee_2h", {})
	_register(&"ranged_1h", {})
	_register(&"ranged_2h", {})
	_register(&"smg_1h", {})
	_register(&"sniper_2h", {})
	_register(&"shotgun_2h", {})
	_register(&"rpg_2h", {})
	_register(&"lmg_2h", {})
	_register(&"accelerator_2h", {})
	_register(&"taser_2h", {})


func _register(key: StringName, set: Dictionary) -> void:
	# Normalize: ensure every category key exists as an array.
	for cat in [&"fire", &"impact", &"miss", &"reload", &"alt_fire"]:
		if not set.has(cat):
			set[cat] = []
	_sounds[key] = set
