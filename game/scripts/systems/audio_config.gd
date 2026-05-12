extends Resource
class_name AudioConfig

## Persisted volume preferences. Per-bus linear values in [0, 1]; AudioState
## converts to dB on apply. Defaults are moderate so first-launch isn't
## ear-shredding before the player finds the settings menu.

@export_range(0.0, 1.0) var music_volume: float = 0.5
@export_range(0.0, 1.0) var sfx_volume: float = 0.85
@export_range(0.0, 1.0) var ambient_volume: float = 0.7
