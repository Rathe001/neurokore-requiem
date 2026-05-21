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

# Per-play variance — slight pitch/volume jitter so repeated fires
# don't read as a mechanical pulse.
#
# Enemies are slightly lower-pitched and quieter than the player so
# horde fights don't blur into a single wash and offscreen incoming
# fire telegraphs before you see the source. The original
# differentiation was 0.78-0.92 + -6 dB which changed the weapon's
# timbre — enemy fire sounded like "wrong" effects rather than the
# same weapon. The current numbers overlap the player range at the
# top end (0.96) so the same gun still reads as the same gun.
const PLAYER_PITCH_RANGE := Vector2(0.96, 1.04)
const ENEMY_PITCH_RANGE := Vector2(0.90, 0.96)
const VOLUME_JITTER_DB := 1.5  # ± this many dB on top of the category offset
const ENEMY_ATTEN_DB := -2.0   # blanket cut so enemy fire sits behind player SFX

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
	&"rpg": &"rpg_2h",
	&"lmg": &"lmg_2h",
	&"accelerator": &"accelerator_2h",
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


## Start a looping hold sound using a reserved SFX pool player (same
## AudioStreamPlayer3D nodes that produce audible one-shots). The pool
## player is marked reserved so rapid fire sounds can't evict it.
## Returns the player (null when no hold loop registered) — caller stores
## it and passes to stop_channel_loop on release.
const CHANNEL_FADE_OUT := 0.35

func play_channel_loop(weapon_key: StringName, parent_node: Node3D) -> AudioStreamPlayer3D:
	var key := _resolve_key(weapon_key)
	if key == &"":
		return null
	var set: Dictionary = _sounds.get(key, {})
	var stream = set.get(&"hold_loop", null) as AudioStream
	if stream == null:
		return null
	# OGG files loop natively via import settings (loop=true). DO NOT
	# modify the stream resource at runtime — it's a shared cached object
	# and mutating it can break playback for all users of that resource.
	var is_enemy := _is_enemy_key(weapon_key)
	var pitch_range := ENEMY_PITCH_RANGE if is_enemy else PLAYER_PITCH_RANGE
	var pitch := randf_range(pitch_range.x, pitch_range.y)
	if is_enemy:
		return SFX.claim_reserved(stream, parent_node.global_position, 0.0, pitch)
	else:
		return SFX.claim_reserved_at_listener(stream, 0.0, pitch)


## Reposition a channel-loop player to follow its source. Called each
## frame by _tick_channel so the 3D sound tracks the wielder.
func update_channel_position(player: AudioStreamPlayer3D, pos: Vector3) -> void:
	if player != null and is_instance_valid(player):
		player.global_position = pos


