extends Resource
class_name Skill

enum TargetingMode {
	SINGLE_CONE,
	AOE_RADIAL,
	PROJECTILE,
	HITSCAN,
	SHOTGUN_SPREAD,  # N independent hitscan pellets fanned within cone_deg; each pellet rolls damage + crit independently
	CHAIN_LIGHTNING, # Damage primary target + jump to nearby enemies, optional damage falloff per jump (Taser)
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
	SECOND_WIND,    # instant self-cast → refill resource bar, then cooldown
	AIM_HOLD,       # hold RMB → buff accuracy/crit while drains resource (LMG Tripod, Aimed Shot)
	CHANNEL_BEAM,   # hold LMB/RMB → tick damage via skill.targeting_mode; drains resource per second (Taser hold, Accelerator stream)
	POTION,         # consume a charge from the equipped consumable; starts a HoT on the player
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
@export var projectile_speed: float = 14.0
@export var icon_color: Color = Color(0.7, 0.9, 1.0, 1.0)
## Multiplier applied to the weapon's base damage when this skill fires.
## 1.0 = weapon damage as-is. Values > 1.0 make the skill hit harder than
## a normal attack (e.g. Charged Plasma at 2.5× weapon damage).
@export var damage_multiplier: float = 1.0

## Ammo consumed per cast on bullet weapons. Default 1; shotgun's double-
## barrel uses 2. Energy weapons ignore this entirely (resource_cost
## handles their gate).
@export var ammo_cost: int = 1

## Number of independent hits fired per cast for SHOTGUN_SPREAD targeting.
## Each pellet rolls its own direction within cone_deg and its own damage
## and crit. Ignored by every other targeting mode.
@export var pellet_count: int = 1

# ── Chain lightning (CHAIN_LIGHTNING targeting) ────────────────────────────
## Maximum number of bounces from the primary target. 5 = 1 primary + 5
## additional jumps for 6 total enemies struck. 0 with damage_falloff_pct
## > 0 means "chain until damage drops to ~zero" (the held-Taser pattern).
@export var chain_jumps: int = 0
## Damage radius around each link — the bounce searches for the nearest
## enemy within this radius that hasn't been struck yet.
@export var chain_jump_radius: float = 5.0
## Per-jump damage reduction in percent. 15 = each jump deals 15% less than
## the previous. 0 = no falloff (the RMB High-Voltage pattern).
@export var chain_falloff_pct: float = 0.0
## When chain_jumps == 0 and falloff > 0, the chain keeps bouncing while
## the running damage stays at or above this absolute floor. Stops the
## hold-Taser from infinite-chaining around a horde.
@export var chain_min_damage: int = 1

# ── CHANNEL_BEAM (held-to-damage) ──────────────────────────────────────────
## Seconds between damage ticks while the hold is active. Lower = smoother
## damage numbers, higher = more legible per-hit feedback.
@export var channel_tick_interval: float = 0.15
## Resource drained per second while the hold is active. Hold ends when
## resource pool empties or the user releases the bound input.
@export var channel_resource_per_sec: float = 12.0

# ── Overcharge / status-on-hit ─────────────────────────────────────────────
## Status to apply on hit. &"" = no status. &"weapon_default" = pick the
## status from the weapon's damage_type field (flame→ignite, cryo→freeze,
## electric→stun). Specific names override the weapon's element.
@export var overcharge_status: StringName = &""
## How long the applied status lasts in seconds.
@export var overcharge_status_duration: float = 3.0
## Damage-per-second for ignite-type status applications. Ignored by stun
## and freeze (which are pure CC, not DoT).
@export var overcharge_status_dps: float = 8.0

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
## Explosion radius in world units. Used by grenades and AoE projectiles.
@export var blast_radius: float = 0.0
## GRENADE: detonation behaviour subtype.
@export var grenade_type: GrenadeType = GrenadeType.FRAG

## AIM_HOLD: additive accuracy bonus applied while RMB is held. 0.3 means
## "+30% accuracy on top of the weapon's rolled accuracy" — clamped to 1.0
## downstream so a 0.7-accuracy weapon with +0.3 hold buff fires perfectly
## straight while held.
@export var aim_hold_accuracy_bonus: float = 0.0
## AIM_HOLD: additive crit chance applied while RMB is held. 0.5 means
## "+50% crit chance on every shot fired during the hold."
@export var aim_hold_crit_bonus: float = 0.0
## AIM_HOLD: resource drained per second of hold. Hold ends when the
## resource pool empties (or the player releases RMB).
@export var aim_hold_resource_drain: float = 30.0
## AIM_HOLD: when true, the player can't move while holding. Trades
## mobility for the buff so the hold reads as a deliberate stance, not
## a free always-on benefit.
@export var aim_hold_locks_movement: bool = true

## Airstrike-style PROJECTILE delivery. When true, the projectile is
## NOT fired from the player — instead, an X marker is painted at the
## cursor position (clamped to skill_range) and the projectile spawns
## high above that point falling straight down. Used by RPG Tactical
## Strike. Ignored unless targeting_mode == PROJECTILE.
@export var is_airstrike: bool = false
## Airstrike: meters above the strike point where the projectile spawns.
## Combined with projectile_speed this defines the fall time the X
## marker has to be visible before impact. Lives on the skill so the
## marker spawner (PrototypeAttackIndicator) and the rocket spawner
## (PlayerCombat) read the same value without duplication.
@export var airstrike_fall_height: float = 30.0
