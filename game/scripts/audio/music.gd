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
## Level BGM uses a long, deliberate fade-in to ease the player back into the
## space after the silent gap (or when first entering a level). Independent
## of the user's Music volume setting — that's applied at the bus level by
## AudioState, so this player-level fade composes cleanly on top.
const LEVEL_FADE_IN_SEC := 15.0

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
# Fade-in duration captured alongside _loop_path so the post-gap replay
# eases up at the same rate as the original entrance (level tracks use a
# 15s fade; title/menu uses the standard 1.5s).
var _loop_fade_in_sec: float = FADE_TIME
var _loop_timer: Timer
# Shuffled level playlist — filled by play_level_track(), advanced by
# _on_loop_timer(). Empty when playing non-level music (title screen).
var _level_queue: Array[String] = []
var _level_queue_idx: int = 0


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
## `fade_in_sec` controls how long the new track takes to reach full
## volume — defaults to a snappy 1.5s for menus / transitions; level
## music passes LEVEL_FADE_IN_SEC for a slow build. Outgoing track
## always fades down at FADE_TIME regardless, so a crossfade between
## two long-fade tracks doesn't leave both audible simultaneously.
##
## No-op when the track is already active so re-entering a scene with
## the same BGM doesn't restart playback. Missing files warn and skip
## rather than crashing — keeps the iterate-by-dropping-files loop
## frictionless.
func play_track(path: String, fade_in_sec: float = FADE_TIME) -> void:
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
	_loop_fade_in_sec = fade_in_sec
	_cancel_loop_timer()
	_next.stream = stream
	_next.volume_db = SILENT_DB
	_next.play()
	_start_crossfade(fade_in_sec)


## Shuffle-play all level tracks. Builds a randomised playlist from
## LEVEL_TRACKS and starts the first one; when each track finishes the
## loop-gap timer advances to the next in the shuffle. Once the queue
## is exhausted it re-shuffles so you never hear the same order twice
## in a row.
func play_level_track(_index: int = 0) -> void:
	if LEVEL_TRACKS.is_empty():
		return
	_build_level_queue()
	play_track(_level_queue[0], LEVEL_FADE_IN_SEC)


## Fade out and stop. Use for moments where silence reads better than a
## crossfade (e.g. death sting). The next play_track will pick up from
## a silent state and fade up cleanly.
func stop(fade: float = FADE_TIME) -> void:
	_loop_path = ""
	_level_queue.clear()
	_cancel_loop_timer()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_active, "volume_db", SILENT_DB, fade)
	_tween.tween_callback(_active.stop)


func _start_crossfade(fade_in_sec: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	# Outgoing track always fades quickly — no benefit to dragging the
	# previous BGM out over 15s when the new one is the focus.
	_tween.tween_property(_active, "volume_db", SILENT_DB, FADE_TIME)
	_tween.tween_property(_next, "volume_db", 0.0, fade_in_sec)
	# Barrier waits for the LATER of the two parallel tweens (fade_in_sec
	# is typically longer), then the sequential callback swaps players.
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
	# Level playlist: advance to the next shuffled track. When the queue
	# is exhausted, re-shuffle so the rotation never repeats the same
	# order back-to-back.
	var next_path: String
	var next_fade: float = _loop_fade_in_sec
	if not _level_queue.is_empty():
		_level_queue_idx += 1
		if _level_queue_idx >= _level_queue.size():
			_build_level_queue()
		next_path = _level_queue[_level_queue_idx]
	else:
		# Non-level track: replay the same path (title screen, etc.).
		next_path = _loop_path
	# Clear the no-op guard so play_track doesn't skip on "same stream
	# already active" — the active player is stopped at this point but
	# its `stream` reference still matches.
	_loop_path = ""
	play_track(next_path, next_fade)


func _cancel_loop_timer() -> void:
	if _loop_timer != null and not _loop_timer.is_stopped():
		_loop_timer.stop()


## Build a fresh shuffled copy of LEVEL_TRACKS and reset the index.
func _build_level_queue() -> void:
	_level_queue = LEVEL_TRACKS.duplicate()
	# Fisher-Yates shuffle.
	for i in range(_level_queue.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp := _level_queue[i]
		_level_queue[i] = _level_queue[j]
		_level_queue[j] = tmp
	_level_queue_idx = 0
