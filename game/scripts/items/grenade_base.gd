class_name GrenadeBase extends Resource

## Defines a grenade archetype (e.g. "Frag", "Incendiary"). Per-stat rolls
## happen at item generation: each *_range field is (min, max) for the rolled
## instance value. Parallel to WeaponBase but with grenade-specific fields.

@export var id: StringName = &""
@export var display_name: String = ""
@export var glyph: String = "◉"

@export var damage_min_range: Vector2 = Vector2(8, 14)
@export var damage_max_range: Vector2 = Vector2(18, 28)
@export var blast_radius_range: Vector2 = Vector2(2.5, 4.0)
@export var crit_chance_range: Vector2 = Vector2(0.05, 0.10)

@export var fire_skill: Skill
