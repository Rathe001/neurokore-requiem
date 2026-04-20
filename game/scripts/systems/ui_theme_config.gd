class_name UIThemeConfig
extends Resource

# Semantic palette for a class/spec. UIThemeState picks one based on
# PlayerState and assembles a Godot Theme from it. When adding a new
# field, also update _build_theme in ui_theme_state.gd if the color
# should flow into default widget styling.

@export_group("Core")
@export var accent: Color = Color(0.3, 0.7, 1.0)
@export var accent_dim: Color = Color(0.25, 0.45, 0.7)

@export_group("Panels")
@export var panel_bg: Color = Color(0.04, 0.05, 0.08, 0.92)
@export var panel_border: Color = Color(0.3, 0.5, 0.7, 0.9)

@export_group("Text")
@export var text: Color = Color(0.82, 0.9, 1.0)
@export var text_dim: Color = Color(0.55, 0.65, 0.8)

@export_group("HP")
@export var hp_full: Color = Color(0.3, 0.95, 1.0)
@export var hp_low: Color = Color(1.0, 0.25, 0.3)
@export var hp_bar_bg: Color = Color(0.04, 0.05, 0.08, 0.9)
@export var hp_bar_border: Color = Color(0.3, 0.5, 0.7, 0.7)

@export_group("Slots")
@export var slot_bg: Color = Color(0.08, 0.08, 0.1, 1.0)
@export var slot_border: Color = Color(0.35, 0.4, 0.5, 1.0)

@export_group("Credits")
@export var credits: Color = Color(1.0, 0.85, 0.25)

@export_group("Player")
@export var player_color: Color = Color(0.75, 0.78, 0.85)

@export_group("Frames")
# Optional textured frames. When set, they replace the flat ColorRect/
# ReferenceRect borders used by the default look. Configured via the
# Godot editor's region rect tool on the AtlasTexture resources.
@export var hp_bar_frame: Texture2D
@export var resource_bar_frame: Texture2D
@export var slot_frame: Texture2D
@export var frame_patch_margin: int = 20

@export_group("Fonts")
@export var base_font_size: int = 13
