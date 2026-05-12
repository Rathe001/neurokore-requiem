extends Node

# Owns per-bus volume preferences. Loads AudioConfig from user://audio.tres
# at boot and applies to the Music / SFX / Ambient AudioServer buses; the
# settings UI mutates the config via set_*_volume helpers, which apply +
# save in one step.
#
# Mirrors the DisplayState pattern (config resource + apply/save/changed
# signal) so the settings panel can hook both with the same shape.

signal changed

const SAVE_PATH := "user://audio.tres"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const AMBIENT_BUS := &"Ambient"
# Music slider value gets multiplied by this before linear_to_db, so the
# slider's whole 0..1 range maps to a much quieter window than the other
# buses. With 0.10 scale, slider 50% = effective linear 0.05 = -26 dB
# (which playtesting found is where music feels ambient rather than
# competing with combat audio). 100% on the slider = effective 0.10 =
# -20 dB, the realistic loud-end ceiling for BGM.
const MUSIC_VOLUME_SCALE: float = 0.10

var config: AudioConfig


func _ready() -> void:
	config = _load_config()
	apply()


func set_music_volume(v: float) -> void:
	if config == null:
		return
	v = clampf(v, 0.0, 1.0)
	if is_equal_approx(config.music_volume, v):
		return
	config.music_volume = v
	_apply_bus(MUSIC_BUS, v)
	changed.emit()
	save()


func set_sfx_volume(v: float) -> void:
	if config == null:
		return
	v = clampf(v, 0.0, 1.0)
	if is_equal_approx(config.sfx_volume, v):
		return
	config.sfx_volume = v
	_apply_bus(SFX_BUS, v)
	changed.emit()
	save()


func set_ambient_volume(v: float) -> void:
	if config == null:
		return
	v = clampf(v, 0.0, 1.0)
	if is_equal_approx(config.ambient_volume, v):
		return
	config.ambient_volume = v
	_apply_bus(AMBIENT_BUS, v)
	changed.emit()
	save()


# Push the current config to AudioServer. Called at boot and as a fallback
# for code that wants to refresh state (e.g. settings UI re-binding).
func apply() -> void:
	if config == null:
		return
	_apply_bus(MUSIC_BUS, config.music_volume)
	_apply_bus(SFX_BUS, config.sfx_volume)
	_apply_bus(AMBIENT_BUS, config.ambient_volume)
	changed.emit()


# Convert linear [0,1] → dB and apply to a bus. linear_to_db(0) returns
# -inf which Godot handles, but muting the bus avoids per-sample work
# on a permanently-silent bus. Bus muted exactly at 0, unmuted otherwise.
#
# Music gets pre-scaled by MUSIC_VOLUME_SCALE so the slider's 0..1 range
# maps to a quieter effective window than the other buses — BGM should
# sit under combat audio, not compete with it.
func _apply_bus(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		push_warning("[AudioState] bus '%s' not found" % bus_name)
		return
	if linear <= 0.0:
		AudioServer.set_bus_mute(idx, true)
		return
	AudioServer.set_bus_mute(idx, false)
	var effective: float = linear * MUSIC_VOLUME_SCALE if bus_name == MUSIC_BUS else linear
	AudioServer.set_bus_volume_db(idx, linear_to_db(effective))


func save() -> void:
	if config == null:
		return
	var err := ResourceSaver.save(config, SAVE_PATH)
	if err != OK:
		push_warning("[AudioState] failed to save: %d" % err)


func _load_config() -> AudioConfig:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded := load(SAVE_PATH) as AudioConfig
		if loaded != null:
			return loaded
	return AudioConfig.new()
