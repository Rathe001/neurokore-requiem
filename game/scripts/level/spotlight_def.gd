extends Resource
class_name SpotlightDef

@export var offset: Vector3 = Vector3(0, 4.0, 0)
@export var rotation_degrees: Vector3 = Vector3(-90, 0, 0)
@export var color: Color = Color.WHITE
@export var energy: float = 16.0
@export var light_range: float = 10.0
@export var angle: float = 30.0
@export var angle_attenuation: float = 0.15
@export var attenuation: float = 0.6
@export var shadows: bool = true

@export_group("Sweep Animation")
## Total sweep arc in degrees. 0 = no animation.
@export var sweep_arc: float = 0.0
## Degrees per second of sweep rotation.
@export var sweep_speed: float = 30.0
## Pause in seconds at each end of the sweep.
@export var sweep_pause: float = 0.5
