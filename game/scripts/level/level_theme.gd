extends Resource
class_name LevelTheme

@export var wall_height: float = 4.5
@export var wall_thickness: float = 0.4

# PBR materials applied to walls and floors. Imported from Blenderkit via
# tools/import_blenderkit_material.py. The _alt slots are used for corridor
# pieces so corridors can read as a different space from rooms; null falls
# back to the primary material (corridors look like rooms).
@export var wall_material: Material
@export var floor_material: Material
@export var wall_material_alt: Material
@export var floor_material_alt: Material

@export_group("FPS Fog")
@export var fps_fog_density: float = 0.35
@export var fps_fog_color: Color = Color(0.002, 0.003, 0.006)

@export_group("Pit")
@export var pit_depth: float = 5.0
@export var pit_ooze_color: Color = Color(0.15, 0.85, 0.2, 1.0)
@export var pit_ooze_energy: float = 2.5

@export_group("Fluorescent Geometry")
@export var fluorescent_housing_size: Vector3 = Vector3(1.2, 0.06, 0.2)
@export var fluorescent_tube_size: Vector3 = Vector3(1.1, 0.02, 0.08)
@export var fluorescent_housing_color: Color = Color(0.12, 0.12, 0.13, 1)
@export var fluorescent_housing_metallic: float = 0.5
@export var fluorescent_housing_roughness: float = 0.5
@export var fluorescent_emission_multiplier: float = 4.0
