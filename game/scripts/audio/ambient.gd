extends Node

## Ambient zone audio autoload. Plays a looping atmosphere track on the
## Ambient bus alongside the Music bus's BGM — think distant machine hum,
## ventilation rumble, far-off industrial chatter. Distinct from music:
##   - Loops natively (no silent gap between repeats); ambience that goes
##     quiet for 30s reads as a bug, not a breath.
##   - Routes through the Ambient bus so it can be balanced (or muted)
##     independently of music in the settings panel.
##   - Single track at a time. Crossfades cleanly on play_track() so
##     floor transitions don't cut the room out from under the player.
##
## Usage:
##   Ambient.play_floor_track(PlayerState.new_game_plus)
##   Ambient.play_track("res://resources/audio/ambient/foo.ogg")
##   Ambient.stop()
##
## Silent until assets are dropped into res://resources/audio/ambient/ —
## play_track warns and skips when the file is missing.

const FADE_IN := 5.0
const FADE_OUT := 3.0
const SILENT_DB := -60.0
const AMBIENT_BUS := &"Ambient"
## Target play volume in dB. Ambient is meant to be a bed under the music
## and SFX — "barely there" rather than competing for attention. -24 dB
## puts it ~16× quieter than 0 dB. The Ambient bus volume in the settings
## panel scales this further, so the user can still mute or boost it.
const AMBIENT_TARGET_DB := -24.0

## Floor BGM-style rotation. play_floor_track(index) picks
## index % FLOOR_TRACKS.size() so callers can pass NG+ count, floor
## number, etc., and the cycle wraps automatically. Add more entries
## here as additional ambience tracks land.
const FLOOR_TRACKS: Array[String] = [
	"res://resources/audio/ambient/floor_01.ogg",
	"res://resources/audio/ambient/floor_02.ogg",
	"res://resources/audio/ambient/floor_03.ogg",
]

var _player: AudioStreamPlayer
var _tween: Tween
# Path currently playing — used to no-op re-entry of the same track so
# scene transitions with the same ambience don't restart from silence.
var _current_path: String = ""


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = AMBIENT_BUS
	_player.volume_db = SILENT_DB
	add_child(_player)


## Crossfade to `path`. Looping is forced on the stream so the track
## restarts seamlessly. No-op when the requested track is already
## playing (re-entering the same scene shouldn't blip the audio).
func play_track(path: String) -> void:
	if not ResourceLoader.exists(path):
		# Missing file — warn once and skip. Matches Music.play_track so
		# iterating by dropping new files in stays frictionless.
		push_warning("[Ambient] missing track: %s" % path)
		return
	if _current_path == path and _player.playing:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	# Native loop — we want continuous ambience, not the Music autoload's
	# gap-then-replay pattern.
	if "loop" in stream:
		stream.loop = true
	_current_path = path
	_player.stream = stream
	# Start from silence regardless of where the previous fade left us so
	# the fade-in always reads as a deliberate ease-in, not a jump-cut.
	_player.volume_db = SILENT_DB
	_player.play()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", AMBIENT_TARGET_DB, FADE_IN)


## Picks a track from FLOOR_TRACKS based on the supplied index, modulo
## the pool size. Mirrors Music.play_level_track so callers can pass
## the same NG+ counter and both layers rotate together.
func play_floor_track(index: int = 0) -> void:
	if FLOOR_TRACKS.is_empty():
		return
	var path := FLOOR_TRACKS[index % FLOOR_TRACKS.size()]
	play_track(path)


## Fade to silence and stop. Use on main menu, death screen, or any
## moment where music carries the scene alone.
func stop(fade: float = FADE_OUT) -> void:
	_current_path = ""
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", SILENT_DB, fade)
	_tween.tween_callback(_player.stop)
