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

# Crit chance is now a Head Armor stat domain — weapons no longer roll
# intrinsic crit. The field stays in the schema as (0, 0) so the rolled
# Item.crit_chance is always 0 on a weapon, which makes _roll_crit fall
# through to the player's gear-aggregated crit bonus (sourced from helm).
# Override this on a base only for special weapons that should "guarantee
# crit" regardless of helm — extremely rare; leave at 0/0 for the rest.
@export var crit_chance_range: Vector2 = Vector2(0.0, 0.0)
# Accuracy is weapon-intrinsic — only weapons can roll it (no helm/armor
# affixes touch hit_chance). Rolled per-instance and combat resolves
# miss/hit purely from the weapon plus weapon-only "Honed" affixes.
@export var accuracy_range: Vector2 = Vector2(0.90, 0.97)

# Effective range in world units. Melee weapons sit around 2–4; ranged
# weapons 12–25+. Combat uses the rolled value from the Item.
@export var weapon_range_range: Vector2 = Vector2(2.5, 3.5)

# The default skills attached to this weapon when rolled. Affixes / class
# perks layer on top in combat resolution.
@export var fire_skill: Skill
@export var alt_fire_skill: Skill
