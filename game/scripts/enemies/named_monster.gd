class_name NamedMonster extends Resource

## Super-rare unique enemy template. Pulls together a fixed identity (name,
## ring tint, model scale), a baseline EnemyClass (melee / ranged / support),
## a guaranteed affix list, and an extra stat boost layered on top of the
## affix mults. EnemySpawner rolls for these BEFORE the pack roll — a hit
## preempts both pack and solo paths and spawns one named monster solo.
##
## Design intent matches D2 unique monsters: fixed names show up rarely,
## telegraph as "this one is special," and reward focused effort with a
## guaranteed high-rarity drop. The named encounter is the headline event
## of an unlucky-for-them room.

@export var id: StringName = &""
@export var display_name: String = ""

## Underlying archetype (drives attack mode + base tuning). Required.
@export var enemy_class: EnemyClass

## Fixed modifier set — same shape as a rare pack's affixes, but authored
## not rolled. Two affixes is the typical sweet spot; named monsters
## should feel meatier than rare leaders without becoming bosses.
@export var affixes: Array[MonsterAffix] = []

@export_group("Stat boost (compounds onto affix mults)")
@export var health_mult: float = 1.5
@export var damage_mult: float = 1.2

@export_group("Visual")
@export var visual_scale: float = 1.25
## Floor ring tint that overrides the affix tint and the level tint.
## Default amber-gold reads as "named" against any biome palette; override
## per-monster only when a named's flavor demands a specific color (e.g.
## a fire-themed named gets deep red).
@export var ring_tint: Color = Color(1.0, 0.85, 0.2, 1.0)

@export_group("Skills")
## Fixed special skills for this named monster. Bypasses the spawner's
## random skill-count roll — these are assigned directly.
@export var special_skills: Array[EnemySkill] = []

@export_group("Roll")
@export var weight: int = 100
@export var min_level: int = 1

@export_group("Drop")
## Floor on the kill drop's rarity. Item generation can roll higher than
## this (e.g. unique on a rare floor) but never lower. Future hook for
## guaranteed unique-tier item drops once that path exists.
@export var guaranteed_drop_rarity: StringName = &"magic"
