extends Resource
class_name LevelTheme

@export var wall_height: float = 3.0
@export var wall_thickness: float = 0.4

# Kit-bash models. When wall_model / floor_model are set the level builder
# instances these 3D models in a grid instead of using procedural geometry
# + PBR materials. Each model is assumed to be sized exactly wall_grid_size
# (or floor_grid_size) so they tile seam-to-seam. Rooms get their size
# quantized to multiples of the grid at build time.
#
# When wall_model is null, falls back to the procedural SurfaceTool wall
# mesh + StandardMaterial3D (wall_material). Same for floor_model.
@export var wall_model: PackedScene
@export var floor_model: PackedScene
@export var wall_grid_size: float = 4.0
@export var floor_grid_size: float = 4.0
# Native dimensions of the source models (before any kit-bash scaling).
# These fields are informational — the builders read the mesh AABB at
# runtime and auto-detect which axis is height vs thickness.
# - floor_model_native_size: XZ footprint of the floor tile.
# The builders scale each instance so it fills wall_grid_size × wall_height
# (walls) or floor_grid_size × floor_grid_size (floors).
@export var wall_model_native_width: float = 2.0
@export var wall_model_native_height: float = 2.0
@export var floor_model_native_size: Vector2 = Vector2(2.0, 2.0)

# PBR materials applied to walls and floors when no kit model is set.
# Imported from Blenderkit via tools/import_blenderkit_material.py. The
# _alt slots are used for corridor pieces so corridors can read as a
# different space from rooms; null falls back to the primary material.
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
