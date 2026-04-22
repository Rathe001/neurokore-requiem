extends Resource
class_name LevelTheme

@export var wall_height: float = 4.5
@export var wall_thickness: float = 0.4
@export var wall_shader: Shader
@export var floor_shader: Shader

@export_group("Wall Material")
@export var wall_color: Color = Color(0.2, 0.21, 0.24, 1)
@export var wall_metallic: float = 0.3
@export var wall_roughness: float = 0.6

@export_group("Floor Material")
@export var floor_color: Color = Color(0.25, 0.26, 0.28, 1)
@export var floor_metallic: float = 0.2
@export var floor_roughness: float = 0.7

@export_group("FPS Fog")
@export var fps_fog_density: float = 0.35
@export var fps_fog_color: Color = Color(0.002, 0.003, 0.006)

@export_group("Fluorescent Geometry")
@export var fluorescent_housing_size: Vector3 = Vector3(1.2, 0.06, 0.2)
@export var fluorescent_tube_size: Vector3 = Vector3(1.1, 0.02, 0.08)
@export var fluorescent_housing_color: Color = Color(0.12, 0.12, 0.13, 1)
@export var fluorescent_housing_metallic: float = 0.5
@export var fluorescent_housing_roughness: float = 0.5
@export var fluorescent_emission_multiplier: float = 4.0
