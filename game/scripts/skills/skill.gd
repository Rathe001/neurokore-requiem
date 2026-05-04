extends Resource
class_name Skill

enum TargetingMode {
	SINGLE_CONE,
	AOE_RADIAL,
	PROJECTILE,
	HITSCAN,
}

# Active offhand archetypes. NONE = the skill fires through the normal
# targeting_mode pipeline (cone/aoe/projectile/hitscan, one-shot damage).
# Anything else routes through PrototypePlayer._activate_offhand_skill,
# which owns the per-archetype state machine (buff timers, shield pools,
# grenade arcs). The Skill resource carries the tuning via the fields
# below; the player owns the live state.
enum ActiveKind {
	NONE,           # standard one-shot fire (current behaviour)
	SHIELD_HOLD,    # hold RMB → frontal shield absorbs hits until pool drains, then cooldown
	GRENADE,        # click RMB → throw grenade at cursor with AoE on impact
	SHIELD_BUFF,    # click RMB → buff player with N% damage reduction; cooldown after pool drains
}

enum GrenadeType {
	FRAG,           # standard AoE + full knockback
	INCENDIARY,     # reduced knockback + stun; damage over time later
	CLUSTER,        # smaller primary blast, spawns 3 sub-grenades
	STUN,           # AoE stagger to all hit enemies
}

@export var display_name: String = ""
@export var glyph: String = ""
@export var damage: int = 10
@export var skill_range: float = 100.0
@export var cooldown: float = 0.5
@export var wind_up: float = 0.0
@export var resource_cost: int = 0
@export var targeting_mode: TargetingMode = TargetingMode.SINGLE_CONE
@export var cone_deg: float = 60.0
@export var knockback: float = 0.0
@export var projectile_speed: float = 30.0
@export var icon_color: Color = Color(0.7, 0.9, 1.0, 1.0)

@export_group("Active Offhand")
## Set to anything other than NONE to make this skill an "active offhand"
## — its activation routes through PrototypePlayer's offhand handler
## instead of the standard targeting/fire pipeline. The fields below are
## interpreted per active_kind; unused fields are ignored.
@export var active_kind: ActiveKind = ActiveKind.NONE
## SHIELD_HOLD / SHIELD_BUFF: max damage the shield absorbs before breaking.
## Base value at ilvl 1; rolled items add `shield_pool_bonus` via
## stat_modifiers to scale the effective pool with item level. Skill.cooldown
## applies AFTER a break (not on natural expiry), so a player who never gets
## hit can re-buff freely once the duration runs out.
@export var shield_pool: int = 25
## SHIELD_HOLD / SHIELD_BUFF: fraction of incoming damage the shield
## absorbs (0.25 = 25% reduction). The absorbed amount is subtracted from
## shield_pool each hit.
@export var damage_reduction: float = 0.25
## SHIELD_HOLD / SHIELD_BUFF: how long the buff lasts before it
## naturally expires. Expiry is free — no cooldown applies; the player
## can immediately re-cast. A break (pool drained before expiry) is
## what triggers Skill.cooldown.
@export var duration: float = 120.0
## GRENADE: explosion radius in world units.
@export var blast_radius: float = 3.0
## GRENADE: detonation behaviour subtype.
@export var grenade_type: GrenadeType = GrenadeType.FRAG
