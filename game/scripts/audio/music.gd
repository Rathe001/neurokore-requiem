extends Node
## Background music autoload. Routes through the Music bus and crossfades
## between tracks so scene transitions don't cut audio. Two-player swap
## pattern: `_active` is what's audible, `_next` is staged for the next
## track and faded up while `_active` fades down.
##
## Usage:
##   Music.play_track("res://resources/audio/music/level1.mp3")
##   Music.stop()                  # fade out + stop
##   Music.play_track(...)         # crossfade to new track; no-op if same

const FADE_TIME := 1.5
const SILENT_DB := -60.0
const MUSIC_BUS := &"Music"

var _active: AudioStreamPlayer
var _next: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	_active = _make_player()
	_next = _make_player()


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = MUSIC_BUS
	p.volume_db = SILENT_DB
	add_child(p)
	return p


## Start (or cross-fade to) a music track. `path` is res://-relative.
## No-op when the track is already active so re-entering a scene with the
## same BGM doesn't restart playback. Missing files warn and skip rather
## than crashing — keeps the iterate-by-dropping-files loop frictionless.
func play_track(path: String, looped: bool = true) -> void:
	if not ResourceLoader.exists(path):
		push_warning("[Music] missing track: %s" % path)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if _active.stream == stream and _active.playing:
		return
	# MP3 and Ogg both expose a `loop` property; setting it once on the
	# stream resource is sufficient because the players just play whatever
	# the stream itself says.
	if "loop" in stream:
		stream.loop = looped
	_next.stream = stream
	_next.volume_db = SILENT_DB
	_next.play()
	_start_crossfade()


## Fade out and stop. Use for moments where silence reads better than a
## crossfade (e.g. death sting). The next play_track will pick up from
## a silent state and fade up cleanly.
func stop(fade: float = FADE_TIME) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_active, "volume_db", SILENT_DB, fade)
	_tween.tween_callback(_active.stop)


func _start_crossfade() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_active, "volume_db", SILENT_DB, FADE_TIME)
	_tween.tween_property(_next, "volume_db", 0.0, FADE_TIME)
	# Sequential phase after the parallel fade — stop the now-silent old
	# player and swap references so `_active` always points at audio.
	_tween.chain().tween_callback(_finish_crossfade)


func _finish_crossfade() -> void:
	_active.stop()
	var tmp := _active
	_active = _next
	_next = tmp
