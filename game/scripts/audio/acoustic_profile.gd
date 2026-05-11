extends Resource
class_name AcousticProfile
## Per-zone reverb parameters. Attach to RoomDef / CorridorDef to hand-tune a
## room's acoustic character, or leave null and RoomAcoustics will auto-derive
## from the room's floor area via from_area().

@export_range(0.0, 1.0) var room_size: float = 0.5
@export_range(0.0, 1.0) var damping: float = 0.5
@export_range(0.0, 1.0) var spread: float = 0.5
@export_range(0.0, 1.0) var wet: float = 0.3
@export_range(0.0, 1.0) var dry: float = 0.7
@export_range(0.0, 500.0) var pre_delay_ms: float = 20.0


## Auto-derive from room area (m²). Logarithmic mapping:
## small rooms (~16 m²) → tight, absorbed reverb
## large rooms (~200 m²+) → echoey, cathedral-like
static func from_area(area: float) -> AcousticProfile:
	var p := AcousticProfile.new()
	# t ∈ [0, 1]: 0 = smallest reference room, 1 = largest
	var t := clampf(log(area / 16.0) / log(200.0 / 16.0), 0.0, 1.0)
	p.room_size = lerpf(0.1, 0.85, t)
	p.damping = lerpf(0.8, 0.3, t)       # small rooms absorb more
	p.spread = lerpf(0.2, 0.8, t)
	p.wet = lerpf(0.15, 0.45, t)
	p.dry = lerpf(0.85, 0.55, t)
	p.pre_delay_ms = lerpf(5.0, 40.0, t)
	return p
