class_name EnemySkill extends Resource

## Skill definition for enemies. Each enemy has a basic attack (from
## EnemyClass.basic_attack) and 0-3 specials (rolled from EnemyClass.skill_pool
## at spawn). The AI picks the highest-priority ready skill per attack
## opportunity; no match falls back to the basic attack.
##
## damage_mult is applied on top of the enemy's rolled _attack_damage (from
## LEVEL_DAMAGE_RANGE), not carried as a flat value — so a 1.5× Ground Slam
## on a level-3 enemy deals 1.5× whatever that enemy's base damage is.

enum TargetingMode {
	SINGLE_CONE,    # melee swing in cone
	AOE_RADIAL,     # AoE centered on self
	PROJECTILE,     # ranged projectile(s)
	SELF_BUFF,      # buff self, no targeting
}

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Combat")
@export var targeting_mode: TargetingMode = TargetingMode.SINGLE_CONE
@export var damage_mult: float = 1.0
@export var skill_range: float = 2.2
@export var cooldown: float = 1.6
@export var wind_up: float = 0.4
## Lower = higher priority for AI selection. The AI iterates specials in
## ascending priority order; first skill that passes the range + cooldown
## check wins. Basic attack has implicit infinite priority (always last).
@export var priority: int = 0
@export var knockback: float = 0.0

@export_group("Cone")
@export var cone_deg: float = 80.0

@export_group("Projectile")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 10.0
@export var projectile_max_range: float = 14.0
## Number of projectiles per cast. >1 spawns a symmetric spread around the
## aim vector, each offset by projectile_spread_deg (shotgun pellets).
@export var projectile_count: int = 1
@export var projectile_spread_deg: float = 15.0
## Burst fire: fire burst_count rounds with burst_delay between each.
## burst_count=1 (default) is a single shot. burst_count=3 + burst_delay=0.1
## fires three rapid rounds over 0.2s then waits for the full cooldown.
## Burst rounds re-aim at the player's current position each shot.
@export var burst_count: int = 1
@export var burst_delay: float = 0.1
## AoE blast radius on impact. >0 makes the projectile explode (RPG).
@export var projectile_blast_radius: float = 0.0

@export_group("AoE")
@export var aoe_radius: float = 3.0

@export_group("Self-Buff")
@export var buff_duration: float = 5.0
@export var buff_damage_mult: float = 1.5
@export var buff_speed_mult: float = 1.3

@export_group("Roll")
## Minimum enemy level required before this skill can be assigned.
@export var min_level: int = 1
## Relative weight for weighted-random pool selection.
@export var weight: int = 100
