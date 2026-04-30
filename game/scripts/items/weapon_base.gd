class_name WeaponBase extends Resource

# Defines a weapon archetype (e.g. "Combat Knife", "Sledgehammer"). Per-stat
# rolls happen at item generation: each *_range field is (min, max) for the
# rolled instance value. The Item carries the rolled values; combat reads from
# the Item, not from the WeaponBase.

@export var id: StringName = &""
@export var display_name: String = ""
@export var glyph: String = "/"
@export var two_handed: bool = false

# Damage ranges. Each item rolls a damage_min in [damage_min_range.x, .y] and
# a damage_max in [damage_max_range.x, .y]; combat then rolls actual hit
# damage in [item.damage_min, item.damage_max] per swing.
@export var damage_min_range: Vector2 = Vector2(4, 7)
@export var damage_max_range: Vector2 = Vector2(8, 12)

# Attack speed is a cycle multiplier. 1.0 = use skill.cooldown unchanged,
# 2.0 = twice as fast, 0.5 = half as fast. Stat bonuses (+attack_speed_pct)
# add on top: effective = weapon.attack_speed * (1 + bonus_pct).
@export var attack_speed_range: Vector2 = Vector2(0.9, 1.1)

# Both stored as 0..1 and rolled per-instance. Crit_chance feeds crit rolls
# in combat; accuracy gates miss vs hit.
@export var crit_chance_range: Vector2 = Vector2(0.05, 0.10)
@export var accuracy_range: Vector2 = Vector2(0.90, 0.97)

# Effective range in world units. Melee weapons sit around 2–4; ranged
# weapons 12–25+. Combat uses the rolled value from the Item.
@export var weapon_range_range: Vector2 = Vector2(2.5, 3.5)

# The default skills attached to this weapon when rolled. Affixes / class
# perks layer on top in combat resolution.
@export var fire_skill: Skill
@export var alt_fire_skill: Skill
