extends Node
## Fire-and-forget positional audio helper. Pools AudioStreamPlayer3D nodes so
## callers never allocate — just `SFX.play_at(stream, pos)`.

const POOL_SIZE := 16
const DEFAULT_BUS := &"SFX"

var _pool: Array[AudioStreamPlayer3D] = []
var _idx: int = 0
var _ui_player: AudioStreamPlayer


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = DEFAULT_BUS
		p.max_distance = 30.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)


## Play a sound at a world position. Returns the player so the caller can
## tweak pitch_scale / volume_db after the fact if needed.
func play_at(stream: AudioStream, pos: Vector3, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var player := _pool[_idx]
	_idx = (_idx + 1) % POOL_SIZE
	player.stream = stream
	player.global_position = pos
	player.volume_db = volume_db
	player.play()
	return player


## Non-positional shortcut for UI sounds (menu clicks, notifications, etc.).
func play_ui(stream: AudioStream, volume_db: float = 0.0) -> void:
	if _ui_player == null:
		_ui_player = AudioStreamPlayer.new()
		_ui_player.bus = &"UI"
		add_child(_ui_player)
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()
