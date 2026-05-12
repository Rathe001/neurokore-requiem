extends Node
## Background music autoload. Routes through the Music bus and crossfades
## between tracks so scene transitions don't cut audio. Two-player swap
## pattern: `_active` is what's audible, `_next` is staged for the next
## track and faded up while `_active` fades down.
##
## Tracks DO NOT loop natively — we set `stream.loop = false` and listen
## for the `finished` signal, then wait LOOP_GAP_SEC of silence before
## restarting. Gives the player a breather between repeats and avoids the
## "same 2 minutes on repeat for an hour" mood-killer.
##
## Usage:
##   Music.play_track("res://resources/audio/music/level1.mp3")
##   Music.play_level_track(PlayerState.new_game_plus)
##   Music.stop()

const FADE_TIME := 1.5
const SILENT_DB := -60.0
const LOOP_GAP_SEC := 30.0
const MUSIC_BUS := &"Music"

## Level BGM rotation. play_level_track(index) picks index % LEVEL_TRACKS.size()
## so any caller can pass a monotonically-increasing sequence (level number,
## NG+ count, etc.) and the cycle wraps automatically.
const LEVEL_TRACKS: Array[String] = [
	"res://resources/audio/music/level1.mp3",
	"res://resources/audio/music/level2.mp3",
	"res://resources/audio/music/level3.mp3",
	"res://resources/audio/music/level4.mp3",
	"res://resources/audio/music/level5.mp3",
]

var _active: AudioStreamPlayer
var _next: AudioStreamPlayer
var _tween: Tween
# Path of the currently-playing track, captured so the loop-gap timer
# knows what to replay. Empty when nothing is playing or stop() was called.
var _loop_path: String = ""
var _loop_timer: Timer


func _ready() -> void:
	_active = _make_player()
	_next = _make_player()
	_loop_timer = Timer.new()
	_loop_timer.one_shot = true
	_loop_timer.wait_time = LOOP_GAP_SEC
	_loop_timer.timeout.connect(_on_loop_timer)
	add_child(_loop_timer)


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
func play_track(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("[Music] missing track: %s" % path)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if _active.stream == stream and _active.playing:
		return
	# We manage looping manually via finished + timer so we can insert a
	# silent gap; disable the stream's own loop flag so playback stops
	# naturally at end-of-file and triggers `finished`.
	if "loop" in stream:
		stream.loop = false
	_loop_path = path
	_cancel_loop_timer()
	_next.stream = stream
	_next.volume_db = SILENT_DB
	_next.play()
	_start_crossfade()


## Cycle helper for level BGM. `index` is treated as a monotonic counter
## (level number, NG+ count, etc.) and wraps modulo the track count.
func play_level_track(index: int) -> void:
	if LEVEL_TRACKS.is_empty():
		return
	var i: int = posmod(index, LEVEL_TRACKS.size())
	play_track(LEVEL_TRACKS[i])


## Fade out and stop. Use for moments where silence reads better than a
## crossfade (e.g. death sting). The next play_track will pick up from
## a silent state and fade up cleanly.
func stop(fade: float = FADE_TIME) -> void:
	_loop_path = ""
	_cancel_loop_timer()
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
	# Connect finished on the new active player. CONNECT_ONE_SHOT so it
	# auto-disconnects after firing (the next play_track will reconnect
	# fresh, the next stop()/manual-replay handles the rest).
	if _active.finished.is_connected(_on_track_finished):
		_active.finished.disconnect(_on_track_finished)
	_active.finished.connect(_on_track_finished, CONNECT_ONE_SHOT)


# Track played all the way through. Start the silent-gap timer; on its
# timeout we re-stage the same track for another play.
func _on_track_finished() -> void:
	if _loop_path.is_empty():
		return
	_loop_timer.start()


func _on_loop_timer() -> void:
	if _loop_path.is_empty():
		return
	# Re-play the captured path. play_track stages on _next and crossfades
	# from the (silent) _active so the entrance fades up smoothly rather
	# than starting at full volume.
	var path := _loop_path
	# Clear the no-op guard so play_track doesn't skip on "same stream
	# already active" — the active player is stopped at this point but
	# its `stream` reference still matches.
	_loop_path = ""
	play_track(path)


func _cancel_loop_timer() -> void:
	if _loop_timer != null and not _loop_timer.is_stopped():
		_loop_timer.stop()