## Stop a previously-claimed channel-loop player. Fades out then releases
## the reserved pool slot. Safe to call with null (no-op).
func stop_channel_loop(player: AudioStreamPlayer3D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var tw := player.create_tween()
	tw.tween_property(player, "volume_db", -40.0, CHANNEL_FADE_OUT)
	# instance_id capture — see HitFlash for the rationale. Binding
	# `player` into a Callable would fail with "Lambda capture freed"
	# if the audio pool reclaims the player before the fade finishes.
	var player_id: int = player.get_instance_id()
	tw.tween_callback(func() -> void:
		var p := instance_from_id(player_id) as AudioStreamPlayer3D
		if p != null:
			SFX.release_player(p)
	)


# ── Generic sounds (not weapon-specific) ────────────────────────────────────

var _generic: Dictionary = {}  # StringName → Array[AudioStream]

## Play a generic named sound (e.g. &"explosion", &"level_up", &"pickup").
## Register via register_generic(). Pass at_listener=true for player-
## originated sounds (footsteps) so movement doesn't shift volume.
func play_generic(sound_name: StringName, pos: Vector3, volume_db: float = 0.0, at_listener: bool = false) -> void:
	var pool: Array = _generic.get(sound_name, [])
	if pool.is_empty():
		return
	var stream: AudioStream = pool[randi() % pool.size()]
	if at_listener:
		SFX.play_at_listener(stream, volume_db)
	else:
		SFX.play_at(stream, pos, volume_db)


func register_generic(sound_name: StringName, streams: Array[AudioStream]) -> void:
	_generic[sound_name] = streams


## Play a random UI sound on the UI bus (non-positional).
## Usage: WeaponSounds.play_ui(&"ui_click")
func play_ui(sound_name: StringName, volume_db: float = 0.0) -> void:
	var pool: Array = _generic.get(sound_name, [])
	if pool.is_empty():
		return
	var stream: AudioStream = pool[randi() % pool.size()]
	SFX.play_ui(stream, volume_db)


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
	if is_enemy:
		SFX.play_at(stream, pos, db + vol_jitter + ENEMY_ATTEN_DB, pitch)
	else:
		# Player sounds play at the listener so isometric camera distance
		# doesn't shift volume or panning with movement.
		SFX.play_at_listener(stream, db + vol_jitter, pitch)


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# Register sound sets per archetype. `_streams()` filters out any path
	# whose .wav/.ogg / .import sidecar isn't present yet, so partially-
	# populated folders don't crash the autoload — missing files just
	# degrade to silence for that category.
	var _blade_swings := _streams([
		"res://resources/audio/sfx/weapons/blade_swing_01.wav",
		"res://resources/audio/sfx/weapons/blade_swing_02.wav",
		"res://resources/audio/sfx/weapons/blade_swing_03.wav",
		"res://resources/audio/sfx/weapons/blade_swing_04.wav",
	])
	_register(&"melee_1h", { fire = _blade_swings })
	_register(&"melee_2h", {
		fire = _streams([
			"res://resources/audio/sfx/weapons/sledge_hit_01.wav",
			"res://resources/audio/sfx/weapons/sledge_hit_02.wav",
			"res://resources/audio/sfx/weapons/sledge_hit_03.wav",
			"res://resources/audio/sfx/weapons/sledge_hit_04.wav",
		]),
	})
	var _reloads := _streams([
		"res://resources/audio/sfx/weapons/reload_01.wav",
		"res://resources/audio/sfx/weapons/reload_02.wav",
		"res://resources/audio/sfx/weapons/reload_03.wav",
		"res://resources/audio/sfx/weapons/reload_04.wav",
		"res://resources/audio/sfx/weapons/reload_05.wav",
		"res://resources/audio/sfx/weapons/reload_06.wav",
	])
	_register(&"ranged_1h", {
		fire = _streams([
			"res://resources/audio/sfx/weapons/laser_pistol_fire_01.wav",
			"res://resources/audio/sfx/weapons/laser_pistol_fire_02.wav",
			"res://resources/audio/sfx/weapons/laser_pistol_fire_03.wav",
			"res://resources/audio/sfx/weapons/laser_pistol_fire_04.wav",
			"res://resources/audio/sfx/weapons/laser_pistol_fire_05.wav",
		]),
		reload = _reloads,
	})
	_register(&"ranged_2h", {
		fire = _streams([
			"res://resources/audio/sfx/weapons/plasma_rifle_01.wav",
			"res://resources/audio/sfx/weapons/plasma_rifle_02.wav",
			"res://resources/audio/sfx/weapons/plasma_rifle_03.wav",
			"res://resources/audio/sfx/weapons/plasma_rifle_04.wav",
			"res://resources/audio/sfx/weapons/plasma_rifle_05.wav",
		]),
		reload = _reloads,
	})
	_register(&"smg_1h", {
		fire = _streams([
			"res://resources/audio/sfx/weapons/smg_fire_01.wav",
			"res://resources/audio/sfx/weapons/smg_fire_02.wav",
			"res://resources/audio/sfx/weapons/smg_fire_03.wav",
			"res://resources/audio/sfx/weapons/smg_fire_04.wav",
			"res://resources/audio/sfx/weapons/smg_fire_05.wav",
			"res://resources/audio/sfx/weapons/smg_fire_06.wav",
		]),
		reload = _reloads,
	})
	_register(&"sniper_2h", {
		fire = _streams([
			"res://resources/audio/sfx/weapons/sniper_fire_01.wav",
			"res://resources/audio/sfx/weapons/sniper_fire_02.wav",
			"res://resources/audio/sfx/weapons/sniper_fire_03.wav",
			"res://resources/audio/sfx/weapons/sniper_fire_04.wav",
			"res://resources/audio/sfx/weapons/sniper_fire_05.wav",
		]),
		reload = _reloads,
	})
	_register(&"shotgun_2h", {
		fire = _streams([
			"res://resources/audio/sfx/weapons/shotgun_fire_01.wav",
			"res://resources/audio/sfx/weapons/shotgun_fire_02.wav",
			"res://resources/audio/sfx/weapons/shotgun_fire_03.wav",
			"res://resources/audio/sfx/weapons/shotgun_fire_04.wav",
			"res://resources/audio/sfx/weapons/shotgun_fire_05.wav",
			"res://resources/audio/sfx/weapons/shotgun_fire_06.wav",
			"res://resources/audio/sfx/weapons/shotgun_fire_07.wav",
			"res://resources/audio/sfx/weapons/shotgun_fire_08.wav",
		]),
		reload = _reloads,
	})
	_register(&"rpg_2h", {
		fire = _streams([
			"res://resources/audio/sfx/weapons/rpg_fire_01.wav",
			"res://resources/audio/sfx/weapons/rpg_fire_02.wav",
			"res://resources/audio/sfx/weapons/rpg_fire_03.wav",
			"res://resources/audio/sfx/weapons/rpg_fire_04.wav",
		]),
		impact = _streams(["res://resources/audio/sfx/weapons/rpg-impact.wav"]),
		reload = _reloads,
	})
	_register(&"lmg_2h", {
		fire = _streams([
			"res://resources/audio/sfx/weapons/lmg_fire_01.wav",
			"res://resources/audio/sfx/weapons/lmg_fire_02.wav",
			"res://resources/audio/sfx/weapons/lmg_fire_03.wav",
			"res://resources/audio/sfx/weapons/lmg_fire_04.wav",
			"res://resources/audio/sfx/weapons/lmg_fire_05.wav",
			"res://resources/audio/sfx/weapons/lmg_fire_06.wav",
		]),
		reload = _reloads,
	})
	# Accelerator: same channel pattern as taser — punchy zap at engage
	# (clip_11) + continuous beam loop for the duration of the stream.
	# is_channel_weapon() returns true so per-tick fire is suppressed
	# in player_combat.resolve_skill_hit.
	_register(&"accelerator_2h", {
		fire = _streams(["res://resources/audio/sfx/weapons/energy-accelerator.wav"]),
		hold_loop = _load_one("res://resources/audio/sfx/weapons/energy-accelerator-hold.ogg"),
	})
	# Taser: per-attack zap on the fire array, continuous crackle on
	# hold_loop. is_channel_weapon() returns true for it, so callers
	# in the channel-tick path skip the per-tick play_fire and rely on
	# the hold loop + the channel-start zap.
	_register(&"taser_2h", {
		fire = _streams(["res://resources/audio/sfx/weapons/charged-arc-taser.wav"]),
		hold_loop = _load_one("res://resources/audio/sfx/weapons/charged-arc-taser-hold.ogg"),
	})

	# ── Footstep sounds ────────────────────────────────────────────────────
	# Keyed by floor material. Player's _detect_floor_type() returns
	# &"footstep_metal" (default) or &"footstep_grate" (when standing on
	# a floor in the &"floor_grate" group). Add more floor types here as
	# level themes expand (e.g. &"footstep_stone", &"footstep_dirt").
	# Flesh hit — quiet, subliminal layer that fires every time any weapon
	# damages any enemy. Volume is set at the call site (-15 dB in
	# prototype_enemy.gd) rather than baked into the samples so it can be
	# tuned without re-editing the wavs.
	register_generic(&"hit_flesh", _streams([
		"res://resources/audio/sfx/enemies/hit_flesh_01.wav",
		"res://resources/audio/sfx/enemies/hit_flesh_02.wav",
		"res://resources/audio/sfx/enemies/hit_flesh_03.wav",
		"res://resources/audio/sfx/enemies/hit_flesh_04.wav",
		"res://resources/audio/sfx/enemies/hit_flesh_05.wav",
	]))

	# Explosion — generic blast sound. Triggered from combat_visuals.spawn_explosion
	# for any grenade detonation or AoE projectile (RPG, charged plasma, etc).
	# Random pick per blast + per-play pitch jitter for natural variety. Pos
	# is the world impact point; play_at handles 3D attenuation from there.
	register_generic(&"explosion", _streams([
		"res://resources/audio/sfx/weapons/explosion_01.wav",
		"res://resources/audio/sfx/weapons/explosion_02.wav",
		"res://resources/audio/sfx/weapons/explosion_03.wav",
		"res://resources/audio/sfx/weapons/explosion_04.wav",
		"res://resources/audio/sfx/weapons/explosion_05.wav",
	]))

	register_generic(&"footstep_metal", _streams([
		"res://resources/audio/sfx/player/step_metal_01.wav",
		"res://resources/audio/sfx/player/step_metal_02.wav",
		"res://resources/audio/sfx/player/step_metal_03.wav",
		"res://resources/audio/sfx/player/step_metal_04.wav",
		"res://resources/audio/sfx/player/step_metal_05.wav",
		"res://resources/audio/sfx/player/step_metal_06.wav",
		"res://resources/audio/sfx/player/step_metal_07.wav",
		"res://resources/audio/sfx/player/step_metal_08.wav",
		"res://resources/audio/sfx/player/step_metal_09.wav",
		"res://resources/audio/sfx/player/step_metal_10.wav",
	]))
	register_generic(&"footstep_grate", _streams([
		"res://resources/audio/sfx/player/step_grate_01.wav",
		"res://resources/audio/sfx/player/step_grate_02.wav",
		"res://resources/audio/sfx/player/step_grate_03.wav",
		"res://resources/audio/sfx/player/step_grate_04.wav",
	]))

	# ── Player took damage (impact on flesh/armor) ─────────────────────────
	# Generic body-impact sound for "you got hit." Pairs with hit_grunt:
	# this is the impact thump on the player, hit_grunt is the vocal
	# response. play_generic at_listener=true in prototype_player.gd
	# so distance attenuation doesn't kill the feedback.
	register_generic(&"hit_player", _streams([
		"res://resources/audio/sfx/player/hit_player_01.wav",
		"res://resources/audio/sfx/player/hit_player_02.wav",
		"res://resources/audio/sfx/player/hit_player_03.wav",
		"res://resources/audio/sfx/player/hit_player_04.wav",
		"res://resources/audio/sfx/player/hit_player_05.wav",
	]))

	# ── Unarmed swing ─────────────────────────────────────────────────────
	# Bare-fist attack whoosh. prototype_player.gd _fire_unarmed fires this
	# at swing time; the per-archetype hit_flesh sample lands the impact.
	register_generic(&"unarmed_swing", _streams([
		"res://resources/audio/sfx/weapons/unarmed_swing_01.wav",
		"res://resources/audio/sfx/weapons/unarmed_swing_02.wav",
		"res://resources/audio/sfx/weapons/unarmed_swing_03.wav",
		"res://resources/audio/sfx/weapons/unarmed_swing_04.wav",
		"res://resources/audio/sfx/weapons/unarmed_swing_05.wav",
	]))

	# ── Enemy death ────────────────────────────────────────────────────────
	# Killing-blow sting fired from prototype_enemy._die at the corpse
	# position. Distinct from hit_flesh (every hit) so kills feel weightier
	# than chip-damage swings.
	register_generic(&"enemy_death", _streams([
		"res://resources/audio/sfx/enemies/enemy_death_01.wav",
		"res://resources/audio/sfx/enemies/enemy_death_02.wav",
		"res://resources/audio/sfx/enemies/enemy_death_03.wav",
		"res://resources/audio/sfx/enemies/enemy_death_04.wav",
		"res://resources/audio/sfx/enemies/enemy_death_05.wav",
		"res://resources/audio/sfx/enemies/enemy_death_06.wav",
		"res://resources/audio/sfx/enemies/enemy_death_07.wav",
		"res://resources/audio/sfx/enemies/enemy_death_08.wav",
		"res://resources/audio/sfx/enemies/enemy_death_09.wav",
	]))

	# ── Doors and switches ────────────────────────────────────────────────
	# Single-sample environmental clicks. PrototypeDoor open/close and
	# PrototypeSwitch.interact fire these at the node's position so the
	# 3D attenuation telegraphs which door/switch the player just used.
	register_generic(&"door_open", _streams([
		"res://resources/audio/sfx/world/door_open.wav",
	]))
	register_generic(&"door_close", _streams([
		"res://resources/audio/sfx/world/door_close.wav",
	]))
	register_generic(&"switch_click", _streams([
		"res://resources/audio/sfx/world/switch_click.wav",
	]))
	# Loot crate / chest open — single sample fired from _open_visual so it
	# plays on both the local opener AND every peer that receives the
	# _client_open_visual RPC (since the visual path runs on both sides).
	register_generic(&"chest_open", _streams([
		"res://resources/audio/sfx/world/chest_open.wav",
	]))

	# ── IED placement and detonation ──────────────────────────────────────
	# Placement: short electronic beep/click when the trap arms at the
	# thrown position. Detonation: layered on top of the generic explosion
	# sound by prototype_trap._detonate to give the IED a distinct
	# digital-blast signature versus a grenade or RPG impact.
	register_generic(&"ied_place", _streams([
		"res://resources/audio/sfx/world/ied_place_01.wav",
		"res://resources/audio/sfx/world/ied_place_02.wav",
		"res://resources/audio/sfx/world/ied_place_03.wav",
	]))
	register_generic(&"ied_detonate", _streams([
		"res://resources/audio/sfx/weapons/ied_detonate_01.wav",
		"res://resources/audio/sfx/weapons/ied_detonate_02.wav",
		"res://resources/audio/sfx/weapons/ied_detonate_03.wav",
		"res://resources/audio/sfx/weapons/ied_detonate_04.wav",
	]))

	# ── Shield (offhand) ──────────────────────────────────────────────────
	# Raise plays on activation, hit plays each time damage is absorbed
	# (multi-sample pool prevents repetitive sustained-fire blocks from
	# sounding identical), break plays when the pool depletes.
	register_generic(&"shield_raise", _streams([
		"res://resources/audio/sfx/weapons/shield_raise.wav",
	]))
	register_generic(&"shield_hit", _streams([
		"res://resources/audio/sfx/weapons/shield_hit_01.wav",
		"res://resources/audio/sfx/weapons/shield_hit_02.wav",
	]))
	register_generic(&"shield_break", _streams([
		"res://resources/audio/sfx/weapons/shield_break.wav",
	]))

	# ── Player hit grunts ─────────────────────────────────────────────────
	# Played at listener when the player takes damage. Random selection
	# from the pool so repeated hits don't sound identical.
	register_generic(&"hit_grunt", _streams([
		"res://resources/audio/sfx/player/hit_grunt_01.wav",
		"res://resources/audio/sfx/player/hit_grunt_02.wav",
		"res://resources/audio/sfx/player/hit_grunt_03.wav",
		"res://resources/audio/sfx/player/hit_grunt_04.wav",
		"res://resources/audio/sfx/player/hit_grunt_05.wav",
		"res://resources/audio/sfx/player/hit_grunt_06.wav",
		"res://resources/audio/sfx/player/hit_grunt_07.wav",
		"res://resources/audio/sfx/player/hit_grunt_08.wav",
		"res://resources/audio/sfx/player/hit_grunt_09.wav",
		"res://resources/audio/sfx/player/hit_grunt_10.wav",
	]))

	# ── UI sounds ──────────────────────────────────────────────────────────
	# Played via SFX.play_ui() on the UI bus. Each category has a small
	# pool for random selection so menus don't sound robotic.
	register_generic(&"ui_click", _streams([
		"res://resources/audio/sfx/ui/ui_click_01.wav",
		"res://resources/audio/sfx/ui/ui_click_02.wav",
		"res://resources/audio/sfx/ui/ui_click_03.wav",
	]))
	register_generic(&"ui_hover", _streams([
		"res://resources/audio/sfx/ui/ui_hover_01.wav",
		"res://resources/audio/sfx/ui/ui_hover_02.wav",
		"res://resources/audio/sfx/ui/ui_hover_03.wav",
	]))
	register_generic(&"ui_confirm", _streams([
		"res://resources/audio/sfx/ui/ui_confirm_01.wav",
		"res://resources/audio/sfx/ui/ui_confirm_02.wav",
	]))
	register_generic(&"ui_back", _streams([
		"res://resources/audio/sfx/ui/ui_back_01.wav",
		"res://resources/audio/sfx/ui/ui_back_02.wav",
	]))
	register_generic(&"ui_navigate", _streams([
		"res://resources/audio/sfx/ui/ui_navigate_01.wav",
		"res://resources/audio/sfx/ui/ui_navigate_02.wav",
		"res://resources/audio/sfx/ui/ui_navigate_03.wav",
		"res://resources/audio/sfx/ui/ui_navigate_04.wav",
	]))
	register_generic(&"ui_open", _streams([
		"res://resources/audio/sfx/ui/ui_open_01.wav",
	]))


# Load a single AudioStream by path, null if missing. For hold_loop where
# we need a single stream (not an array of random alternates).
func _load_one(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("[WeaponSounds] _load_one: resource doesn't exist at ", path)
		return null
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("[WeaponSounds] _load_one: loaded null for ", path)
	return stream


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
