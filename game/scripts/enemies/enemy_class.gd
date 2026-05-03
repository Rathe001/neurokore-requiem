class_name EnemyClass extends Resource

## Behavior profile for an enemy. PrototypeEnemy reads its `enemy_class` to
## decide how to engage the player and whether to broadcast support effects
## to nearby allies. Combinations are first-class: a single class .tres can
## be ranged + heal-aura, melee + damage-buff, etc. by setting both the
## attack fields and the support fields.
##
## Adding a new attack pattern (charge, leap-strike, summoning) is an enum
## extension here plus a branch in PrototypeEnemy. Adding a new support
## variant is the same — extend SupportRole + add the response in the
## support tick.

enum AttackMode {
	MELEE,    # walk into ATTACK_RANGE, swing in cone
	RANGED,   # kite to preferred distance, fire projectile
}

enum SupportRole {
	NONE,         # no support overlay
	HEAL,         # restore allied HP per support tick
	DAMAGE_BUFF,  # multiply allied outgoing damage while in radius
}

@export var id: StringName = &""
@export var label: String = ""

@export_group("Attack")
@export var attack_mode: AttackMode = AttackMode.MELEE
@export var attack_range: float = 2.2          # MELEE swing reach OR RANGED preferred fire distance
@export var attack_cooldown: float = 1.6
@export var attack_windup: float = 0.4
@export var attack_damage_mult: float = 1.0    # multiplied onto the level's rolled damage

@export_group("Melee")
@export var melee_cone_deg: float = 80.0
@export var melee_knockback: float = 5.0

@export_group("Ranged")
## Spawned via EntityPool when the enemy fires. Must be a PrototypeProjectile
## scene (or any node that exposes the same fields used by player projectiles
## — see prototype_projectile.gd).
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 18.0
@export var projectile_max_range: float = 18.0
## Distance the enemy tries to keep from the player while firing — closer
## triggers a backpedal, farther triggers normal chase.
@export var ranged_kite_distance: float = 8.0

@export_group("Support")
@export var support_role: SupportRole = SupportRole.NONE
@export var support_radius: float = 6.0
@export var support_interval: float = 3.0
## HEAL: % of target's max_health restored per tick (0.20 = 20% heal).
## DAMAGE_BUFF: multiplier applied to allied outgoing damage (0.25 = +25%).
@export var support_magnitude: float = 0.20
