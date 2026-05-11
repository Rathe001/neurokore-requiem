extends CharacterBody3D
class_name PrototypeEnemy

signal died
signal revived

# Knockback decays quadratically over this window so enemies coast to a stop
# instead of snapping back to chase mid-shove. Pre-decay this was a hard
# velocity hold + abrupt cutoff, which read as bouncy.
const KNOCKBACK_DURATION := 0.22

# Hit-squash punch: brief Y compression + horizontal flare to sell the impact
# without leaning fully cartoony. Sized small so PBR characters don't deform
# noticeably outside the strike window.
const HIT_SQUASH_SCALE := Vector3(1.10, 0.85, 1.10)
const HIT_SQUASH_IN := 0.06
const HIT_SQUASH_OUT := 0.16
const DEATH_HOLD := 1.6
const DEATH_FALLBACK_DURATION := 0.6

const CREDIT_DROP_MIN := 1
const CREDIT_DROP_MAX := 5
const CREDIT_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_credit_pickup.tscn")
const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_item_pickup.tscn")
# Base drop chance per enemy. Higher-level enemies get a bonus so killing
# tougher mobs feels more rewarding.
const ITEM_DROP_CHANCE_BASE: float = 0.05
const ITEM_DROP_CHANCE_PER_LEVEL: float = 0.025
# Item level rolls within this window around the enemy's own level so
# drops scale with zone difficulty, not the player's character level.
const ITEM_DROP_ILVL_OFFSET_MIN: int = -1
const ITEM_DROP_ILVL_OFFSET_MAX: int = 1

# Maximum angular spread (radians) at 0% accuracy for enemy projectiles.
# Matched to the player's INACCURACY_SPREAD_MAX so both sides play by
# the same rules — designers tune the feel via EnemyClass.accuracy.
const ENEMY_INACCURACY_SPREAD_MAX: float = 0.25
const ENEMY_VERTICAL_SPREAD_RATIO: float = 0.5

const GRAVITY := 22.0
const CHASE_SPEED := 3.2
const AGGRO_RANGE := 10.0
const GROUP_AGGRO_RANGE := 8.0
# Default attack params — used when `enemy_class` is null. Once every enemy
# scene has an EnemyClass assigned, these become unused and can be deleted.
# Until then they preserve current behaviour for unconfigured spawns.
const DEFAULT_ATTACK_RANGE := 2.2
const DEFAULT_ATTACK_COOLDOWN := 2.0
const DEFAULT_ATTACK_WINDUP := 0.4
const DEFAULT_ATTACK_CONE_DEG := 80.0
const DEFAULT_ATTACK_KNOCKBACK := 0.0
# Hysteresis on the chase→hold transition. Once a melee enemy reaches
# attack range, it stays in hold until distance exceeds attack_range plus
# this buffer. Without it the enemy yo-yos between hold and chase whenever
# the player drifts a few cm across the boundary (knockback, light motion,
# physics push). Same idea for ranged at the kite boundary, with a wider
# buffer because kite distance is larger and ranged enemies should commit
# more strongly to their firing band.
const ATTACK_RANGE_HYSTERESIS := 0.4
const RANGED_KITE_HYSTERESIS := 1.0
# Leash distance — once the enemy strays this far from its spawn while
# chasing, it disengages and walks back to spawn. Prevents whole-level
# chases (and the "lure them into a pit" exploit). Squared for the cheap
# distance check inside _chase_tick.
const MAX_CHASE_FROM_SPAWN_SQ := 225.0  # 15.0 * 15.0
const RETURN_THRESHOLD_SQ := 1.0  # 1.0 * 1.0 — within 1m of spawn = arrived
# If the player is within this distance when the leash trips (or while we're
# returning), don't disengage. Stops the leash from triggering on a kited
# enemy that the player is still actively engaging — the leash is for "I
# walked away," not "I'm fighting you across a doorway."
const KEEP_CHASE_PLAYER_RANGE_SQ := 144.0  # 12.0 * 12.0
# If a returning enemy hasn't made at least this much progress (sq dist
# change) within RETURN_STUCK_TIMEOUT, teleport it home.
const RETURN_STUCK_TIMEOUT := 3.0
const RETURN_STUCK_PROGRESS_SQ := 2.0  # must close 1.4m in 3s or stuck
# Returning enemies take this fraction of damage (5% — effectively immune)
# and skip knockback entirely. Stops the player from kiting an enemy past
# its leash and then sniping it on the walk back.
const RETURNING_DAMAGE_MULT := 0.05
# When an enemy takes damage while idle, the leash extends to reach the
# attacker so sniping from beyond 15m doesn't look like a no-op. The
# extended leash decays when the enemy returns to idle or dies.
const HIT_LEASH_PADDING := 5.0  # extra metres past attacker distance

# Crouch: shrinks the capsule when an overhead probe finds a low ceiling
# (crouch corridors). Restores when overhead clears. The navmesh is baked
# at agent_height=0.9 so pathfinding routes through the same tunnels that
# require the crouch — keep these in sync if either changes.
const STAND_HEIGHT := 1.7
const CROUCH_HEIGHT := 1.0
const CAPSULE_BOTTOM_Y := -0.05  # keeps the capsule bottom at floor level (matches authored stand transform)
const CROUCH_SPEED_MULT := 0.6
# Probe overhead at this cadence — every-frame casts at horde scale add up.
# Each enemy gets a randomised initial offset so the population doesn't
# spike on a single tick.
const CROUCH_PROBE_INTERVAL := 0.25
# The probe capsule covers ONLY the volume that needs to be clear ABOVE
# the crouch capsule for the enemy to stand — a thin slab from the crouch
# capsule's top to the would-be stand capsule's top. Probing the whole
# stand-height capsule (earlier bug) intersected the floor underneath the
# enemy and reported "blocked" every tick, locking everyone into crouch.
const CROUCH_PROBE_HEIGHT := STAND_HEIGHT - CROUCH_HEIGHT  # 0.7
const CROUCH_PROBE_CENTER_Y := CROUCH_HEIGHT + CAPSULE_BOTTOM_Y + CROUCH_PROBE_HEIGHT * 0.5  # 1.30
const CROUCH_PROBE_RADIUS := 0.5  # < capsule radius (0.6) so a brushed wall doesn't trip the probe
# Distance ahead of the enemy to also probe — long enough to clear the
# capsule + a bit of slab so the enemy crouches BEFORE bumping the
# corridor's low-ceiling block, not after. Tuned for the standard 0.6m
# capsule radius + 0.4m wall thickness.
const CROUCH_PROBE_LOOKAHEAD := 1.1
# Low-Y probe used to disambiguate a real low ceiling from a wall / closed
# door. Walls are full-height colliders so they intersect the probe at any
# Y; a low-ceiling slab (corridor ceiling at y=1.4-1.5) doesn't extend
# down to crouch-body height. If the OVERHEAD probe hits but this probe
# is CLEAR, it's a low ceiling and crouching helps. If both hit, it's a
# wall and crouching makes the enemy waddle uselessly into it.
const CROUCH_BODY_PROBE_CENTER_Y := 0.4  # capsule covers y≈0.05-0.75

# Pit-pillar jump: triggered when the navmesh routes the enemy onto a
# NavigationLink3D (placed by pit_builder between adjacent pillars). The
# enemy launches with an impulse that arcs to the link's exit; gravity
# carries them down. JUMP_MISS_CHANCE is rolled per leap — a missed jump
# horizontally undershoots so the enemy lands short and falls into the pit.
const JUMP_AIRTIME := 0.7
const JUMP_MISS_CHANCE := 0.18
const JUMP_MISS_DIST_FACTOR := 0.55  # how far the missed jump reaches (start → 55% toward target)
const JUMP_LANDING_GRACE := 0.18  # require this much airtime before is_on_floor() can end the jump (avoids takeoff-frame false landings)
const JUMP_COOLDOWN := 0.8        # post-landing lockout — caps jump cadence so a chain of pillars doesn't read as constant hopping

# Per-level stat ranges, indexed [1..MAX_LEVEL]. Index 0 is unused (no level 0).
# Tuned so L1 sits near the previous fixed values and each step up ~1.2× the
# threat — a flatter curve that keeps NG+ approachable without exponential
# spikes. Extended to 15 to cover several NG+ cycles; levels beyond MAX_LEVEL
# clamp to the top tier so the game never crashes on deep NG+ runs.
const MAX_LEVEL := 15
# Global HP multiplier applied on top of LEVEL_HP_RANGE rolls. Single knob
# for "enemies are too tanky" tuning — touches every spawn (regular, pack,
# named, boss) without rewriting the per-level table or any per-archetype
# overrides. 1.0 = balanced; lower = squishier.
const HP_GLOBAL_MULT := 0.5
const LEVEL_HP_RANGE: Array[Vector2i] = [
	Vector2i(0, 0),       # 0 — unused
	Vector2i(30, 45),     # 1
	Vector2i(36, 54),     # 2
	Vector2i(44, 65),     # 3
	Vector2i(52, 78),     # 4
	Vector2i(63, 94),     # 5
	Vector2i(76, 113),    # 6
	Vector2i(91, 136),    # 7
	Vector2i(109, 163),   # 8
	Vector2i(131, 196),   # 9
	Vector2i(157, 235),   # 10
	Vector2i(188, 282),   # 11
	Vector2i(226, 339),   # 12
	Vector2i(271, 406),   # 13
	Vector2i(325, 488),   # 14
	Vector2i(390, 585),   # 15
]
const LEVEL_DAMAGE_RANGE: Array[Vector2i] = [
	Vector2i(0, 0),     # 0 — unused
	Vector2i(6, 11),    # 1
	Vector2i(8, 14),    # 2
	Vector2i(10, 17),   # 3
	Vector2i(12, 20),   # 4
	Vector2i(7, 12),    # 5
	Vector2i(9, 15),    # 6
	Vector2i(10, 18),   # 7
	Vector2i(12, 21),   # 8
	Vector2i(15, 25),   # 9
	Vector2i(18, 30),   # 10
	Vector2i(21, 36),   # 11
	Vector2i(26, 43),   # 12
	Vector2i(31, 52),   # 13
	Vector2i(37, 62),   # 14
	Vector2i(44, 75),   # 15
]
# Floor-ring emission color per level. Higher levels glow hotter so a player
# can read threat at a glance from across the room. Levels beyond the array
# clamp to the last entry.
const LEVEL_RING_EMISSION: Array[Color] = [
	Color.BLACK,
	Color(1.0, 0.3, 0.18),   # 1 — warm orange
	Color(1.0, 0.65, 0.15),  # 2 — gold
	Color(1.0, 0.25, 0.05),  # 3 — deep orange
	Color(0.9, 0.15, 0.15),  # 4 — red
	Color(0.8, 0.05, 0.25),  # 5 — crimson
]

# Boss tuning: levels above the trash cap, multipliers stacked on the rolled
# stats, and a deep-red glow distinct from any trash tier.
const BOSS_LEVEL := 5
const BOSS_HP_MULT := 3.0
const BOSS_DAMAGE_MULT := 2.25
# Bosses move at this multiple of CHASE_SPEED so the encounter has more
# pressure than a kited trash mob. Applied in _movement_speed_base().
const BOSS_SPEED_MULT := 1.35
const BOSS_VISUAL_SCALE := 1.6
const BOSS_RING_EMISSION := Color(1.0, 0.05, 0.05)
const MAX_AGGRO_CASCADE := 2

const ANIM_IDLE: Array[StringName] = [&"Idle_Normal", &"Idle", &"IDLE_NORMAL"]
const ANIM_RUN: Array[StringName] = [&"Jog_Fwd", &"Walk_Normal", &"JOG_FWD", &"WALK_NORMAL"]
const ANIM_ATTACK: Array[StringName] = [&"Sword_Attack", &"Punch_Cross", &"SWORD_ATTACK", &"PUNCH_CROSS"]
const ANIM_CROUCH_IDLE: Array[StringName] = [&"Crouch_Idle", &"CROUCH_IDLE", &"Crouch", &"CROUCH"]
const ANIM_CROUCH_RUN: Array[StringName] = [&"Crouch_Walk_Forward", &"Crouch_Walk", &"CROUCH_WALK", &"Crouch_Idle", &"CROUCH_IDLE"]
const ANIM_JUMP: Array[StringName] = [&"Jump", &"Jump_Start", &"JUMP", &"JUMP_START"]
const ANIM_DEATH: Array[StringName] = [
	&"Death_1", &"Death_2", &"Death_A", &"Death_B", &"Death",
	&"Dying_A", &"Dying_B", &"Die",
	&"DEATH_1", &"DEATH_2", &"DEATH",
]

const OUTLINE_GROW := 0.04
const OUTLINE_LOCKED_COLOR := Color(1.0, 0.15, 0.15)

# Random name palette for trash mobs — flavor for the augmentation-facility setting.
# Bosses set their own display_name (assigned by the spawner) and skip the roll.
const NAME_PALETTE: Array[String] = [
	"Husk", "Stray", "Wretch", "Drone", "Brawler",
	"Reject", "Patient", "Recoverer", "Cultist", "Augmented",
]
const NAME_PALETTE_NUMBERED: Array[String] = ["Subject", "Specimen", "Unit"]

static var _s_outline_mat: StandardMaterial3D
static var _s_outline_mat_locked: StandardMaterial3D

@export var max_health: int = 40
@export_range(0.0, 1.0, 0.05) var credit_drop_chance: float = 0.6
@export var display_name: String = "Enemy"
## Enemy level. 0 means "auto-roll within current zone band on init"; spawners that want
## a specific level (e.g. boss encounters) can set it before reset() runs.
@export var level: int = 0
## Boss flag. Bosses use boosted HP/damage, larger visual, distinct floor ring,
## a fixed level above the trash cap, and emit a boss_died group call so the
## exit can unlock.
@export var is_boss: bool = false

## Movement capabilities. Disabled crouching just keeps the capsule standing
## (the navmesh still bakes at crouch height, so a tall enemy will physically
## bump low ceilings instead of slipping under). Disabled jumping means
## NavigationLink3D crossings are silently skipped — the enemy will idle at
## the link entry, which is fine when the encounter is designed to keep that
## enemy in walking-only zones.
@export var can_crouch: bool = true
@export var can_jump: bool = true

## Behaviour profile — attack mode (melee / ranged), per-class attack tuning,
## and optional support overlay (heal / damage-buff aura). When null the
## enemy falls back to the DEFAULT_ATTACK_* constants and pure melee. Assign
## an EnemyClass .tres to differentiate enemy archetypes without touching
## this script.
@export var enemy_class: EnemyClass

## Pack-rare modifier list. Set by EnemySpawner before reset() runs when the
## pack roll succeeds; both the leader and its companions share the same
## affix list. Empty = a regular trash spawn. Affix multipliers compound
## onto the rolled level stats inside _apply_level_stats; the first affix's
## ring_tint overrides the level-based floor-ring color.
@export var affixes: Array[MonsterAffix] = []

## Optional unique-encounter override. Set by EnemySpawner BEFORE reset()
## when the named-roll succeeds (preempts the pack roll); also set by
## explicit per-piece named placements. When non-null:
##   - display_name, ring_tint, visual_scale, and the extra health/damage
##     mults all override the trash defaults.
##   - The named's affix list is copied onto `affixes` so the existing
##     affix-mult path picks them up.
##   - The kill drop's rarity is floored at named.guaranteed_drop_rarity.
@export var named_monster: NamedMonster

@onready var visual: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/Character/AnimationPlayer
@onready var health_bar: MeshInstance3D = $HealthBar
@onready var collision: CollisionShape3D = $Collision
@onready var floor_ring: MeshInstance3D = $FloorRing

# Behaviour states. Mutually exclusive — the enemy is in exactly one at a
# time. Replaces the previous bag of boolean flags (_aggroed / _casting /
# _jumping / _returning_to_spawn / _alive) which couldn't express "what's
# going on right now?" without tedious flag-cross-referencing. Add new
# behaviours by extending this enum + handling them in _physics_process,
# not by introducing more flags.
enum State {
	IDLE,       # Not aggroed; standing or wandering
	CHASING,    # Aggroed; pursuing the player via navmesh
	CASTING,    # Mid attack-windup; locked in place until the swing resolves
	JUMPING,    # Mid pit-jump impulse; physics-driven until landing
	RETURNING,  # Leashed; heading back to spawn (5% dmg + CC immune)
	KNOCKBACK,  # Velocity-controlled by an incoming hit; transitions back to CHASING when the timer drains
	STUNNED,    # Doomsayer stun — frozen in place; transitions back to IDLE when the timer drains
	GRABBED,    # Telekinesis lift — global_position controlled externally by the TelekinesisGrab tween, no gravity, no AI
	DEAD,       # Terminal — physics suspended, awaiting cleanup
}

# `_crouching` stays orthogonal to State — it changes capsule height + speed
# mult but doesn't change WHAT the enemy is doing. Same for the timers below
# (_knockback_remain, _jump_t) which support but don't replace the State.
var _state: State = State.IDLE
var _health: int
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0
var _attack_cd: float = 0.0
var _attack_damage: int = 10
var _want_dir: Vector3 = Vector3.ZERO
# True when in an attack-hold or kite-hold pose. Lets the chase→hold
# transition use a tighter threshold than hold→chase, eliminating boundary
# stutter at attack range / kite distance.
var _holding_position: bool = false
var _player_ref: Node3D
var _outlined_meshes: Array[MeshInstance3D] = []
var _hover_hooked: bool = false
var _hovered: bool = false
# Locked overrides hovered: red persists past mouse-exit until LMB release.
var _tooltip_locked: bool = false
var _hit_tween: Tween
var _hit_flash_tween: Tween
# Captured at the end of reset() so the hit-squash tween can return to
# the right rest pose for bosses + named monsters (which use a non-1.0
# visual scale). Without this, the tween's ".tween_property(...,
# Vector3.ONE, ...)" final keyframe stomps the boss size to ONE on the
# first hit and the boss permanently shrinks.
var _rest_visual_scale: Vector3 = Vector3.ONE
var _crouching: bool = false
var _crouch_probe_t: float = 0.0
var _stand_test_shape: CapsuleShape3D
var _jump_t: float = 0.0
var _jump_cooldown_remain: float = 0.0
# Support overlay state. _support_tick_t counts down to the next emit;
# _damage_buff_mult / _damage_buff_remain are set by ALLIES' support ticks
# (HEAL writes to allies' health directly and leaves no state behind).
# Multiple buffers overlapping take the max magnitude rather than stacking
# additively, so one strong + one weak doesn't double-up.
var _support_tick_t: float = 0.0
var _damage_buff_mult: float = 0.0
var _damage_buff_remain: float = 0.0
# Count Exile curse state. Set ONCE on the first hit while the perk is
# active — subsequent hits don't refresh the timer (the player has to
# commit damage inside the fixed window). Ticks down each frame; on
# expire the enemy calls back to PlayerCombat.fire_exile_shot for the
# massive auto-shot. _curse_marker is a cheap floating glyph above the
# head — visible while cursed, hidden otherwise. Stored as percentages
# (10 / 20 / 40) to match the perk magnitude convention.
var _curse_remain: float = 0.0
var _curse_damage_pct: float = 0.0
var _curse_marker: Label3D = null
# Thin red "red dot sight" line from player to this enemy while cursed.
# Top-level so it lives in world space; tracks both endpoints each tick.
# Cleared AFTER the auto-shot lands (or immediately on death/reset).
var _curse_laser: MeshInstance3D = null
# Enculted Doomsayer afflictions. STUN moves the enemy into State.STUNNED
# (frozen); CHARM repoints the chase target at the nearest other enemy
# without changing State (the existing chase logic does the work via the
# _effective_target() helper); WEAKEN compounds into _outgoing_damage_mult.
# Stun + weaken are timer-driven (independent — an enemy can be stunned
# AND weakened); charm is BOOLEAN — held by PrototypePlayer's FIFO charm
# list, released only when the player dies or a new charm bumps it out.
var _stun_remain: float = 0.0
# Ignite DoT — flame-type weapon overcharge applies. Damage ticks every
# IGNITE_TICK_INTERVAL seconds at _ignite_dps for _ignite_remain
# seconds. Reusable for any future fire/poison/bleed DoT — the field
# names stay generic enough that "ignite" is just the first consumer.
var _ignite_remain: float = 0.0
var _ignite_dps: float = 0.0
var _ignite_tick_accum: float = 0.0
const IGNITE_TICK_INTERVAL := 0.5

# Bleed DoT — applied by 1H melee third-hit combo (and any future
# weapon/affix that wants a "physical" DoT to differentiate from the
# ignite/elemental side). Damage is computed as a fraction of the
# enemy's max HP per tick rather than flat dps, so bleed scales
# meaningfully across enemy tiers. Stacks via _bleed_stacks (each
# stack adds the same per-tick fraction) so chained 3rd-hits compound.
var _bleed_remain: float = 0.0
var _bleed_stacks: int = 0
var _bleed_tick_accum: float = 0.0

# Sniper "First Mark" — timestamp of the last sniper round that hit
# this enemy. The first sniper shot after FIRST_MARK_FRESH_INTERVAL
# seconds of no sniper damage gets +50% damage. Subsequent shots
# inside the window are normal. Resets the freshness clock on every
# sniper hit, so rapid-fire sniping doesn't compound the bonus.
var _sniper_last_hit_t: float = -1000.0
const SNIPER_FIRST_MARK_FRESH_INTERVAL: float = 5.0
const SNIPER_FIRST_MARK_BONUS_MULT: float = 1.5

# Taser "Static Build" — every Nth taser tick on this enemy releases
# at TASER_STATIC_RELEASE_MULT. Per-enemy counter so chain bounces +
# hold-tase ticks compound independently on each target.
var _taser_hit_count: int = 0
const TASER_STATIC_INTERVAL: int = 10
const TASER_STATIC_RELEASE_MULT: float = 3.0


# Atomic check-and-advance for the Taser static-build bonus. Returns
# the damage multiplier (3.0 on the Nth tick, 1.0 otherwise) and
# advances the per-enemy hit counter.
func consume_taser_static_build() -> float:
	_taser_hit_count += 1
	if _taser_hit_count % TASER_STATIC_INTERVAL == 0:
		return TASER_STATIC_RELEASE_MULT
	return 1.0


# Atomic check-and-stamp for the sniper first-mark bonus. Returns the
# damage multiplier (1.5 if "fresh" — no sniper hit in the last
# FIRST_MARK_FRESH_INTERVAL seconds — otherwise 1.0) and updates the
# stamp. Called by the projectile's hit handler before damage is
# rolled.
func consume_sniper_first_mark() -> float:
	var now: float = Time.get_ticks_msec() / 1000.0
	var bonus: float = 1.0
	if now - _sniper_last_hit_t > SNIPER_FIRST_MARK_FRESH_INTERVAL:
		bonus = SNIPER_FIRST_MARK_BONUS_MULT
	_sniper_last_hit_t = now
	return bonus
const BLEED_TICK_INTERVAL := 0.5
# Each stack ticks for this fraction of MAX HP per second — so 1 stack
# is 2% / s, 4 stacks is 8% / s. Body-horror tone wants visible-but-
# not-overwhelming bleed pressure; the % scaling keeps it relevant
# against tank enemies where flat-dps DoTs become trivial.
const BLEED_HP_PCT_PER_SEC: float = 0.02
const BLEED_MAX_STACKS: int = 5
var _charmed: bool = false
var _charm_target: Node3D = null
var _weaken_remain: float = 0.0
var _weaken_mult: float = 0.0  # 0..1 fractional reduction (0.5 = -50% damage)
var _isr_vuln_count: int = 0
var _affliction_marker: Label3D = null
var _floor_ring_mat: StandardMaterial3D
# Skill system state. _special_skills is assigned by the spawner AFTER
# reset(); _skill_cooldowns tracks independent per-skill cooldown timers.
# Self-buff state is set by SELF_BUFF skills and ticks down each frame.
var _special_skills: Array[EnemySkill] = []
var _skill_cooldowns: Dictionary = {}
var _self_buff_remain: float = 0.0
var _self_buff_damage_mult: float = 1.0
var _self_buff_speed_mult: float = 1.0
# Generation counter — incremented on every reset(). Post-await code captures
# the generation before yielding and bails if it changed, preventing stale
# continuations from executing on a pool-recycled entity.
var _generation: int = 0
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
# Spawn position captured on reset() — enemies leash back to this point
# when they chase too far. Set whenever the enemy is reused from the pool
# at a new position.
var _spawn_position: Vector3 = Vector3.ZERO
var _return_stuck_timer: float = 0.0
var _return_last_dist_sq: float = 0.0
var _hit_leash_extend_sq: float = 0.0

# Networking: synced by the MultiplayerSynchronizer to clients. Authority
# (host) writes these each physics tick; clients read them for visuals.
var net_health: int = 0
var net_max_health: int = 0
var net_state: int = 0  # State enum as int
var _net_prev_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_init_enemy()
	_setup_hover()

func _init_enemy() -> void:
	_generation += 1
	add_to_group(&"enemies")
	# SpatialGrid drives AI queries (aggro, support, AoE) — only the host
	# needs it. Clients skip registration since they don't run AI.
	if not _is_remote_enemy():
		SpatialGrid.register(self, &"enemies")
	if not is_boss:
		_roll_display_name()
	# Reset transient visuals before _apply_level_stats so boss scaling, applied
	# inside that call, isn't immediately stomped back to ONE.
	if visual != null:
		visual.rotation = Vector3.ZERO
		visual.scale = Vector3.ONE
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
		_hit_tween = null
	_apply_level_stats()
	# _apply_level_stats handles boss / named visual scale; capture
	# whatever it landed on as the rest pose so the hit-squash tween
	# returns here instead of stomping back to Vector3.ONE.
	if visual != null:
		_rest_visual_scale = visual.scale
	_health = max_health
	_state = State.IDLE
	_knockback_remain = 0.0
	_attack_cd = 0.0
	_want_dir = Vector3.ZERO
	_player_ref = null
	set_physics_process(true)
	collision_layer = _LAYER_ENEMY
	collision_mask = _DEFAULT_ENEMY_MASK
	if collision != null:
		collision.disabled = false
	if floor_ring != null:
		floor_ring.visible = true
	_ensure_loop(ANIM_IDLE)
	_ensure_loop(ANIM_RUN)
	_play_anim(ANIM_IDLE)
	if health_bar != null:
		health_bar.visible = false
	if _stand_test_shape == null:
		_stand_test_shape = CapsuleShape3D.new()
		_stand_test_shape.radius = CROUCH_PROBE_RADIUS
		_stand_test_shape.height = CROUCH_PROBE_HEIGHT
	# Reset crouch on pool re-acquire — pool returned us mid-tunnel, capsule
	# might still be shrunk from prior owner.
	if _crouching:
		_set_crouch(false)
	# Stagger probes across the population so we don't shape-cast for every
	# enemy on the same physics tick.
	_crouch_probe_t = randf() * CROUCH_PROBE_INTERVAL
	_jump_t = 0.0
	_jump_cooldown_remain = 0.0
	_damage_buff_mult = 0.0
	_damage_buff_remain = 0.0
	_curse_remain = 0.0
	_curse_damage_pct = 0.0
	_clear_curse_marker()
	_clear_curse_laser()
	_stun_remain = 0.0
	_ignite_remain = 0.0
	_ignite_dps = 0.0
	_ignite_tick_accum = 0.0
	_bleed_remain = 0.0
	_bleed_stacks = 0
	_bleed_tick_accum = 0.0
	_charmed = false
	_charm_target = null
	_weaken_remain = 0.0
	_weaken_mult = 0.0
	_isr_vuln_count = 0
	_loose_running = false
	_clear_affliction_marker()
	_special_skills.clear()
	_skill_cooldowns.clear()
	_self_buff_remain = 0.0
	_self_buff_damage_mult = 1.0
	_self_buff_speed_mult = 1.0
	_threat_cache = null
	_threat_retarget_t = 0.0
	# Stagger the first support tick by a random fraction of the interval —
	# without this every support enemy in a room emits in lockstep on the
	# same physics frame, spiking the SpatialGrid query cost.
	if enemy_class != null and enemy_class.support_role != EnemyClass.SupportRole.NONE:
		_support_tick_t = randf() * enemy_class.support_interval
	else:
		_support_tick_t = 0.0
	# Connect once — signal stays connected across pool cycles.
	if _nav_agent != null and not _nav_agent.link_reached.is_connected(_on_link_reached):
		_nav_agent.link_reached.connect(_on_link_reached)

## Roll level (if not pre-set) and derive HP, damage, and floor-ring tint.
## Spawners that want a fixed level (e.g. boss) set `level` before reset() runs;
## anything else (including pooled re-acquires) auto-rolls within the zone band.
func _apply_level_stats() -> void:
	if is_boss:
		_apply_boss_stats()
		return
	# Named monsters carry their own EnemyClass + affix list. Copy both onto
	# the enemy's runtime fields BEFORE the affix-mult pass so the existing
	# math + accessors (_attack_range, _attack_cooldown, etc.) pick them up
	# without a separate "is this named?" branch in every helper. Done here
	# (not in the spawner) so per-piece hand-placements behave identically
	# to random-roll spawns.
	if named_monster != null:
		if named_monster.enemy_class != null:
			enemy_class = named_monster.enemy_class
		if not named_monster.affixes.is_empty():
			affixes = named_monster.affixes.duplicate()
	var lv := clampi(level, 0, MAX_LEVEL)
	if lv <= 0:
		# Auto-roll within the current zone band when no explicit level is set.
		var zoff := PlayerState.zone_level_offset()
		var lo := clampi(1 + zoff, 1, MAX_LEVEL)
		var hi := clampi(3 + zoff, lo, MAX_LEVEL)
		lv = randi_range(lo, hi)
	level = lv
	var hp_range := LEVEL_HP_RANGE[lv]
	var dmg_range := LEVEL_DAMAGE_RANGE[lv]
	max_health = int(round(randi_range(hp_range.x, hp_range.y) * HP_GLOBAL_MULT))
	_attack_damage = randi_range(dmg_range.x, dmg_range.y)
	# Compound affix multipliers onto the rolled stats. Storing the per-stat
	# mult product on the enemy lets _attack_cooldown / _chase_speed use them
	# at runtime without re-iterating affixes every tick.
	var hp_mult := 1.0
	var dmg_mult := 1.0
	for affix in affixes:
		if affix == null:
			continue
		hp_mult *= affix.health_mult
		dmg_mult *= affix.damage_mult
	# Named monsters layer their own stat boost on top of affix mults. Same
	# multiplicative model — if the named author wanted "1.6× HP" that's
	# the FINAL multiplier on the affix-modified base, not the raw base.
	if named_monster != null:
		hp_mult *= named_monster.health_mult
		dmg_mult *= named_monster.damage_mult
	max_health = int(round(float(max_health) * hp_mult))
	_attack_damage = int(round(float(_attack_damage) * dmg_mult))
	# Tint priority: named ring > first affix > class type. Named and
	# affix override everything because those identities are the
	# headline visual cue. Otherwise the ring colour communicates the
	# enemy's COMBAT TYPE — melee / ranged / support — so the player
	# can read a pack at a glance and pick targets accordingly.
	var tint_color: Color
	if named_monster != null:
		tint_color = named_monster.ring_tint
	elif not affixes.is_empty() and affixes[0] != null:
		tint_color = affixes[0].ring_tint
	else:
		tint_color = _class_ring_color()
	_apply_floor_ring_tint_color(tint_color)
	_apply_model_tint(tint_color)
	# Visual scale: named > 1.0 boosts the model. Don't scale otherwise (a
	# multi-affix rare keeps the base size — only named encounters earn the
	# silhouette change).
	if named_monster != null and visual != null:
		visual.scale = Vector3.ONE * named_monster.visual_scale
	# Display name: named replaces the rolled trash name AND skips affix
	# label decoration ("Vex, the Sundered" not "Frenzied Jagged Vex…").
	# Plain rare packs still get affix-prefixed names.
	if named_monster != null:
		display_name = named_monster.display_name
	elif not affixes.is_empty():
		var parts: Array[String] = []
		for affix in affixes:
			if affix != null and affix.label != "":
				parts.append(affix.label)
		if not parts.is_empty():
			parts.append(display_name)
			display_name = " ".join(parts)

func _apply_boss_stats() -> void:
	# Boss level scales with the zone: base BOSS_LEVEL + NG+ offset, capped
	# at MAX_LEVEL so the stat array lookup stays in bounds.
	var zoff := PlayerState.zone_level_offset()
	level = clampi(BOSS_LEVEL + zoff, BOSS_LEVEL, MAX_LEVEL)
	var boss_hp := LEVEL_HP_RANGE[level]
	var boss_dmg := LEVEL_DAMAGE_RANGE[level]
	max_health = int(round(randi_range(boss_hp.x, boss_hp.y) * BOSS_HP_MULT * HP_GLOBAL_MULT))
	_attack_damage = int(round(randi_range(boss_dmg.x, boss_dmg.y) * BOSS_DAMAGE_MULT))
	if visual != null:
		visual.scale = Vector3.ONE * BOSS_VISUAL_SCALE
	_apply_floor_ring_tint_color(BOSS_RING_EMISSION)
	_apply_model_tint(BOSS_RING_EMISSION)
	add_to_group(&"bosses")

func _roll_display_name() -> void:
	if randf() < 0.4:
		var prefix: String = NAME_PALETTE_NUMBERED[randi() % NAME_PALETTE_NUMBERED.size()]
		display_name = "%s %02d" % [prefix, randi_range(1, 99)]
	else:
		display_name = NAME_PALETTE[randi() % NAME_PALETTE.size()]

func _apply_floor_ring_tint(lv: int) -> void:
	_apply_floor_ring_tint_color(LEVEL_RING_EMISSION[mini(lv, LEVEL_RING_EMISSION.size() - 1)])


# Per-class ring tint — communicates combat type at a glance. Support
# beats attack mode in the precedence so a "melee + healer" reads as
# support (the rarer / more notable role) rather than blending into a
# pack of plain melee. Falls back to the level tint when the enemy
# has no class assigned (legacy spawns / future archetypes).
const _CLASS_TINT_MELEE := Color(1.0, 0.25, 0.15)
const _CLASS_TINT_RANGED := Color(0.25, 0.65, 1.0)
const _CLASS_TINT_SUPPORT := Color(0.25, 1.0, 0.45)
func _class_ring_color() -> Color:
	if enemy_class == null:
		return LEVEL_RING_EMISSION[mini(clampi(level, 0, MAX_LEVEL), LEVEL_RING_EMISSION.size() - 1)]
	if enemy_class.support_role != EnemyClass.SupportRole.NONE:
		return _CLASS_TINT_SUPPORT
	if enemy_class.attack_mode == EnemyClass.AttackMode.RANGED:
		return _CLASS_TINT_RANGED
	return _CLASS_TINT_MELEE

func _apply_floor_ring_tint_color(color: Color) -> void:
	if floor_ring == null:
		return
	if _floor_ring_mat == null:
		_floor_ring_mat = StandardMaterial3D.new()
		_floor_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_floor_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_floor_ring_mat.albedo_color = Color(0, 0, 0, 0)
		_floor_ring_mat.emission_enabled = true
		_floor_ring_mat.emission_energy_multiplier = 4.0
	_floor_ring_mat.emission = color
	floor_ring.material_override = _floor_ring_mat


## Adds an emissive glow to every mesh surface in the model so the player can
## tell melee (warm), ranged (cool), and support (green) enemies apart at a
## glance. Uses emission rather than albedo tinting because the glb meshes may
## use texture atlases that wash out a subtle albedo shift.
func _apply_model_tint(color: Color) -> void:
	if visual == null:
		return
	_tint_recursive(visual, color)


func _tint_recursive(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		_tint_mesh(node as MeshInstance3D, color)
	for child in node.get_children():
		_tint_recursive(child, color)


# Static cache of tinted materials keyed by (base_material_rid, color) to avoid
# duplicating a new StandardMaterial3D for every surface of every enemy on spawn.
static var _tint_mat_cache: Dictionary = {}

func _tint_mesh(mesh_inst: MeshInstance3D, color: Color) -> void:
	var surface_count := mesh_inst.mesh.get_surface_count() if mesh_inst.mesh != null else 0
	if surface_count == 0:
		return
	for i in surface_count:
		var base_mat := mesh_inst.get_active_material(i)
		if base_mat is StandardMaterial3D:
			var key := Vector3i(base_mat.get_rid().get_id(), color.to_rgba32(), 0)
			var cached: StandardMaterial3D = _tint_mat_cache.get(key)
			if cached == null:
				cached = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				cached.emission_enabled = true
				cached.emission = color
				cached.emission_energy_multiplier = 0.45
				_tint_mat_cache[key] = cached
			mesh_inst.set_surface_override_material(i, cached)
		else:
			var key := Vector3i(0, color.to_rgba32(), 1)
			var cached: StandardMaterial3D = _tint_mat_cache.get(key)
			if cached == null:
				cached = StandardMaterial3D.new()
				cached.emission_enabled = true
				cached.emission = color
				cached.emission_energy_multiplier = 0.45
				_tint_mat_cache[key] = cached
			mesh_inst.set_surface_override_material(i, cached)


## Called by EntityPool.release() before pooling. Disconnects stale listeners.
func _pool_release() -> void:
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
		_hit_tween = null
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
		_hit_flash_tween = null
	for conn in died.get_connections():
		died.disconnect(conn["callable"])
	for conn in revived.get_connections():
		revived.disconnect(conn["callable"])
	_hovered = false
	_tooltip_locked = false
	# Clear level + boss flag so the next reset() re-rolls cleanly. Spawners
	# that need a fixed level/boss reassign these after acquire() and before reset().
	level = 0
	is_boss = false
	display_name = "Enemy"
	remove_from_group(&"bosses")
	_refresh_outline()

## Re-initialize an enemy returned from the pool.
func reset() -> void:
	remove_from_group(&"corpses")
	# Restore the visual the ragdoll spawn hid on death — pool re-acquire
	# would otherwise show an invisible enemy.
	if visual != null:
		visual.visible = true
	_init_enemy()
	# EnemySpawner sets global_position right before calling reset(), so
	# capturing here gives us the correct spawn point even when the enemy
	# is reused from the pool at a new location.
	_spawn_position = global_position
	_hit_leash_extend_sq = 0.0
	# Note: `affixes` is set by the spawner BEFORE reset() in pack-spawn
	# paths, and cleared (re-set to []) by the spawner for non-pack spawns,
	# so a pool-recycled body never inherits the previous owner's modifiers.
	# We don't clear here because the spawner's pre-reset assignment would
	# be wiped.

func _setup_hover() -> void:
	if _s_outline_mat == null:
		_s_outline_mat = StandardMaterial3D.new()
		_s_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_s_outline_mat.albedo_color = Color.WHITE
		_s_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		_s_outline_mat.grow = true
		_s_outline_mat.grow_amount = OUTLINE_GROW
	if _s_outline_mat_locked == null:
		_s_outline_mat_locked = StandardMaterial3D.new()
		_s_outline_mat_locked.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_s_outline_mat_locked.albedo_color = OUTLINE_LOCKED_COLOR
		_s_outline_mat_locked.cull_mode = BaseMaterial3D.CULL_FRONT
		_s_outline_mat_locked.grow = true
		_s_outline_mat_locked.grow_amount = OUTLINE_GROW
	_outlined_meshes.clear()
	_collect_meshes(visual)
	if not _hover_hooked:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		_build_hover_zone()
		_hover_hooked = true


# Generous Area3D capsule that catches mouse-picking ahead of the body's
# tighter physics capsule. Players reported it was hard to click enemies
# — the body shape is sized for movement (0.6m radius), which leaves a
# thin ring around each enemy that the cursor slips through. The hover
# zone is roughly twice as wide so click and tooltip-lock-on land
# reliably even on small enemies.
const _HOVER_RADIUS: float = 1.1
const _HOVER_HEIGHT: float = 2.2

func _build_hover_zone() -> void:
	var area := Area3D.new()
	area.name = &"HoverZone"
	# Pure picker — never detected by anything else's mask, never detects
	# anything itself. Layer/mask both 0; input_ray_pickable=true is what
	# makes physics_object_picking notice it.
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.input_ray_pickable = true
	# Sit at chest height so the capsule covers the visible silhouette.
	area.position = Vector3(0.0, 0.8, 0.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _HOVER_RADIUS
	cap.height = _HOVER_HEIGHT
	shape.shape = cap
	area.add_child(shape)
	add_child(area)
	# Forward Area3D mouse events into the same handlers the body uses,
	# so &"tooltip_target" group membership, lock-on routing, and the
	# outline highlight all "just work" via one path.
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)

func _collect_meshes(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D:
			_outlined_meshes.append(child)
		_collect_meshes(child)

func _refresh_outline() -> void:
	var mat: Material = null
	if _tooltip_locked:
		mat = _s_outline_mat_locked
	elif _hovered:
		mat = _s_outline_mat
	for mi in _outlined_meshes:
		if is_instance_valid(mi):
			mi.material_overlay = mat

func _on_mouse_entered() -> void:
	if not _is_alive():
		return
	_hovered = true
	_refresh_outline()
	add_to_group(&"tooltip_target")
	_push_tooltip()


# Build + push the rich tooltip. Title is name + level; body lists the
# combat type, current HP, and any active buffs/debuffs (curse, stun,
# weaken, charmed/friendly). Called from mouse-enter and from any
# state change while hovered (curse applied, stun expired, take_damage)
# via _refresh_tooltip_if_hovered, so the tooltip stays accurate
# without needing a re-hover.
func _push_tooltip() -> void:
	var title := "%s  %s" % [display_name, tr("HUD_LEVEL_FORMAT") % level]
	var body := _build_tooltip_body()
	get_tree().call_group(&"interactable_tooltip", &"show_talent_node", title, body)


func _build_tooltip_body() -> String:
	var lines: Array[String] = []
	lines.append(_describe_class())
	lines.append("HP: %d / %d" % [maxi(_health, 0), max_health])
	# Active buffs / debuffs — only listed when present so a clean
	# enemy reads short. Order: friendly status first (it's an identity
	# flag, not a debuff), then time-bound debuffs in expiry order.
	if _charmed:
		lines.append("Friendly (charmed)")
	if _stun_remain > 0.0:
		lines.append("Stunned · %.1fs" % _stun_remain)
	if _bleed_remain > 0.0 and _bleed_stacks > 0:
		# % HP per second from BLEED_HP_PCT_PER_SEC × stacks — shown as
		# the rate so the player can reason about whether to keep
		# stacking or move to a new target.
		var bleed_pct := int(round(BLEED_HP_PCT_PER_SEC * 100.0 * float(_bleed_stacks)))
		lines.append("Bleed ×%d (−%d%% HP/s) · %.1fs" % [_bleed_stacks, bleed_pct, _bleed_remain])
	if _weaken_remain > 0.0:
		var pct := int(round(_weaken_mult * 100.0))
		lines.append("Weakened −%d%% dmg · %.1fs" % [pct, _weaken_remain])
	if _curse_remain > 0.0 and _curse_damage_pct > 0.0:
		lines.append("Cursed +%d%% dmg taken · %.1fs" % [int(round(_curse_damage_pct)), _curse_remain])
	if _isr_vuln_count > 0:
		var vuln_pct := int(round(float(_isr_vuln_count) * (ISRDrone.VULN_MULT - 1.0) * 100.0))
		lines.append("ISR Scanned +%d%% dmg taken" % vuln_pct)
	# Affix names — already baked into display_name's prefix, but
	# spelling them out as a discrete line makes it explicit when an
	# elite shows up so the player knows what they're up against.
	if _self_buff_remain > 0.0:
		lines.append("Enraged · %.1fs" % _self_buff_remain)
	if not affixes.is_empty():
		var labels: Array[String] = []
		for affix in affixes:
			if affix != null and affix.label != "":
				labels.append(affix.label)
		if not labels.is_empty():
			lines.append("Affixes: " + ", ".join(labels))
	if not _special_skills.is_empty():
		var skill_names: Array[String] = []
		for sk in _special_skills:
			if sk != null and sk.display_name != "":
				skill_names.append(sk.display_name)
		if not skill_names.is_empty():
			lines.append("Skills: " + ", ".join(skill_names))
	return "\n".join(lines)


# Single-line "Melee", "Ranged", "Healer", "Buffer", or combinations
# like "Melee · Healer" when the enemy has both an attack mode and a
# support role.
func _describe_class() -> String:
	if enemy_class == null:
		return "Unknown type"
	var attack: String = "Ranged" if enemy_class.attack_mode == EnemyClass.AttackMode.RANGED else "Melee"
	var support: String = ""
	match enemy_class.support_role:
		EnemyClass.SupportRole.HEAL:
			support = "Healer"
		EnemyClass.SupportRole.DAMAGE_BUFF:
			support = "Buffer"
	if support == "":
		return attack
	return "%s · %s" % [attack, support]


# Re-push the tooltip if currently hovered, so applied / expired
# debuffs and HP changes show up live without forcing a re-hover.
# Cheap when not hovered (single bool check + early return).
func _refresh_tooltip_if_hovered() -> void:
	if _hovered or _tooltip_locked:
		_push_tooltip()

func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_outline()
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func set_tooltip_locked(on: bool) -> void:
	_tooltip_locked = on
	_refresh_outline()

## Static helper: route damage to an enemy, handling SP / MP host / MP client
## transparently. Every damage source (player_combat, projectile, grenade,
## trap, telekinesis, doomsayer) calls this instead of target.take_damage().
## In SP or on the host, calls take_damage directly. On a MP client, sends
## the hit to the host via RPC. Hit visuals (damage number, flash, squash)
## are broadcast to ALL clients by the host's take_damage via _client_show_hit,
## so the client path no longer spawns local feedback.
static func deal_damage(target: Node3D, amount: int, knockback_from: Vector3, knockback_strength: float = 0.0, multistrike: int = 1, is_crit: bool = false) -> void:
	if NetState.is_in_lobby() and not NetState.is_host():
		target.request_damage.rpc_id(1, amount, knockback_from, knockback_strength, multistrike, is_crit)
		return
	target.take_damage(amount, knockback_from, knockback_strength, multistrike, is_crit)

## RPC endpoint: any peer can request damage on an enemy. Only the host
## (authority) actually applies it — clients' local take_damage is gated.
## Clients call `request_damage.rpc_id(1, ...)` to route hits to the host.
@rpc("any_peer", "call_remote", "reliable")
func request_damage(amount: int, knockback_from: Vector3, knockback_strength: float, multistrike: int, is_crit: bool) -> void:
	if not multiplayer.is_server():
		return
	if not is_inside_tree():
		return
	take_damage(amount, knockback_from, knockback_strength, multistrike, is_crit)

## Host → all clients: play hit visuals (damage number, squash, flash).
## Sent from take_damage after the host applies damage so every client
## sees every hit, not just the attacker. Unreliable because a dropped
## damage number is cosmetic — no gameplay impact.
@rpc("authority", "call_remote", "unreliable")
func _client_show_hit(amount: int, multistrike: int, is_crit: bool) -> void:
	var head := global_position + Vector3(0.0, 1.8, 0.0)
	DamageNumber.spawn(get_parent(), head, amount, multistrike, is_crit)
	_play_hit_squash()
	_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween)

func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0, multistrike: int = 1, is_crit: bool = false) -> void:
	if not _is_alive():
		return
	# Clients don't apply damage locally — they route hits through
	# request_damage RPC to the host.
	if _is_remote_enemy():
		return
	if DebugState.config != null and DebugState.config.one_shot_enemies:
		amount = max(amount, max_health)
	# Returning enemies (leash tripped) take ~5% damage and skip CC. Without
	# this the player can kite an enemy out of its territory and snipe it on
	# the walk back. The leash should read as "give up + reset", not a free
	# kill window.
	var returning := _state == State.RETURNING
	if returning:
		amount = maxi(1, int(round(float(amount) * RETURNING_DAMAGE_MULT)))
	# Count Exile curse — cursed enemies take +X% damage from any source
	# (the curse is applied by PlayerCombat after the player's hits, but
	# the modifier applies regardless of who's swinging). Returning-leash
	# damage reduction takes effect FIRST so a kite-cursed enemy still
	# enjoys the leash protection.
	if _curse_damage_pct > 0.0:
		amount = int(round(float(amount) * (1.0 + _curse_damage_pct * 0.01)))
	if _isr_vuln_count > 0:
		amount = int(round(float(amount) * (1.0 + float(_isr_vuln_count) * (ISRDrone.VULN_MULT - 1.0))))
	_health -= amount
	_update_health_bar()
	var head := global_position + Vector3(0.0, 1.8, 0.0)
	DamageNumber.spawn(get_parent(), head, amount, multistrike, is_crit)
	WeaponSounds.play_generic(&"hit_flesh", global_position)
	# Snapshot the pre-hit state BEFORE the knockback transition so the
	# aggro check below sees the original disposition. Without this, any
	# IDLE enemy that gets knocked back loses the IDLE→aggro transition
	# (state is now KNOCKBACK at the check) and 1-shot kills never alert
	# their pack — both bugs masked the same way.
	var pre_hit_state := _state
	if knockback_strength > 0.0 and not returning:
		var dir := global_position - knockback_from
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			_knockback_vel = dir.normalized() * knockback_strength
			_knockback_remain = KNOCKBACK_DURATION
			# Knockback preempts whatever we were doing (chase, casting,
			# jumping). The casting await checks _state on resume and bails.
			_change_state(State.KNOCKBACK)
	# Re-aggro on hit unless we're disengaging — getting nicked while heading
	# back shouldn't yank the enemy toward the player; that defeats the leash.
	# Fires even on a fatal hit (before _die below) so the dying enemy still
	# alerts the pack — single-shot kills shouldn't silence group aggro.
	if pre_hit_state == State.IDLE:
		# Extend leash so the enemy can actually reach a long-range attacker
		# (sniper/RPG from beyond the default 15m leash). The padding gives
		# a few extra metres so the enemy doesn't leash the instant it reaches
		# the player's former position.
		if _player_ref != null and is_instance_valid(_player_ref):
			var dist_to_player := _spawn_position.distance_to(_player_ref.global_position) + HIT_LEASH_PADDING
			_hit_leash_extend_sq = maxf(_hit_leash_extend_sq, dist_to_player * dist_to_player)
		aggro()
	_play_hit_squash()
	_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween)
	_refresh_tooltip_if_hovered()
	# Broadcast hit visuals to all clients so every player sees every hit's
	# damage number, squash, and flash — not just the attacker.
	if NetState.is_in_lobby():
		_client_show_hit.rpc(amount, multistrike, is_crit)
	if _health <= 0:
		_die(knockback_from, knockback_strength)

## Helper — DEAD is the only state in which the enemy should ignore inputs
## (damage, animation triggers, hover). All other states are "alive enough."
func _is_alive() -> bool:
	return _state != State.DEAD

## True when this enemy exists on a non-host client in an active MP session.
## Same detection rule as _is_remote_player: NetState.is_in_lobby() is the
## SP/MP discriminator (multiplayer.has_multiplayer_peer() lies because
## GodotSteam binds a peer at Steam init). Enemy authority always stays
## with the host (peer 1) — they're never transferred.
func _is_remote_enemy() -> bool:
	if not NetState.is_in_lobby():
		return false
	return not is_multiplayer_authority()


# Per-class attack-param accessors. Precedence: EnemySkill basic_attack →
# legacy EnemyClass inline fields → DEFAULT_* constants. Once every class
# has a basic_attack .tres, the legacy fields and DEFAULT_* consts can go.
func _attack_range() -> float:
	if enemy_class != null and enemy_class.basic_attack != null:
		return enemy_class.basic_attack.skill_range
	return enemy_class.attack_range if enemy_class != null else DEFAULT_ATTACK_RANGE

func _attack_cooldown() -> float:
	var base: float
	if enemy_class != null and enemy_class.basic_attack != null:
		base = enemy_class.basic_attack.cooldown
	elif enemy_class != null:
		base = enemy_class.attack_cooldown
	else:
		base = DEFAULT_ATTACK_COOLDOWN
	return base * _affix_attack_cooldown_mult()

func _attack_windup() -> float:
	if enemy_class != null and enemy_class.basic_attack != null:
		return enemy_class.basic_attack.wind_up
	return enemy_class.attack_windup if enemy_class != null else DEFAULT_ATTACK_WINDUP

func _melee_cone_deg() -> float:
	if enemy_class != null and enemy_class.basic_attack != null:
		return enemy_class.basic_attack.cone_deg
	return enemy_class.melee_cone_deg if enemy_class != null else DEFAULT_ATTACK_CONE_DEG

func _melee_knockback() -> float:
	if enemy_class != null and enemy_class.basic_attack != null:
		return enemy_class.basic_attack.knockback
	return enemy_class.melee_knockback if enemy_class != null else DEFAULT_ATTACK_KNOCKBACK

func _is_ranged() -> bool:
	return enemy_class != null and enemy_class.attack_mode == EnemyClass.AttackMode.RANGED

func _ranged_kite_distance() -> float:
	return enemy_class.ranged_kite_distance if enemy_class != null else 8.0


# Affix-driven runtime multipliers — walked at access rather than cached so
# future buff overlays (slow, haste status effects) can layer onto the same
# accessor without a separate refresh pass. At horde scale this is still
# cheap; the affix list is typically 1-2 entries.
func _affix_attack_cooldown_mult() -> float:
	var m := 1.0
	for affix in affixes:
		if affix != null:
			m *= affix.attack_cooldown_mult
	return m

func _affix_move_speed_mult() -> float:
	var m := 1.0
	for affix in affixes:
		if affix != null:
			m *= affix.move_speed_mult
	return m


# Run one support tick — query SpatialGrid for nearby allies (including self,
# so a buffer benefits from its own aura) and apply HEAL or DAMAGE_BUFF
# based on enemy_class.support_role. Buffer lifetime is interval * 1.1 so
# the next tick refreshes the buff before it expires (small overlap masks
# the ramp-down between ticks).
func _emit_support() -> void:
	if enemy_class == null or enemy_class.support_role == EnemyClass.SupportRole.NONE:
		return
	var radius := enemy_class.support_radius
	var role := enemy_class.support_role
	var magnitude := enemy_class.support_magnitude
	var magnitude_max := enemy_class.support_magnitude_max
	var buff_duration := enemy_class.support_interval * 1.1
	for ally: Node in SpatialGrid.query_radius(global_position, radius, &"enemies"):
		if ally == null or not is_instance_valid(ally):
			continue
		if not (ally is PrototypeEnemy):
			continue
		var ae: PrototypeEnemy = ally
		if not ae._is_alive():
			continue
		# Charmed support enemies should only buff/heal fellow charmed
		# allies (or self), not hostile enemies they're betraying.
		# Non-charmed supports skip charmed targets for symmetry.
		if _charmed != ae._charmed:
			continue
		match role:
			EnemyClass.SupportRole.HEAL:
				# Per-target roll so heal sizes vary across the pack rather
				# than every ally getting an identical chunk.
				var pct := magnitude
				if magnitude_max > magnitude:
					pct = randf_range(magnitude, magnitude_max)
				ae.heal(int(round(float(ae.max_health) * pct)))
			EnemyClass.SupportRole.DAMAGE_BUFF:
				ae.apply_damage_buff(magnitude, buff_duration)


## Restore HP up to max_health. Called by allied support enemies' ticks;
## a no-op on dead enemies (corpses don't recover).
func heal(amount: int) -> void:
	if not _is_alive() or amount <= 0:
		return
	var before := _health
	_health = mini(_health + amount, max_health)
	_update_health_bar()
	_refresh_tooltip_if_hovered()
	var gained := _health - before
	if gained > 0:
		_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween, HitFlash.HEAL_COLOR)
		var head := global_position + Vector3(0.0, 1.8, 0.0)
		DamageNumber.spawn_heal(get_parent(), head, gained)


## Apply (or refresh) a damage-buff overlay. Multiple buffers overlapping
## take the max magnitude rather than stacking; duration always extends
## to the longer of current vs new so a brief weak refresh from one buffer
## doesn't shorten a stronger pulse from another.
func apply_damage_buff(magnitude: float, duration: float) -> void:
	if not _is_alive():
		return
	if magnitude > _damage_buff_mult:
		_damage_buff_mult = magnitude
	if duration > _damage_buff_remain:
		_damage_buff_remain = duration


## Final damage multiplier for an outgoing attack — base class mult
## (configured per archetype) compounded with active support-aura buff and
## the Doomsayer weaken debuff. Order is buff-then-weaken so a buffed
## enemy doesn't evade the weakening, and a weakened enemy that picks up
## a buff doesn't suddenly wash out the debuff.
func _outgoing_damage_mult() -> float:
	var class_mult := enemy_class.attack_damage_mult if enemy_class != null else 1.0
	return class_mult * (1.0 + _damage_buff_mult) * _self_buff_damage_mult * (1.0 - _weaken_mult)


## Apply the Count Exile curse. ONLY takes effect when the enemy isn't
## already cursed — subsequent hits inside the active window are silently
## ignored, by design (the duration is fixed from first application so the
## player has to commit damage inside it; refreshing on every hit would
## let an aggressive player keep an enemy permanently tagged for free).
## After the curse expires, the next hit re-arms it. Skip on dead enemies
## — corpses don't carry tags.
func apply_curse(damage_pct: float, duration: float) -> void:
	if not _is_alive() or damage_pct <= 0.0 or duration <= 0.0:
		return
	# Player-friendly (charmed) enemies are immune to player-sourced
	# debuffs — Exile included. They're fighting for us; cursing them
	# would be friendly fire.
	if is_player_friendly():
		return
	if _curse_remain > 0.0:
		return
	_curse_damage_pct = damage_pct
	_curse_remain = duration
	_show_curse_marker()
	_show_curse_laser()
	_refresh_tooltip_if_hovered()


# True when this enemy is currently controlled by the player (charmed
# via Doomsayer). The player's damage paths and debuffs check this and
# skip affected enemies — charmed enemies fight for the player, so
# player attacks would be friendly fire.
func is_player_friendly() -> bool:
	return _charmed


# True when this enemy is actively pursuing the player (CHASING state and
# not on the player's team via charm). Used by the player's HP regen tick
# to gate "out of combat" — any nearby aggro'd enemy keeps regen paused
# even when the player isn't being hit. Knockback / stunned / grabbed
# count too: the enemy is meaningfully engaged, just not currently mobile.
func is_engaged_with_player() -> bool:
	if _charmed:
		return false
	return _state == State.CHASING or _state == State.KNOCKBACK or _state == State.STUNNED or _state == State.GRABBED


# Tick the curse timer; on expire, fire the player's auto-shot at this
# enemy and clear local curse state. The shot is fired by PlayerCombat so
# the damage / VFX live with the player-side combat code; we just provide
# the trigger and the target reference.
func _tick_curse(delta: float) -> void:
	if _curse_remain <= 0.0:
		return
	_curse_remain -= delta
	if _curse_remain > 0.0:
		# Still cursed — keep the laser tracking both endpoints.
		_update_curse_laser()
		return
	_curse_damage_pct = 0.0
	_curse_remain = 0.0
	_clear_curse_marker()
	# Fire the expire shot through the player. _player_ref might still be
	# null if we were cursed before ever being aggro'd (rare — would require
	# a remote AoE hit) — fall back to a group lookup in that case.
	var player: Node3D = _player_ref
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	if player != null and player.has_method(&"fire_exile_shot"):
		player.fire_exile_shot(self)
	# Laser disappears AFTER the target takes damage from Exile — order is
	# significant: clearing before fire_exile_shot would leave a one-frame
	# gap where the shot hits but the targeting beam is already gone.
	_clear_curse_laser()


# Floating glyph above the head — visible while cursed, freed on expire.
# Cheap (single Label3D), doesn't conflict with the hit-flash overlay or
# affix tinting on the floor ring.
func _show_curse_marker() -> void:
	if _curse_marker != null and is_instance_valid(_curse_marker):
		return
	var lbl := Label3D.new()
	lbl.text = "✦"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0014
	lbl.font_size = 32
	lbl.outline_size = 8
	lbl.modulate = Color(0.95, 0.85, 0.3, 1.0)
	lbl.outline_modulate = Color(0.05, 0.0, 0.1, 1.0)
	lbl.position = Vector3(0.0, 2.4, 0.0)
	add_child(lbl)
	_curse_marker = lbl


func _clear_curse_marker() -> void:
	if _curse_marker != null and is_instance_valid(_curse_marker):
		_curse_marker.queue_free()
	_curse_marker = null


# Thin red beam from the player's chest to the cursed enemy's chest. Reads
# as a red-dot-sight reticle in 3D — telegraphs the impending Exile auto-shot
# without the visual weight of a hitscan beam. Built once, repositioned each
# tick via _update_curse_laser; freed when the curse ends.
const CURSE_LASER_RADIUS: float = 0.005
const CURSE_LASER_COLOR: Color = Color(1.0, 0.18, 0.18, 0.25)
const CURSE_LASER_PLAYER_OFFSET: Vector3 = Vector3(0.0, 1.0, 0.0)
const CURSE_LASER_TARGET_OFFSET: Vector3 = Vector3(0.0, 1.0, 0.0)

func _show_curse_laser() -> void:
	if _curse_laser != null and is_instance_valid(_curse_laser):
		return
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = CURSE_LASER_RADIUS
	cyl.bottom_radius = CURSE_LASER_RADIUS
	cyl.height = 1.0  # scaled per-frame
	cyl.radial_segments = 6
	cyl.cap_top = false
	cyl.cap_bottom = false
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = CURSE_LASER_COLOR
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.25, 1.0)
	# Low emission so the beam reads as a thin cue rather than a glow
	# strip — anything brighter blooms out the bullet/laser cues nearby.
	mat.emission_energy_multiplier = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Don't cast shadows — a red shadow strip from a sight beam reads as a
	# bug, not stylistic.
	mat.shadow_to_opacity = false
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# top_level so the laser's transform isn't dragged by the enemy's local
	# space — both endpoints are world-space positions.
	mesh_inst.top_level = true
	add_child(mesh_inst)
	_curse_laser = mesh_inst
	_update_curse_laser()


func _clear_curse_laser() -> void:
	if _curse_laser != null and is_instance_valid(_curse_laser):
		_curse_laser.queue_free()
	_curse_laser = null


# Recomputes laser endpoints — player chest to enemy chest. The cylinder's
# default Y axis is rotated to align with the player→enemy vector via a
# shortest-arc quaternion; degenerate (player and enemy coincident) hides
# the laser for the frame.
func _update_curse_laser() -> void:
	if _curse_laser == null or not is_instance_valid(_curse_laser):
		return
	var player: Node3D = _player_ref
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or not is_inside_tree():
		_curse_laser.visible = false
		return
	var p_pos: Vector3 = player.global_position + CURSE_LASER_PLAYER_OFFSET
	var e_pos: Vector3 = global_position + CURSE_LASER_TARGET_OFFSET
	var diff := e_pos - p_pos
	var dist := diff.length()
	if dist < 0.05:
		_curse_laser.visible = false
		return
	_curse_laser.visible = true
	_curse_laser.global_position = (p_pos + e_pos) * 0.5
	var dir := diff / dist
	# Order matters: assigning `basis` REPLACES the entire 3×3 matrix,
	# including its scale component. So set rotation first, then scale, or
	# the cylinder snaps back to unit length and never stretches between
	# the endpoints.
	# Quaternion(arc_from, arc_to) returns the shortest-arc rotation; safe
	# for parallel vectors but degenerate when antiparallel — fall back to
	# a 180° flip around X in that case.
	if dir.dot(Vector3.UP) < -0.9999:
		_curse_laser.basis = Basis(Vector3(1.0, 0.0, 0.0), PI)
	else:
		_curse_laser.basis = Basis(Quaternion(Vector3.UP, dir))
	_curse_laser.scale = Vector3(1.0, dist, 1.0)


# ---------------------------------------------------------------------------
# Enculted Doomsayer afflictions — stun / charm (mind-control) / weaken
# ---------------------------------------------------------------------------

## Frozen in place for `duration`. Interrupts whatever the enemy was doing
## (chase, mid-cast, return) by switching to State.STUNNED — the cast's
## post-windup _state check bails on its own. Refreshes to the longer of
## current vs new so a fresh proc never shortens an active stun. RETURNING
## enemies (leashed) ignore — leash is treated as CC immune.
## Apply or refresh ignite. Higher dps wins (don't replace strong burn
## with weak); duration extends if longer. Damage ticks via
## _tick_afflictions every IGNITE_TICK_INTERVAL seconds.
func apply_ignite(dps: float, duration: float) -> void:
	if dps <= 0.0 or duration <= 0.0:
		return
	if not _is_alive():
		return
	if dps > _ignite_dps:
		_ignite_dps = dps
	if duration > _ignite_remain:
		_ignite_remain = duration


## Apply or refresh bleed. Stacks (each call adds 1 stack up to BLEED_
## MAX_STACKS); duration extends if longer. Tick damage scales with the
## enemy's max HP so bleed stays meaningful against tank tiers.
func apply_bleed(duration: float, stacks: int = 1) -> void:
	if not _is_alive() or duration <= 0.0 or stacks <= 0:
		return
	_bleed_stacks = mini(BLEED_MAX_STACKS, _bleed_stacks + stacks)
	if duration > _bleed_remain:
		_bleed_remain = duration


func apply_stun(duration: float) -> void:
	if not _is_alive() or duration <= 0.0:
		return
	if _state == State.RETURNING or _state == State.JUMPING:
		return
	if duration > _stun_remain:
		_stun_remain = duration
	# Don't yank a Telekinesis-grabbed enemy out of GRABBED — the lift
	# tween still owns global_position and STUNNED's velocity zero
	# would conflict with it. The stun timer is preserved (and paused
	# in _tick_afflictions while GRABBED), so on release_grab the
	# enemy transitions straight into STUNNED with the full duration
	# remaining for the post-slam follow-up window.
	if _state != State.GRABBED:
		_change_state(State.STUNNED)
		velocity = Vector3.ZERO
	_show_affliction_marker("✱", Color(0.55, 0.7, 1.0, 1.0))
	_refresh_tooltip_if_hovered()


## Mind-control: the enemy chases / attacks the nearest other enemy
## instead of the player. Persistent — does NOT expire on a timer. The
## player owns the charm list (FIFO-capped via doomsayer_max_charms) and
## calls release_charm when the cap evicts this enemy or the player dies.
## Returns false when the application failed (no other enemy in range,
## or the enemy is leashed/dead) so the caller can skip adding to the
## charm list. Returns true on a successful charm.
# Physics layer values (mirrors the project layer scheme — see CLAUDE.md
# section on collision layers / `docs/status.md` notes).
const _LAYER_WORLD := 1
const _LAYER_ENEMY := 2
const _LAYER_PLAYER := 4
# Charmed pets move to a dedicated "ally" layer that the player's mask
# (1|2) does NOT include — so the player passes through pets without
# getting body-blocked. Hostile enemies' mask DOES include this layer
# (_DEFAULT_ENEMY_MASK below), so a pet and a hostile melee'ing each
# other body-block each other and stand still while swinging instead
# of sliding through one another in a tug-of-war.
const _LAYER_CHARMED_ALLY := 16
# Layer 7 (Interactables) — chests, doors, switches, exit pads. Off the
# World layer so projectiles + LoS rays pass straight through, but kept
# in the movement masks below so player and enemies can't walk through
# them. Same trade as monsters from a Diablo: solid to feet, transparent
# to bullets.
const _LAYER_INTERACTABLE := 64
# Layer 8 (Pillars) — movement-blocking but LoS-transparent obstacles.
# Player, enemy, projectile, and corpse masks all include this so pillars
# physically interact like walls; LoSCuller + ProximityLighting (which
# mask Layer 1 only) ignore them, preserving sightlines through nearby
# columns.
const _LAYER_PILLAR := 128
const _DEFAULT_ENEMY_MASK := _LAYER_WORLD | _LAYER_ENEMY | _LAYER_PLAYER | _LAYER_CHARMED_ALLY | _LAYER_INTERACTABLE | _LAYER_PILLAR  # 215
# Pets collide with world, hostile enemies, AND other pets (layer 16) —
# but NOT the player. Including the ally bit means two pets can't stand
# on top of each other; they push apart naturally via move_and_slide.
const _CHARMED_PET_MASK := _LAYER_WORLD | _LAYER_ENEMY | _LAYER_CHARMED_ALLY | _LAYER_INTERACTABLE | _LAYER_PILLAR  # 211


## True for plain (normal-rarity) enemies that the Doomsayer aura is
## allowed to convert. Bosses, named monsters, and rare-pack members
## are immune so bossfights / set-piece encounters can't be trivialised
## by flipping the headliner to the player's side.
func is_charmable() -> bool:
	return not is_boss and named_monster == null and affixes.is_empty()


func apply_charm() -> bool:
	if not _is_alive():
		return false
	if _state == State.RETURNING:
		return false
	if _charmed:
		# Already charmed — caller shouldn't double-add. Returning false so
		# the player's FIFO list doesn't gain a duplicate entry.
		return false
	if not is_charmable():
		return false
	_charmed = true
	# Initial target is best-effort. null is fine — _tick_afflictions
	# re-picks every frame and the chase tick falls back to "follow
	# player loosely" until a real enemy walks into AGGRO_RANGE.
	_charm_target = _pick_nearest_other_enemy()
	# A stunned enemy snapping out of stun should still resume mind-control;
	# don't override an active stun's State here.
	if _state != State.STUNNED:
		_change_state(State.CHASING)
	_show_affliction_marker("♥", Color(1.0, 0.4, 0.7, 1.0))
	# Pass-through collision with the player. Switching to a dedicated
	# ally layer means BOTH directions ignore each other (the player's
	# mask doesn't include this layer either) — pet doesn't push the
	# player around and the player doesn't bump into the pet. Other
	# enemies' masks also don't include this bit, so pets glide through
	# enemy crowds without body-blocking — the trade is that pets can't
	# physically wall enemies in.
	collision_layer = _LAYER_CHARMED_ALLY
	collision_mask = _CHARMED_PET_MASK
	# Puzzle resolution: clear_room_puzzle.gd one-shot connects to the
	# `died` signal to count down its kill counter. Emitting on charm
	# tells those puzzles "this enemy is no longer a threat" so a player
	# who charms every guard in a room still unlocks the door. The
	# CONNECT_ONE_SHOT means a later actual death of this pet won't
	# double-decrement the counter.
	died.emit()
	_update_health_bar()
	_refresh_tooltip_if_hovered()
	return true


## Release a charm previously applied via apply_charm. Called by the
## player when the FIFO cap evicts this enemy, when the player dies, or
## when this enemy is otherwise removed from the charm list. Safe to call
## on an already-released enemy.
func release_charm() -> void:
	if not _charmed:
		return
	_charmed = false
	_charm_target = null
	_loose_running = false
	# Restore the default collision layer + mask so the released enemy
	# behaves like a normal hostile again (player + enemies collide
	# with it, projectiles target it).
	collision_layer = _LAYER_ENEMY
	collision_mask = _DEFAULT_ENEMY_MASK
	# Marker may stay if other afflictions are still active; the next
	# _tick_afflictions cycle clears it once everything is gone.
	if _stun_remain <= 0.0 and _weaken_remain <= 0.0:
		_clear_affliction_marker()
	_update_health_bar()
	_refresh_tooltip_if_hovered()
	# Notify puzzles that this guard is hostile again. ClearRoomPuzzle
	# counted this enemy as "cleared" when charm emitted died — revived
	# un-counts it so the door re-locks until the enemy actually dies.
	if _is_alive():
		revived.emit()


## Polymath Telekinesis grab — flips the enemy into State.GRABBED so the
## TelekinesisGrab tween can own its global_position (lift then slam)
## without the AI / gravity fighting back. Returns false when the enemy
## can't be grabbed (dead, leashed, or already grabbed) so the caller
## can pick a different target.
func apply_grab() -> bool:
	if not _is_alive():
		return false
	if _state == State.RETURNING or _state == State.GRABBED:
		return false
	_change_state(State.GRABBED)
	velocity = Vector3.ZERO
	return true


## Release a Telekinesis grab. Called by the TelekinesisGrab on slam-
## landing or when the grab is cancelled (target died mid-lift). Safe
## to call on an already-released enemy.
func release_grab() -> void:
	if _state != State.GRABBED:
		return
	# Promote into STUNNED if a stun was applied during the lift (the
	# Telekinesis grab applies one for the lift duration), otherwise
	# back to IDLE so the next chase tick re-evaluates aggro normally —
	# the slam itself usually re-aggros via take_damage anyway.
	if _stun_remain > 0.0:
		_change_state(State.STUNNED)
		velocity = Vector3.ZERO
	else:
		_change_state(State.IDLE)


## Reduce outgoing damage by `magnitude` (0..1) for `duration` seconds.
## Compounds into _outgoing_damage_mult so a buffed + weakened enemy nets
## out correctly. Take the max magnitude on overlap (a fresh weak proc
## doesn't downgrade a strong active one) and the longer duration.
func apply_weaken(magnitude: float, duration: float) -> void:
	if not _is_alive() or duration <= 0.0 or magnitude <= 0.0:
		return
	if magnitude > _weaken_mult:
		_weaken_mult = clampf(magnitude, 0.0, 1.0)
	if duration > _weaken_remain:
		_weaken_remain = duration
	_show_affliction_marker("↓", Color(0.7, 0.7, 0.7, 1.0))
	_refresh_tooltip_if_hovered()


func apply_isr_mark() -> void:
	_isr_vuln_count += 1
	_show_affliction_marker("◎", Color(1.0, 0.45, 0.2, 1.0))
	_refresh_tooltip_if_hovered()


func remove_isr_mark() -> void:
	_isr_vuln_count = maxi(0, _isr_vuln_count - 1)
	if _isr_vuln_count <= 0:
		if _stun_remain <= 0.0 and not _charmed and _weaken_remain <= 0.0:
			_clear_affliction_marker()
	_refresh_tooltip_if_hovered()


# Tick stun + weaken timers. Charm has no timer — it's released externally
# by the player when capped out or on player death (see release_charm).
# Stun expiry transitions back to IDLE so the next physics frame re-
# evaluates aggro normally. Weaken expiry resets the mult.
func _tick_afflictions(delta: float) -> void:
	# Pause the stun countdown while a Telekinesis grab is active —
	# the enemy is already CC'd by GRABBED, and the stun is meant to
	# apply post-slam. release_grab promotes us into STUNNED with the
	# full duration intact.
	if _stun_remain > 0.0 and _state != State.GRABBED:
		_stun_remain -= delta
		if _stun_remain <= 0.0:
			_stun_remain = 0.0
			# Only flip out of STUNNED if we're still in it — knockback or
			# death may have already moved us out.
			if _state == State.STUNNED:
				_change_state(State.IDLE)
	# Ignite DoT. Tick at fixed intervals (smoother damage numbers than
	# per-frame), countdown decrements continuously. Damage routes
	# through take_damage so curse / vulnerability / leash multipliers
	# all apply.
	if _ignite_remain > 0.0:
		_ignite_remain -= delta
		_ignite_tick_accum += delta
		if _ignite_tick_accum >= IGNITE_TICK_INTERVAL:
			_ignite_tick_accum -= IGNITE_TICK_INTERVAL
			var tick_dmg: int = maxi(1, int(round(_ignite_dps * IGNITE_TICK_INTERVAL)))
			take_damage(tick_dmg, global_position, 0.0, 1, false)
		if _ignite_remain <= 0.0:
			_ignite_remain = 0.0
			_ignite_dps = 0.0
			_ignite_tick_accum = 0.0
	# Bleed DoT — % of max HP per second per stack, ticked at fixed
	# intervals like ignite. Independent of ignite (a target can bleed
	# AND burn) so 1H melee combo finishers stack with elemental
	# weapons cleanly.
	if _bleed_remain > 0.0 and _bleed_stacks > 0:
		_bleed_remain -= delta
		_bleed_tick_accum += delta
		if _bleed_tick_accum >= BLEED_TICK_INTERVAL:
			_bleed_tick_accum -= BLEED_TICK_INTERVAL
			var per_tick_pct: float = BLEED_HP_PCT_PER_SEC * BLEED_TICK_INTERVAL * float(_bleed_stacks)
			var tick_dmg: int = maxi(1, int(round(float(max_health) * per_tick_pct)))
			take_damage(tick_dmg, global_position, 0.0, 1, false)
		if _bleed_remain <= 0.0:
			_bleed_remain = 0.0
			_bleed_stacks = 0
			_bleed_tick_accum = 0.0
	# Re-pick the charm target every tick when the cached one is dead,
	# null, OR has become an ally (charmed by the player too). Without
	# the friendly check, a pet whose target gets charmed mid-fight
	# would keep attacking it — pet-vs-pet friendly fire. Done per-tick
	# (cheap) rather than via signal because charm targets are short-
	# lived. When no enemy is in range, leave _charm_target null — the
	# chase tick falls back to "follow player loosely" rather than
	# releasing the charm. Pets persist until killed by other enemies.
	if _charmed:
		var needs_repick := _charm_target == null or not _is_target_alive(_charm_target)
		if not needs_repick and _charm_target is PrototypeEnemy:
			if (_charm_target as PrototypeEnemy).is_player_friendly():
				needs_repick = true
		if needs_repick:
			_charm_target = _pick_nearest_other_enemy()
	if _weaken_remain > 0.0:
		_weaken_remain -= delta
		if _weaken_remain <= 0.0:
			_weaken_remain = 0.0
			_weaken_mult = 0.0
	# Clear the marker once nothing is afflicting us. Cheap to recreate on
	# the next proc; saves us tracking which affliction the marker belongs
	# to when overlapping effects clear at different times.
	if _stun_remain <= 0.0 and not _charmed and _weaken_remain <= 0.0:
		_clear_affliction_marker()


# Returns the closest LIVE non-friendly enemy other than self, or null
# if none in AGGRO_RANGE. Used by charm to pick a victim for the mind-
# controlled enemy to attack. Player-friendly (other charmed) enemies
# are skipped — pets shouldn't attack each other.
func _pick_nearest_other_enemy() -> Node3D:
	var best: Node3D = null
	var best_d2 := AGGRO_RANGE * AGGRO_RANGE
	for n in SpatialGrid.query_radius(global_position, AGGRO_RANGE, &"enemies"):
		if n == self or not (n is Node3D) or not is_instance_valid(n):
			continue
		if not _is_target_alive(n):
			continue
		# Skip allies — both my own player-friendly state (irrelevant
		# since I'm doing the picking) and any other charmed pet in range.
		if n is PrototypeEnemy and (n as PrototypeEnemy).is_player_friendly():
			continue
		var d2 := global_position.distance_squared_to((n as Node3D).global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best


# True when `target` is non-null, in-tree, has take_damage, and (for
# PrototypeEnemy) is alive. Player passes the take_damage check too so
# this works for both the normal target and the charm target.
func _is_target_alive(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target is PrototypeEnemy:
		return (target as PrototypeEnemy)._is_alive()
	return target.has_method(&"take_damage")


# Chase / attack target. For charmed pets it's the assigned hostile
# (set by _pick_nearest_other_enemy). For hostile enemies it's the
# closest THREAT — player OR any nearby player-friendly pet.
# The spatial-grid query for pets is throttled to THREAT_RETARGET_INTERVAL
# to avoid running 100 radius queries per physics frame at horde scale.
# Between re-queries the cached target is used if still valid.
const THREAT_RETARGET_INTERVAL := 0.35
var _threat_cache: Node3D = null
var _threat_retarget_t: float = 0.0

func _effective_target() -> Node3D:
	if _charmed and _is_target_alive(_charm_target):
		return _charm_target
	return _pick_closest_threat()


func _pick_closest_threat() -> Node3D:
	# Fast path: use cached target when valid and retarget timer hasn't fired.
	if _threat_retarget_t > 0.0 and _threat_cache != null and is_instance_valid(_threat_cache):
		if _threat_cache is PrototypeEnemy:
			if (_threat_cache as PrototypeEnemy)._is_alive() and (_threat_cache as PrototypeEnemy).is_player_friendly():
				return _threat_cache
		elif _threat_cache.has_method(&"take_damage"):
			return _threat_cache
	# Full re-query: find the closest threat (player or charmed pet).
	_threat_retarget_t = THREAT_RETARGET_INTERVAL
	var best: Node3D = null
	var best_d2 := INF
	if _player_ref != null and is_instance_valid(_player_ref):
		best = _player_ref
		best_d2 = global_position.distance_squared_to(_player_ref.global_position)
	for n in SpatialGrid.query_radius(global_position, AGGRO_RANGE, &"enemies"):
		if n == self or not (n is PrototypeEnemy) or not is_instance_valid(n):
			continue
		var pe: PrototypeEnemy = n
		if not pe.is_player_friendly():
			continue
		if not pe._is_alive():
			continue
		var d2 := global_position.distance_squared_to(pe.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = pe
	_threat_cache = best
	return best


# Floating glyph above the head, similar to the curse marker but for
# Doomsayer afflictions. Re-used across the three effect types — calling
# again with a different glyph just replaces the label so a stunned-then-
# weakened enemy reads the latest application.
func _show_affliction_marker(glyph: String, color: Color) -> void:
	_clear_affliction_marker()
	var lbl := Label3D.new()
	lbl.text = glyph
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0014
	lbl.font_size = 32
	lbl.outline_size = 8
	lbl.modulate = color
	lbl.outline_modulate = Color(0.05, 0.0, 0.1, 1.0)
	# Stack just above the curse marker so an enemy that's both cursed and
	# afflicted shows both glyphs without overlap.
	lbl.position = Vector3(0.0, 2.7, 0.0)
	add_child(lbl)
	_affliction_marker = lbl


func _clear_affliction_marker() -> void:
	if _affliction_marker != null and is_instance_valid(_affliction_marker):
		_affliction_marker.queue_free()
	_affliction_marker = null


## Single point of state transitions. Currently a thin setter; entry/exit
## hooks (e.g. clearing horizontal velocity on enter-CASTING, releasing the
## hit-tween on enter-DEAD) live at the call sites for now. If hook count
## grows beyond a couple per state, switch to a dispatch table here.
func _change_state(new_state: State) -> void:
	if _state == new_state:
		return
	_state = new_state
	if new_state == State.IDLE:
		_hit_leash_extend_sq = 0.0


func _play_hit_squash() -> void:
	if visual == null or not _is_alive():
		return
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	# HIT_SQUASH_SCALE is a multiplier on the rest pose, not an absolute
	# size — multiply componentwise so a 1.5x boss squashes to (1.65,
	# 1.275, 1.65) instead of being slammed down to (1.10, 0.85, 1.10)
	# and ending the tween at Vector3.ONE (which permanently shrunk it).
	var squash := Vector3(
		_rest_visual_scale.x * HIT_SQUASH_SCALE.x,
		_rest_visual_scale.y * HIT_SQUASH_SCALE.y,
		_rest_visual_scale.z * HIT_SQUASH_SCALE.z,
	)
	visual.scale = _rest_visual_scale
	_hit_tween = create_tween()
	_hit_tween.tween_property(visual, "scale", squash, HIT_SQUASH_IN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(visual, "scale", _rest_visual_scale, HIT_SQUASH_OUT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

const _HP_BAR_HOSTILE := Color(1.0, 0.28, 0.32, 1.0)
const _HP_BAR_FRIENDLY := Color(0.30, 1.0, 0.45, 1.0)

func _update_health_bar() -> void:
	if health_bar == null:
		return
	var ratio := clampf(float(_health) / float(max_health), 0.0, 1.0)
	health_bar.visible = _is_alive() and ratio < 1.0
	health_bar.set_instance_shader_parameter(&"fill_ratio", ratio)
	# Charmed pets fight FOR the player; their bar reads green so the
	# player can scan a knot of bodies and tell allies from hostiles
	# without inspecting each one.
	health_bar.set_instance_shader_parameter(&"fill_color",
		_HP_BAR_FRIENDLY if _charmed else _HP_BAR_HOSTILE)

func _physics_process(delta: float) -> void:
	if _is_remote_enemy():
		_remote_physics_process()
		return
	if _state == State.DEAD:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_threat_retarget_t = maxf(0.0, _threat_retarget_t - delta)

	_crouch_probe_t -= delta
	if _crouch_probe_t <= 0.0:
		_crouch_probe_t = CROUCH_PROBE_INTERVAL
		_update_crouch_state()
	_jump_cooldown_remain = maxf(0.0, _jump_cooldown_remain - delta)
	_damage_buff_remain = maxf(0.0, _damage_buff_remain - delta)
	if _damage_buff_remain <= 0.0:
		_damage_buff_mult = 0.0
	if enemy_class != null and enemy_class.support_role != EnemyClass.SupportRole.NONE:
		_support_tick_t -= delta
		if _support_tick_t <= 0.0:
			_support_tick_t = enemy_class.support_interval
			_emit_support()
	# Tick per-skill cooldowns.
	for skill: EnemySkill in _skill_cooldowns:
		if _skill_cooldowns[skill] > 0.0:
			_skill_cooldowns[skill] = maxf(0.0, _skill_cooldowns[skill] - delta)
	# Tick self-buff decay.
	if _self_buff_remain > 0.0:
		_self_buff_remain -= delta
		if _self_buff_remain <= 0.0:
			_self_buff_damage_mult = 1.0
			_self_buff_speed_mult = 1.0
	_tick_curse(delta)
	_tick_afflictions(delta)

	# Floor-snap is suppressed during JUMPING so the takeoff impulse set by
	# _start_jump (which runs from the agent's link_reached signal AFTER our
	# physics_process this frame) survives into the next frame's gravity
	# pass instead of being zeroed by is_on_floor(). GRABBED also skips
	# gravity — global_position.y is owned by the TelekinesisGrab tween.
	if _state == State.GRABBED:
		velocity = Vector3.ZERO
	elif _state == State.JUMPING or not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	# State dispatch — exactly one branch runs each tick. Add new behaviours
	# by extending the State enum and adding a branch here, not by sneaking
	# in another flag check.
	match _state:
		State.KNOCKBACK:
			_tick_knockback(delta)
		State.CASTING:
			# Held in place by the windup; _cast_attack's await transitions
			# us back to CHASING when the swing resolves.
			velocity.x = 0.0
			velocity.z = 0.0
		State.JUMPING:
			_tick_jump(delta)
		State.STUNNED:
			# Frozen — no movement, no aim. _tick_afflictions transitions us
			# back to IDLE when the stun timer drains.
			velocity.x = 0.0
			velocity.z = 0.0
			_want_dir = Vector3.ZERO
		State.GRABBED:
			# Lifted by Telekinesis — TelekinesisGrab owns global_position.
			# Skip move_and_slide and AI entirely; release_grab() is what
			# returns us to IDLE.
			_want_dir = Vector3.ZERO
			return
		State.IDLE, State.CHASING, State.RETURNING:
			# All three share the chase-tick logic — it inspects state and
			# routes between them (proximity aggro, leash trip, return arrival).
			_chase_tick()

	# Capture wished horizontal motion before slide consumes it (see StepUp).
	var wish_horiz := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	# Auto step-up over short obstacles. 0.3m is slightly tighter than the
	# player's 0.4m so enemies can't path up onto things the player wouldn't
	# expect them to (decorative crates, etc.) — still enough for pit fences.
	StepUp.try(self, wish_horiz, 0.3, delta)

	# Animation update — CASTING and KNOCKBACK own their own clips. JUMPING
	# plays the airborne pose. CROUCHING swaps in the crouch idle/walk pair.
	# Otherwise we fall back to the standard idle/run.
	# Guard: if the enemy died mid-tick (e.g. curse-expire auto-shot killed
	# it during _tick_curse above), skip the animation update so _die()'s
	# death clip / fallback pose isn't overwritten by the run/idle fallthrough.
	if _state == State.DEAD:
		return
	var moving := _want_dir.length_squared() > 0.01
	match _state:
		State.CASTING, State.KNOCKBACK:
			pass
		State.JUMPING:
			_play_anim(ANIM_JUMP)
		State.STUNNED, State.GRABBED:
			# Idle clip while frozen / lifted — no rigs have a dedicated
			# stun or grab pose. Freezing on the current frame would lock
			# unnatural mid-motion poses (mid-stride, mid-attack windup).
			_play_anim(ANIM_IDLE)
		_:
			if _crouching:
				_play_anim(ANIM_CROUCH_RUN if moving else ANIM_CROUCH_IDLE)
			else:
				_play_anim(ANIM_RUN if moving else ANIM_IDLE)
			if moving:
				_face_direction(_want_dir)

	# Authority writes net_* vars each tick — the MultiplayerSynchronizer
	# broadcasts them to clients, which read them in _remote_physics_process.
	net_health = _health
	net_max_health = max_health
	net_state = _state as int


## Client-side tick for remote enemies (non-authority in MP). The
## MultiplayerSynchronizer feeds global_position and Visual.rotation
## directly; this method only handles health bar + animation derived
## from the synced net_state.
func _remote_physics_process() -> void:
	var synced_state: int = net_state
	# Detect death transition on the client side.
	if synced_state == State.DEAD:
		if _state != State.DEAD:
			_state = State.DEAD
			set_physics_process(false)
			set_deferred(&"collision_layer", 0)
			set_deferred(&"collision_mask", 0)
			if collision != null:
				collision.set_deferred(&"disabled", true)
			if health_bar != null:
				health_bar.visible = false
			_play_anim(ANIM_DEATH, 1.0)
		return
	_state = synced_state as State
	# Update health bar from synced values.
	_health = net_health
	max_health = net_max_health
	_update_health_bar()
	# Animation from synced state — simplified, no crouch/jump on client yet.
	match _state:
		State.CASTING, State.KNOCKBACK:
			pass
		State.JUMPING:
			_play_anim(ANIM_JUMP)
		State.STUNNED, State.GRABBED:
			_play_anim(ANIM_IDLE)
		_:
			# Infer movement from position delta — the synchronizer writes
			# global_position directly; velocity isn't meaningful on clients.
			var delta_pos := global_position - _net_prev_pos
			delta_pos.y = 0.0
			var moving := delta_pos.length_squared() > 0.0001
			_play_anim(ANIM_RUN if moving else ANIM_IDLE)
	_net_prev_pos = global_position


# Quadratic ease-out: full impulse at the moment of impact, near-zero by the
# end of the window. When the timer drains, hand control back to the chase
# tick — knockback always comes from take_damage which already aggro'd us.
func _tick_knockback(delta: float) -> void:
	var t: float = _knockback_remain / KNOCKBACK_DURATION
	var falloff: float = t * t
	velocity.x = _knockback_vel.x * falloff
	velocity.z = _knockback_vel.z * falloff
	_knockback_remain -= delta
	_want_dir = Vector3.ZERO
	if _knockback_remain <= 0.0:
		# Resume STUNNED if stun time remains — without this a knockback
		# hit on a stunned enemy permanently transitioned them to CHASING
		# (the stun timer kept ticking but the state had moved on),
		# which read in playtest as "stuns are ignored when in attack
		# range". Knockback still applies to a stunned enemy; the stun
		# just survives it.
		if _stun_remain > 0.0:
			_change_state(State.STUNNED)
		else:
			_change_state(State.CHASING)

## Force this enemy into aggro and alert nearby enemies. No-op if we're
## already engaged or already returning (aggro shouldn't pull a leashed
## enemy back into the fight — KEEP_CHASE_PLAYER_RANGE_SQ in _chase_tick
## handles re-engagement when the player closes during a return).
## depth caps the cascade so aggro doesn't chain across the entire level.
func aggro(depth: int = 0) -> void:
	if _state == State.CHASING or _state == State.CASTING or _state == State.JUMPING:
		return
	if _state == State.RETURNING or _state == State.DEAD:
		return
	# KNOCKBACK / STUNNED / GRABBED resolve to CHASING through their own
	# tick functions — don't cut those animations short by force-swapping
	# state here. The pack still gets alerted via the cascade below; this
	# enemy will engage when its current animation lapses.
	if _state != State.KNOCKBACK and _state != State.STUNNED and _state != State.GRABBED:
		_change_state(State.CHASING)
	if depth >= MAX_AGGRO_CASCADE:
		return
	for enode: Node3D in SpatialGrid.query_radius(global_position, GROUP_AGGRO_RANGE, &"enemies"):
		if enode == self:
			continue
		if enode.has_method(&"aggro"):
			enode.aggro(depth + 1)


# Drives IDLE / CHASING / RETURNING — _physics_process routes all three
# here. Each branch may transition between them; CASTING and JUMPING are
# entered from CHASING via _cast_attack / _on_link_reached.
func _chase_tick() -> void:
	_want_dir = Vector3.ZERO
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group(&"player") as Node3D
	var player := _player_ref
	if player == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	# Doomsayer charm: while active the enemy chases / attacks `target`
	# (nearest other enemy) instead of the player. Leash + auto-aggro still
	# read player position so the charmed enemy can't be lured past the
	# leash and the player de-engaging from a charmed enemy still works
	# normally once the timer drains.
	var target: Node3D = _effective_target()
	if target == null:
		target = player

	# Leash logic — runs even in IDLE (so an idle enemy at edge of leash
	# range can't be tricked into RETURNING). Player-close suppression keeps
	# the leash from tripping mid-fight; player-close re-engage prevents the
	# leashed enemy from getting a free walk past the player.
	var spawn_dist_sq := global_position.distance_squared_to(_spawn_position)
	var player_dist_sq := global_position.distance_squared_to(player.global_position)
	var player_close := player_dist_sq <= KEEP_CHASE_PLAYER_RANGE_SQ
	var effective_leash_sq := maxf(MAX_CHASE_FROM_SPAWN_SQ, _hit_leash_extend_sq)
	if _state == State.CHASING and spawn_dist_sq > effective_leash_sq and not player_close:
		_hit_leash_extend_sq = 0.0
		_change_state(State.RETURNING)
		_return_stuck_timer = 0.0
		_return_last_dist_sq = spawn_dist_sq
	elif _state == State.RETURNING and player_close:
		_change_state(State.CHASING)

	if _state == State.RETURNING:
		_tick_return(spawn_dist_sq)
		return

	# Anti-leash teleport for charmed pets — snap to the player when
	# we've drifted too far (lured by a target across the map, lost
	# behind unwalkable geometry, etc.). Generous distance because the
	# pet has its own AI and should normally keep up. Drones use ~6m;
	# pets are big-bodied with pathfinding so they get more rope.
	if _charmed and player_dist_sq > _FOLLOW_TELEPORT_DISTANCE * _FOLLOW_TELEPORT_DISTANCE:
		var snap_pos := player.global_position
		var bearing := randf() * TAU
		snap_pos.x += cos(bearing) * _FOLLOW_DISTANCE_TARGET
		snap_pos.z += sin(bearing) * _FOLLOW_DISTANCE_TARGET
		global_position = snap_pos
		velocity = Vector3.ZERO
		_want_dir = Vector3.ZERO
		# Re-pick a target after teleport — the old one may now be far
		# enough that following it would just trigger another teleport.
		_charm_target = _pick_nearest_other_enemy()
		return

	# Charmed pet with no live enemy target falls back to "loosely follow
	# player" — wander near them, don't attack, don't aggro. _tick_afflictions
	# re-picks _charm_target each tick, so as soon as a real enemy walks
	# into AGGRO_RANGE the pet switches to that target on the next chase
	# tick. Until then this branch keeps them alive and visible without
	# them attacking the player or each other.
	if _charmed and (_charm_target == null or not _is_target_alive(_charm_target)):
		if _state == State.IDLE:
			_change_state(State.CHASING)
		_follow_player_loose(player)
		return

	# IDLE & CHASING share the proximity-aggro check — an IDLE enemy that
	# the player walks toward should wake up the same way a previously-engaged
	# one would re-engage.
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	# Single LoS lookup serves both the aggro and attack-initiation checks
	# below. The damage-time check inside _cast_attack re-queries on purpose,
	# since it runs after the windup await. While charmed, skip the gate —
	# we don't have a cached LoS to the charm target and a temporary debuff
	# isn't worth a per-frame raycast.
	var charmed := target != player
	var has_los := true if charmed else LosCuller.has_los_to_player(self)
	if not charmed and _state == State.IDLE and dist <= AGGRO_RANGE and has_los:
		aggro()
	elif charmed and _state == State.IDLE:
		# Charm during IDLE (or right after a stun ended) — flip into
		# CHASING directly without going through the aggro cascade so the
		# charmed enemy doesn't accidentally rope its allies into chasing
		# itself via the proximity wake.
		_change_state(State.CHASING)

	if _state != State.CHASING or dist < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Ranged enemies kite to ~ranged_kite_distance: too close → backpedal,
	# in band → hold + fire when ready, too far → chase. Melee enemies skip
	# this branch and fall through to the close-and-swing path below.
	# Charmed enemies always melee (see _cast_attack), so they bypass kite
	# too — otherwise they'd backpedal from the very target they're charmed
	# to attack.
	# Special skill check — runs before the basic attack for both melee and
	# ranged. _pick_skill filters by range, cooldown, and LoS internally.
	var special := _pick_skill(dist, has_los)
	if special != null:
		_cast_skill(target, to_target / dist, special)
		return

	if _is_ranged() and not charmed:
		var kite := _ranged_kite_distance()
		if dist <= _attack_range() and _attack_cd <= 0.0 and has_los:
			_holding_position = false
			_cast_attack(target, to_target / dist)
			return
		if dist < kite * 0.7:
			# Backpedal — direct vector, slower than chase. We don't pathfind
			# the retreat because navmesh wants to hug walls; a noisy bumpy
			# straight-line retreat reads as "skittish ranged enemy" and is
			# fine. Bumping into walls is the player's intended advantage.
			_holding_position = false
			var away := -to_target / dist
			_want_dir = away
			var back_speed := CHASE_SPEED * 0.55 * _crouch_speed_factor() * _affix_move_speed_mult() * _self_buff_speed_mult
			velocity.x = away.x * back_speed
			velocity.z = away.z * back_speed
			return
		# Hold band with hysteresis: enter when within kite distance, stay
		# until well past it. Without the second clause the enemy oscillates
		# between hold and chase whenever the player drifts a few cm across
		# the kite boundary — which read in playtest as a stutter step.
		if dist <= kite or (_holding_position and dist <= kite + RANGED_KITE_HYSTERESIS):
			_holding_position = true
			_want_dir = Vector3.ZERO
			velocity.x = 0.0
			velocity.z = 0.0
			return
		# else: too far, fall through to navmesh chase below

	# Aggro'd melee (or charmed). In attack range → swing if ready, otherwise
	# stand and face. Hysteresis on the hold→chase transition keeps the enemy
	# planted for a small buffer past attack range so light drift (knockback,
	# player movement, physics) doesn't trigger a re-chase. Holding while on
	# cooldown is what stops melee enemies from constantly pushing into the
	# target between swings; the buffer is what stops boundary oscillation.
	elif (dist <= _attack_range() or (_holding_position and dist <= _attack_range() + ATTACK_RANGE_HYSTERESIS)) and has_los:
		if dist <= _attack_range() and _attack_cd <= 0.0:
			_holding_position = false
			_cast_attack(target, to_target / dist)
		else:
			_holding_position = true
			_face_direction(to_target / dist)
			_want_dir = Vector3.ZERO
			velocity.x = 0.0
			velocity.z = 0.0
		return

	# Reaching the chase block means the enemy is meaningfully outside
	# attack/kite range — explicitly drop the hold flag so the next
	# in-range entry uses the strict threshold, not the buffered one.
	_holding_position = false

	# Pathfind via NavigationAgent — routes around walls and pit edges
	# instead of charging straight at the target. Falls back to direct
	# vector chase when no nav agent (legacy scene), no map (navmesh
	# bake hasn't finished yet), or the agent is already on top of the
	# target.
	var dir := to_target / dist
	if _nav_agent != null and _nav_agent.get_navigation_map().is_valid():
		_nav_agent.target_position = target.global_position
		if not _nav_agent.is_navigation_finished():
			var next_pos := _nav_agent.get_next_path_position()
			var nav_dir := next_pos - global_position
			nav_dir.y = 0.0
			if nav_dir.length_squared() > 0.0001:
				dir = nav_dir.normalized()
	_want_dir = dir
	var chase_speed := _movement_speed_base() * _crouch_speed_factor() * _affix_move_speed_mult() * _self_buff_speed_mult
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed


# Charmed pet idle behaviour — wander loosely around the player when no
# enemy target is in range. The pet stays in CHASING state but doesn't
# attack and doesn't aggro. Movement holds a comfortable follow distance:
# move toward the player when too far, stop when close, no backpedal.
# _tick_afflictions re-picks _charm_target each tick, so as soon as a
# real enemy walks into AGGRO_RANGE the pet switches over.
#
# Anti-leashing: if the player walks far enough away that the pet would
# get hopelessly stuck behind walls / nav obstacles, snap the pet to the
# player. Distance is far higher than drones (which use ~6m) because the
# pet has its own AI / pathfinding that should usually keep up — the
# teleport is a hard fallback for genuinely lost pets, not the primary
# follow mechanism.
const _FOLLOW_DISTANCE_TARGET := 3.0
const _FOLLOW_DISTANCE_TOLERANCE := 1.0
const _FOLLOW_TELEPORT_DISTANCE := 25.0
# Spring follow tuning. Speed scales with the distance excess past
# _FOLLOW_DISTANCE_TARGET so the pet ramps in/out of motion smoothly
# instead of binary-snapping start/stop at the band edge — the
# previous step-function caused the run animation to flicker as the
# pet crossed the threshold every other frame. Hysteresis on the
# moving flag prevents the residual flicker right at the speed
# threshold (start running at >=_LOOSE_RUN_START_SPEED, stop running
# below _LOOSE_RUN_STOP_SPEED — different values create the deadband).
const _FOLLOW_SPRING_GAIN := 5.0
const _LOOSE_RUN_START_SPEED := 1.0
const _LOOSE_RUN_STOP_SPEED := 0.3
var _loose_running: bool = false


# Base movement speed before crouch / affix / per-tick modifiers. For
# charmed pets this returns the player's current move_speed so they can
# keep up at run pace. Non-charmed enemies use the normal CHASE_SPEED
# constant. Called by _chase_tick (chasing an enemy or returning to
# spawn) and _follow_player_loose (loose pet follow).
func _movement_speed_base() -> float:
	if _charmed and _player_ref != null and is_instance_valid(_player_ref) and _player_ref is PrototypePlayer:
		return (_player_ref as PrototypePlayer).move_speed
	if is_boss:
		return CHASE_SPEED * BOSS_SPEED_MULT
	return CHASE_SPEED


# Crouch speed factor — separate for charmed pets vs. hostiles. Pets
# borrow the player's CROUCH_SPEED_FACTOR (0.45) so they slow down the
# same amount as the player they're following, which reads as "the pet
# is moving with me through the tunnel" rather than overtaking the
# crouched player at the gentler enemy mult (0.6). Hostiles keep the
# enemy mult so the player can still kite them through tunnels at a
# meaningful disadvantage.
func _crouch_speed_factor() -> float:
	if not _crouching:
		return 1.0
	if _charmed:
		return PrototypePlayer.CROUCH_SPEED_FACTOR
	return CROUCH_SPEED_MULT


func _follow_player_loose(player: Node3D) -> void:
	# Anti-leash teleport runs in _chase_tick before this branch, so by
	# the time we get here the pet is guaranteed to be within
	# _FOLLOW_TELEPORT_DISTANCE of the player.
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist < 0.001:
		_want_dir = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		_loose_running = false
		return
	var dir := to_player / dist
	# Spring-style speed scaling — pet accelerates when it falls
	# behind, decelerates as it returns to the comfort band. Negative
	# excess (already inside the band) clamps to 0; pet doesn't
	# back off when too close.
	var max_speed := _movement_speed_base() * 1.2 * _crouch_speed_factor() * _affix_move_speed_mult()
	var excess := dist - _FOLLOW_DISTANCE_TARGET
	var speed := clampf(excess * _FOLLOW_SPRING_GAIN, 0.0, max_speed)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	# Hysteresis on the run/idle flag so the animation doesn't strobe
	# at the exact speed threshold — start running once we cross the
	# higher threshold, only stop once we drop below the lower one.
	if _loose_running:
		if speed < _LOOSE_RUN_STOP_SPEED:
			_loose_running = false
	else:
		if speed > _LOOSE_RUN_START_SPEED:
			_loose_running = true
	if _loose_running:
		_want_dir = dir
		_face_direction(dir)
	else:
		_want_dir = Vector3.ZERO


# Walks the enemy back to its spawn position. Transitions to IDLE on arrival.
func _tick_return(spawn_dist_sq: float) -> void:
	if spawn_dist_sq <= RETURN_THRESHOLD_SQ:
		_change_state(State.IDLE)
		velocity.x = 0.0
		velocity.z = 0.0
		_return_stuck_timer = 0.0
		return
	# Stuck detection: if the enemy hasn't closed enough distance toward
	# spawn within RETURN_STUCK_TIMEOUT, teleport it home. Catches enemies
	# wedged against nav-mesh edges, doorways, or other geometry.
	var progress := _return_last_dist_sq - spawn_dist_sq
	_return_last_dist_sq = spawn_dist_sq
	if progress < RETURN_STUCK_PROGRESS_SQ * get_physics_process_delta_time():
		_return_stuck_timer += get_physics_process_delta_time()
		if _return_stuck_timer >= RETURN_STUCK_TIMEOUT:
			global_position = _spawn_position
			velocity = Vector3.ZERO
			_change_state(State.IDLE)
			_return_stuck_timer = 0.0
			return
	else:
		_return_stuck_timer = 0.0
	var to_spawn := _spawn_position - global_position
	to_spawn.y = 0.0
	var sd := to_spawn.length()
	if sd < 0.001:
		_change_state(State.IDLE)
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var spawn_dir := to_spawn / sd
	_want_dir = spawn_dir
	var return_speed := CHASE_SPEED * _crouch_speed_factor() * _affix_move_speed_mult()
	velocity.x = spawn_dir.x * return_speed
	velocity.z = spawn_dir.z * return_speed

# Shape-cast a stand-height capsule overhead. If anything's there we can't
# stand — drop into crouch. The probe runs on CROUCH_PROBE_INTERVAL cadence
# and self-excludes so the cast doesn't trip on this body's own collider.
func _update_crouch_state() -> void:
	if not can_crouch or _stand_test_shape == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_test_shape
	query.collision_mask = 1  # World layer — walls, ceilings, floors
	query.exclude = [get_rid()]
	# Real low ceiling at the current position keeps us crouched while we're
	# underneath. Lookahead handles the BEFORE-bumping-the-slab case.
	var blocked := _is_real_low_ceiling(query, global_position, space)
	if not blocked and _want_dir.length_squared() > 0.01:
		var forward_pos := global_position + _want_dir.normalized() * CROUCH_PROBE_LOOKAHEAD
		blocked = _is_real_low_ceiling(query, forward_pos, space)
	if blocked != _crouching:
		_set_crouch(blocked)


# A position has a "real low ceiling" iff:
#   - overhead is blocked (something in y≈0.95-1.65)
#   - body height is clear (nothing in y≈0.05-0.75)
# Both blocked means a wall / closed door — crouching doesn't help, and
# committing to the crouch leaves the enemy waddling uselessly into the
# obstacle (which is what was happening at doorways before this check).
func _is_real_low_ceiling(query: PhysicsShapeQueryParameters3D, base: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	if not _probe_at(query, base, CROUCH_PROBE_CENTER_Y, space):
		return false
	return not _probe_at(query, base, CROUCH_BODY_PROBE_CENTER_Y, space)


func _probe_at(query: PhysicsShapeQueryParameters3D, base: Vector3, y_center: float, space: PhysicsDirectSpaceState3D) -> bool:
	query.transform = Transform3D(Basis.IDENTITY, base + Vector3(0.0, y_center, 0.0))
	return not space.intersect_shape(query, 1).is_empty()

func _set_crouch(value: bool) -> void:
	_crouching = value
	if collision == null:
		return
	var shape := collision.shape as CapsuleShape3D
	if shape == null:
		return
	shape.height = CROUCH_HEIGHT if value else STAND_HEIGHT
	collision.position.y = shape.height * 0.5 + CAPSULE_BOTTOM_Y


# Fires when the navmesh routes us across a NavigationLink3D — pit_builder
# places one between every adjacent pillar pair. Only a CHASING enemy on the
# floor can launch; crouched / mid-jump / casting / returning agents skip
# the link (the navmesh will replan once they're free).
func _on_link_reached(details: Dictionary) -> void:
	if _state != State.CHASING or _crouching:
		return
	if not can_jump:
		return
	if _jump_cooldown_remain > 0.0:
		return
	if not is_on_floor():
		return
	var exit_pos: Vector3 = details.get(&"link_exit_position", Vector3.ZERO)
	if exit_pos == Vector3.ZERO:
		return
	_start_jump(exit_pos)


# Launch impulse toward the link exit. Roll for a miss — failed jumps
# undershoot horizontally so the enemy lands short of the next pillar and
# falls into the pit (the per-pit kill area handles the cleanup).
func _start_jump(target: Vector3) -> void:
	var horiz := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var horiz_dist := horiz.length()
	if horiz_dist < 0.001:
		return
	var horiz_dir := horiz / horiz_dist
	var miss := randf() < JUMP_MISS_CHANCE
	var reach_factor := JUMP_MISS_DIST_FACTOR if miss else 1.0
	# Solve for the velocity that covers `horiz_dist * reach_factor` over
	# JUMP_AIRTIME under our GRAVITY. Vertical impulse balances airtime so
	# the enemy peaks mid-flight regardless of horizontal distance.
	var vh := (horiz_dist * reach_factor) / JUMP_AIRTIME
	var vv := 0.5 * GRAVITY * JUMP_AIRTIME
	velocity = horiz_dir * vh
	velocity.y = vv
	_change_state(State.JUMPING)
	_jump_t = 0.0
	_face_direction(horiz_dir)


func _tick_jump(delta: float) -> void:
	_jump_t += delta
	# Velocity persists from the takeoff impulse; gravity (applied earlier
	# this frame) handles the vertical arc. We only need to detect landing.
	if _jump_t >= JUMP_LANDING_GRACE and is_on_floor():
		_jump_t = 0.0
		_jump_cooldown_remain = JUMP_COOLDOWN
		_change_state(State.CHASING)

# Pick the highest-priority special skill that's in range and off cooldown.
# Returns null when no special is ready → caller falls back to basic attack.
# Charmed enemies skip specials entirely (force melee via _cast_attack).
func _pick_skill(dist: float, has_los: bool) -> EnemySkill:
	if _charmed or _special_skills.is_empty():
		return null
	for skill: EnemySkill in _special_skills:
		if skill == null:
			continue
		if _skill_cooldowns.get(skill, 0.0) > 0.0:
			continue
		if skill.targeting_mode == EnemySkill.TargetingMode.SELF_BUFF:
			# Self-buff doesn't need range or LoS — just cooldown.
			if _self_buff_remain <= 0.0:
				return skill
			continue
		if dist > skill.skill_range:
			continue
		if not has_los:
			continue
		return skill
	return null


# Execute a special skill. Routes by targeting_mode — each branch mirrors
# the established cast pattern: enter CASTING → indicator → await windup →
# bail if state changed → resolve damage → back to CHASING.
func _cast_skill(target: Node3D, aim: Vector3, skill: EnemySkill) -> void:
	_skill_cooldowns[skill] = skill.cooldown
	match skill.targeting_mode:
		EnemySkill.TargetingMode.SINGLE_CONE:
			_cast_skill_cone(target, aim, skill)
		EnemySkill.TargetingMode.AOE_RADIAL:
			_cast_skill_radial(target, skill)
		EnemySkill.TargetingMode.PROJECTILE:
			_cast_skill_projectile(target, aim, skill)
		EnemySkill.TargetingMode.SELF_BUFF:
			_cast_skill_self_buff(skill)


func _cast_skill_cone(target: Node3D, aim: Vector3, skill: EnemySkill) -> void:
	_change_state(State.CASTING)
	_attack_cd = _attack_cooldown()
	velocity.x = 0.0
	velocity.z = 0.0
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.2)
	CombatVisuals.spawn_cone(self, aim, skill.skill_range, skill.cone_deg, skill.wind_up)
	var gen := _generation
	await get_tree().create_timer(skill.wind_up).timeout
	if not is_inside_tree() or _generation != gen or _state != State.CASTING:
		return
	# Weapon-matched hit VFX on impact — same routing as _cast_melee_attack.
	var wid: StringName = enemy_class.weapon_id if enemy_class != null else &""
	if wid == &"blade":
		CombatVisuals.spawn_blade_slash(self, aim, skill.skill_range, skill.cone_deg)
	elif wid == &"sledgehammer":
		CombatVisuals.spawn_hit_cone(self, aim, skill.skill_range, skill.cone_deg)
		CombatVisuals.spawn_hammer_impact(self)
	else:
		CombatVisuals.spawn_hit_cone(self, aim, skill.skill_range, skill.cone_deg)
	WeaponSounds.play_fire(wid, global_position)
	_change_state(State.CHASING)
	if not is_instance_valid(target):
		return
	var to_p: Vector3 = target.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist > skill.skill_range or dist < 0.001:
		return
	var half_cos := cos(deg_to_rad(skill.cone_deg * 0.5))
	if aim.dot(to_p / dist) < half_cos:
		return
	if target is PrototypePlayer and not LosCuller.has_los_to_player(self):
		return
	if target.has_method(&"take_damage"):
		var dmg := int(round(float(_attack_damage) * skill.damage_mult * _outgoing_damage_mult()))
		target.take_damage(dmg, global_position, skill.knockback)


func _cast_skill_radial(target: Node3D, skill: EnemySkill) -> void:
	_change_state(State.CASTING)
	_attack_cd = _attack_cooldown()
	velocity.x = 0.0
	velocity.z = 0.0
	_play_anim(ANIM_ATTACK, 1.0)
	CombatVisuals.spawn_radial(self, skill.aoe_radius, skill.wind_up)
	var gen := _generation
	await get_tree().create_timer(skill.wind_up).timeout
	if not is_inside_tree() or _generation != gen or _state != State.CASTING:
		return
	_change_state(State.CHASING)
	# AoE hits everything in radius via SpatialGrid. For enemies, that means
	# the player (or other enemies if charmed).
	var target_group: StringName = &"enemies" if _charmed else &"player"
	for n: Node in SpatialGrid.query_radius(global_position, skill.aoe_radius, target_group):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if not n.has_method(&"take_damage"):
			continue
		if n == self:
			continue
		# When charmed, we query &"enemies" — skip fellow charmed allies.
		# When hostile, we query &"player" — the player is always a valid target.
		if _charmed and n is PrototypeEnemy and (n as PrototypeEnemy).is_player_friendly():
			continue
		var dmg := int(round(float(_attack_damage) * skill.damage_mult * _outgoing_damage_mult()))
		var kb_dir := (n as Node3D).global_position - global_position
		kb_dir.y = 0.0
		if kb_dir.length_squared() > 0.001:
			kb_dir = kb_dir.normalized()
		n.take_damage(dmg, global_position, skill.knockback)


func _cast_skill_projectile(target: Node3D, aim: Vector3, skill: EnemySkill) -> void:
	_change_state(State.CASTING)
	_attack_cd = _attack_cooldown()
	velocity.x = 0.0
	velocity.z = 0.0
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.2)
	var gen := _generation
	await get_tree().create_timer(skill.wind_up).timeout
	if not is_inside_tree() or _generation != gen or _state != State.CASTING:
		return
	_change_state(State.CHASING)
	if not is_instance_valid(target):
		return
	if not LosCuller.has_los_to_player(self):
		return
	var burst: int = skill.burst_count if skill.burst_count > 1 else 1
	var burst_delay: float = skill.burst_delay if skill.burst_delay > 0.0 else 0.1
	for burst_i in burst:
		if burst_i > 0:
			await get_tree().create_timer(burst_delay).timeout
			if not is_inside_tree() or _generation != gen or not _is_alive():
				return
			if not is_instance_valid(target):
				return
		# Re-aim at target's current position (they may have strafed during windup).
		# Full 3D aim from enemy chest to target chest.
		var origin := global_position + Vector3(0.0, 1.4, 0.0)
		var to_p: Vector3 = (target.global_position + Vector3(0.0, 1.0, 0.0)) - origin
		var dist := to_p.length()
		if dist < 0.001:
			return
		var center_aim := to_p / dist
		_face_direction(Vector3(center_aim.x, 0.0, center_aim.z).normalized())
		if skill.projectile_count <= 1:
			_spawn_skill_projectile(center_aim, skill)
		else:
			# Multi-shot: symmetric spread around center aim.
			var spread_rad := deg_to_rad(skill.projectile_spread_deg)
			var count := skill.projectile_count
			var half := (count - 1) * 0.5
			for i in count:
				var offset_angle := (float(i) - half) * spread_rad
				var rotated_aim := center_aim.rotated(Vector3.UP, offset_angle)
				_spawn_skill_projectile(rotated_aim, skill)


func _spawn_skill_projectile(aim: Vector3, skill: EnemySkill) -> void:
	if skill.projectile_scene == null:
		# Fallback: use the class's projectile scene if the skill doesn't have one.
		if enemy_class != null and enemy_class.projectile_scene != null:
			_spawn_enemy_projectile(aim)
		return
	var proj: PrototypeProjectile = EntityPool.acquire(skill.projectile_scene)
	if proj == null:
		return
	proj.target_group = &"player"
	proj.direction = _apply_enemy_aim_spread(aim)
	proj.speed = skill.projectile_speed
	proj.max_range = skill.projectile_max_range
	proj.knockback_strength = skill.knockback
	proj.source_position = global_position
	var dmg := int(round(float(_attack_damage) * skill.damage_mult * _outgoing_damage_mult()))
	proj.damage_min = dmg
	proj.damage_max = dmg
	proj.damage_mult = 1.0
	proj.accuracy = 1.0
	proj.crit_chance = 0.0
	get_parent().add_child(proj)
	proj.global_position = global_position + Vector3(0.0, 1.4, 0.0)
	proj.monitoring = true
	proj.reset()


func _cast_skill_self_buff(skill: EnemySkill) -> void:
	_change_state(State.CASTING)
	velocity.x = 0.0
	velocity.z = 0.0
	_play_anim(ANIM_ATTACK, 1.0)
	var gen := _generation
	await get_tree().create_timer(skill.wind_up).timeout
	if not is_inside_tree() or _generation != gen or _state != State.CASTING:
		return
	_change_state(State.CHASING)
	_self_buff_remain = skill.buff_duration
	_self_buff_damage_mult = skill.buff_damage_mult
	_self_buff_speed_mult = skill.buff_speed_mult


func _cast_attack(player: Node3D, aim: Vector3) -> void:
	# Charmed enemies always melee — even ranged classes. Their projectiles
	# are coded against the player layer/group; firing them at another enemy
	# would either no-op or self-hit. Melee resolves cleanly via the
	# target's take_damage regardless of who's holding the leash.
	if _is_ranged() and not _charmed:
		_cast_ranged_attack(player, aim)
	else:
		_cast_melee_attack(player, aim)


func _cast_melee_attack(player: Node3D, aim: Vector3) -> void:
	_change_state(State.CASTING)
	_attack_cd = _attack_cooldown()
	velocity.x = 0.0
	velocity.z = 0.0
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.2)
	var range_now := _attack_range()
	var cone_now := _melee_cone_deg()
	var windup_now := _attack_windup()
	# Telegraph (ground cone outline) during windup, then weapon-matched
	# hit VFX on impact — same visuals the player sees for the same weapon.
	CombatVisuals.spawn_cone(self, aim, range_now, cone_now, windup_now)
	var gen := _generation
	await get_tree().create_timer(windup_now).timeout
	# Bail if anything preempted us during the windup (knockback, death,
	# leash, or pool recycle). The generation counter catches pool recycles;
	# the state check catches in-lifetime preemptions.
	if not is_inside_tree() or _generation != gen or _state != State.CASTING:
		return
	# Weapon-matched impact VFX — mirrors player_combat.gd melee visuals.
	var wid: StringName = enemy_class.weapon_id if enemy_class != null else &""
	if wid == &"blade":
		CombatVisuals.spawn_blade_slash(self, aim, range_now, cone_now)
	elif wid == &"sledgehammer":
		CombatVisuals.spawn_hit_cone(self, aim, range_now, cone_now)
		CombatVisuals.spawn_hammer_impact(self)
	else:
		CombatVisuals.spawn_hit_cone(self, aim, range_now, cone_now)
	WeaponSounds.play_fire(wid, global_position)
	_change_state(State.CHASING)
	if not is_instance_valid(player):
		return
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist > range_now or dist < 0.001:
		return
	var half_cos := cos(deg_to_rad(cone_now * 0.5))
	if aim.dot(to_p / dist) < half_cos:
		return
	# Re-check LoS at the moment of damage so a player who ducked behind a
	# wall during the windup doesn't get hit through it. Skip for non-player
	# targets — LosCuller only caches player LoS, and charm-target swings
	# don't need stealth-vs-walls correctness in the prototype.
	if player is PrototypePlayer and not LosCuller.has_los_to_player(self):
		return
	if player.has_method(&"take_damage"):
		var dmg := int(round(float(_attack_damage) * _outgoing_damage_mult()))
		player.take_damage(dmg, global_position, _melee_knockback())


func _cast_ranged_attack(player: Node3D, aim: Vector3) -> void:
	if enemy_class == null or enemy_class.projectile_scene == null:
		# Misconfigured: ranged class without a projectile scene. Fall back
		# to melee so the enemy isn't silently inert.
		_cast_melee_attack(player, aim)
		return
	_change_state(State.CASTING)
	_attack_cd = _attack_cooldown()
	velocity.x = 0.0
	velocity.z = 0.0
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.2)
	var windup_now := _attack_windup()
	var gen := _generation
	await get_tree().create_timer(windup_now).timeout
	if not is_inside_tree() or _generation != gen or _state != State.CASTING:
		return
	if not is_instance_valid(player):
		_change_state(State.CHASING)
		return
	if not LosCuller.has_los_to_player(self):
		_change_state(State.CHASING)
		return
	# Read burst / pellet config from the basic_attack skill.
	var ba: EnemySkill = enemy_class.basic_attack if enemy_class != null else null
	var burst: int = ba.burst_count if ba != null and ba.burst_count > 1 else 1
	var burst_delay: float = ba.burst_delay if ba != null else 0.1
	var pellets: int = ba.projectile_count if ba != null and ba.projectile_count > 1 else 1
	var spread_deg: float = ba.projectile_spread_deg if ba != null else 15.0
	var ba_dmg_mult: float = ba.damage_mult if ba != null else 1.0
	var ba_blast: float = ba.projectile_blast_radius if ba != null else 0.0
	# Fire burst_count rounds, re-aiming each round at the player's
	# current position. Each round can be a single projectile or a
	# multi-pellet spread (shotgun).
	for burst_i in burst:
		if burst_i > 0:
			await get_tree().create_timer(burst_delay).timeout
			if not is_inside_tree() or _generation != gen:
				return
			if not is_instance_valid(player):
				break
		# Re-aim each burst round at the player's CURRENT position.
		var origin := global_position + Vector3(0.0, 1.4, 0.0)
		var to_p: Vector3 = (player.global_position + Vector3(0.0, 1.0, 0.0)) - origin
		var dist := to_p.length()
		if dist < 0.001:
			break
		var center_aim := to_p / dist
		_face_direction(Vector3(center_aim.x, 0.0, center_aim.z).normalized())
		if pellets <= 1:
			_spawn_enemy_projectile(center_aim, ba_dmg_mult, ba_blast)
		else:
			# Multi-pellet spread (shotgun): symmetric fan around center aim.
			var spread_rad := deg_to_rad(spread_deg)
			var half := (pellets - 1) * 0.5
			for i in pellets:
				var offset_angle := (float(i) - half) * spread_rad
				var rotated_aim := center_aim.rotated(Vector3.UP, offset_angle)
				_spawn_enemy_projectile(rotated_aim, ba_dmg_mult, ba_blast)
	_change_state(State.CHASING)


func _spawn_enemy_projectile(aim: Vector3, skill_damage_mult: float = 1.0, blast_radius: float = 0.0) -> void:
	# Pool/level teardown can free the enemy from the tree between the
	# windup-await resume and here. Bail rather than read global_position
	# off a detached node and crash on get_parent().add_child(...).
	if not is_inside_tree():
		return
	var proj: PrototypeProjectile = EntityPool.acquire(enemy_class.projectile_scene)
	if proj == null:
		return
	proj.target_group = &"player"
	proj.direction = _apply_enemy_aim_spread(aim)
	proj.speed = enemy_class.projectile_speed
	proj.max_range = enemy_class.projectile_max_range
	proj.knockback_strength = 0.0  # no knockback on default ranged attacks — reserve for special skills
	proj.is_bullet = enemy_class.projectile_is_bullet
	proj.blast_radius = blast_radius
	proj.source_position = global_position
	var dmg := int(round(float(_attack_damage) * skill_damage_mult * _outgoing_damage_mult()))
	proj.damage_min = dmg
	proj.damage_max = dmg
	proj.damage_mult = 1.0
	proj.accuracy = 1.0
	proj.crit_chance = 0.0
	get_parent().add_child(proj)
	proj.global_position = global_position + Vector3(0.0, 1.4, 0.0)
	proj.monitoring = true
	proj.reset()
	var proj_wid: StringName = enemy_class.weapon_id if enemy_class != null else &""
	WeaponSounds.play_fire(proj_wid, proj.global_position)


## Minimum horizontal spread on a miss (radians) — same as player.
const ENEMY_MISS_MIN_SPREAD: float = 0.06

## Accuracy is a hit/miss roll: 72% accuracy = 72% of shots fly true,
## 28% get visible spread applied. Same model as the player system.
func _apply_enemy_aim_spread(aim: Vector3) -> Vector3:
	var acc := enemy_class.accuracy if enemy_class != null else 0.75
	acc = clampf(acc, 0.0, 1.0)
	if randf() < acc:
		return aim
	# Miss — apply spread with a guaranteed minimum so it goes wide.
	var yaw := atan2(aim.x, aim.z)
	var pitch := asin(clampf(aim.y, -1.0, 1.0))
	var h_spread := randf_range(ENEMY_MISS_MIN_SPREAD, ENEMY_INACCURACY_SPREAD_MAX)
	if randf() < 0.5:
		h_spread = -h_spread
	var v_max := ENEMY_INACCURACY_SPREAD_MAX * ENEMY_VERTICAL_SPREAD_RATIO
	var v_spread := randf_range(-v_max, v_max)
	yaw += h_spread
	pitch += v_spread
	pitch = clampf(pitch, -PI * 0.5, PI * 0.5)
	var cos_p := cos(pitch)
	return Vector3(sin(yaw) * cos_p, sin(pitch), cos(yaw) * cos_p)


func _die(kill_from: Vector3 = Vector3.ZERO, kill_force: float = 0.0) -> void:
	_change_state(State.DEAD)
	# Drop out of the spatial grid immediately so AoE/cone queries during the
	# DEATH_HOLD window stop "hitting" the corpse-in-progress. The actual
	# group/collision teardown still waits for _become_corpse so the death
	# animation and drops can finish.
	SpatialGrid.unregister(self)
	# Deferred — _die can be reached through projectile body_entered → take_damage,
	# i.e. mid physics-query flush, where direct collision/layer writes error.
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	if collision != null:
		collision.set_deferred(&"disabled", true)
	died.emit()
	if is_boss:
		get_tree().call_group(&"boss_listeners", &"on_boss_died", self)
	set_physics_process(false)
	if health_bar != null:
		health_bar.visible = false
	# Strip every status-effect visual on death — corpses showing
	# stun / weaken / charm / curse markers reads as "this enemy is
	# still a thing", which is misleading. Reset the timer state too
	# so reset() (pool re-acquire) starts from a clean slate.
	_clear_affliction_marker()
	_clear_curse_marker()
	_clear_curse_laser()
	_stun_remain = 0.0
	_ignite_remain = 0.0
	_ignite_dps = 0.0
	_ignite_tick_accum = 0.0
	_bleed_remain = 0.0
	_bleed_stacks = 0
	_bleed_tick_accum = 0.0
	_weaken_remain = 0.0
	_weaken_mult = 0.0
	_curse_remain = 0.0
	_curse_damage_pct = 0.0
	PlayerState.gain_xp(PlayerState.xp_award_for_enemy(level))
	_drop_credits()
	_drop_item()
	# Ragdoll path: spawn a physics-driven corpse with a clone of our visual
	# and hide ours. Replaces the old death-anim / fallback rotation tween —
	# the tumble + sink reads better than a static "lay flat" pose and lets
	# explosions/players knock corpses around. The original CharacterBody3D
	# stays in tree as an inert placeholder until DEATH_HOLD elapses, then
	# becomes a registered corpse for the existing pool-eviction system.
	_spawn_ragdoll_corpse(kill_from, kill_force)
	if visual != null:
		visual.visible = false
	var gen := _generation
	await get_tree().create_timer(DEATH_HOLD).timeout
	if not is_inside_tree() or _generation != gen:
		return
	_become_corpse()

func _drop_credits() -> void:
	if randf() >= credit_drop_chance:
		return
	var drop_pos := global_position + Vector3(0.0, 1.0, 0.0)
	var amt := randi_range(CREDIT_DROP_MIN, CREDIT_DROP_MAX)
	# MP: spawn via PickupsContainer so the spawner replicates to all peers.
	var container := _find_pickups_container()
	if container != null and NetState.is_in_lobby():
		container.spawn_credit(amt, drop_pos)
		return
	# SP: use EntityPool for horde-scale perf.
	var parent := get_parent()
	if parent == null:
		return
	var pickup := EntityPool.acquire(CREDIT_PICKUP_SCENE)
	pickup.amount = amt
	(container if container != null else parent).add_child(pickup)
	pickup.global_position = drop_pos
	pickup.reset()

func _drop_item() -> void:
	var named_drop := named_monster != null
	# Named monsters always drop, at the configured rarity floor. Regular
	# trash uses the level-scaled chance.
	if not named_drop:
		var drop_chance := ITEM_DROP_CHANCE_BASE + ITEM_DROP_CHANCE_PER_LEVEL * float(maxi(level - 1, 0))
		if randf() >= drop_chance:
			return
	var drop_pos := global_position + Vector3(0.0, 1.0, 0.0)
	var container := _find_pickups_container()
	# MP: per-player instanced drops — roll one item per lobby member.
	if NetState.is_in_lobby() and container != null:
		for peer_id_v in NetState.lobby_members.keys():
			var peer_id: int = int(peer_id_v)
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var ilvl := maxi(1, level + rng.randi_range(ITEM_DROP_ILVL_OFFSET_MIN, ITEM_DROP_ILVL_OFFSET_MAX))
			var item: Item
			if named_drop:
				var pool := SlotRegistry.MAIN_TYPES
				var main_type: String = pool[rng.randi_range(0, pool.size() - 1)]
				item = ItemRoller.roll(main_type, ilvl, named_monster.guaranteed_drop_rarity, rng)
			else:
				item = ItemRoller.roll_random(ilvl, rng)
			container.spawn_item(item, drop_pos, StringName(str(peer_id)))
		return
	# SP: single drop, no owner.
	var parent := container if container != null else get_parent()
	if parent == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ilvl := maxi(1, level + rng.randi_range(ITEM_DROP_ILVL_OFFSET_MIN, ITEM_DROP_ILVL_OFFSET_MAX))
	var item: Item
	if named_drop:
		var pool := SlotRegistry.MAIN_TYPES
		var main_type: String = pool[rng.randi_range(0, pool.size() - 1)]
		item = ItemRoller.roll(main_type, ilvl, named_monster.guaranteed_drop_rarity, rng)
	else:
		item = ItemRoller.roll_random(ilvl, rng)
	if container != null:
		container.spawn_item(item, drop_pos)
	else:
		var pickup := ITEM_PICKUP_SCENE.instantiate()
		pickup.configure(item)
		parent.add_child(pickup)
		pickup.global_position = drop_pos


func _find_pickups_container() -> PickupsContainer:
	var pc := get_tree().get_first_node_in_group(&"pickups_container")
	if pc is PickupsContainer:
		return pc as PickupsContainer
	return null

# Spawns a PrototypeRagdollCorpse next to us with a duplicate of the visual
# subtree, then hands it the kill direction so it tumbles away from the hit.
# Best-effort: silently no-ops if the visual is missing or we have no parent
# to attach the corpse to (mid-teardown).
func _spawn_ragdoll_corpse(kill_from: Vector3, kill_force: float) -> void:
	if visual == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var corpse := PrototypeRagdollCorpse.new()
	parent.add_child(corpse)
	# Spawn slightly above ground so the tumble has clearance — the capsule's
	# lower hemisphere otherwise spawns penetrating the floor and the rigid
	# body fires immediately upward to depenetrate, which reads as a hop.
	corpse.global_position = global_position + Vector3(0.0, 0.6, 0.0)
	var clone := visual.duplicate() as Node3D
	if clone == null:
		corpse.queue_free()
		return
	clone.position = Vector3.ZERO
	# Copy the enemy facing onto the corpse before we detach — once the rigid
	# body starts tumbling its rotation is physics-driven, but the initial
	# pose should match the killed enemy.
	clone.rotation = visual.rotation
	corpse.global_transform.basis = global_transform.basis
	corpse.setup_visual(clone, RAGDOLL_CAPSULE_HEIGHT, RAGDOLL_CAPSULE_RADIUS)
	var dir: Vector3 = Vector3.ZERO
	if kill_from != Vector3.ZERO:
		var d := global_position - kill_from
		d.y = 0.0
		if d.length_squared() > 0.0001:
			dir = d.normalized()
	corpse.apply_death_impulse(dir, kill_force)


# Capsule sizing for the ragdoll. Matches the enemy's authored CapsuleShape3D
# in prototype_enemy.tscn (height 1.7, radius 0.6) but a touch smaller so the
# tumbling body doesn't scrape walls it didn't quite touch alive.
const RAGDOLL_CAPSULE_HEIGHT: float = 1.5
const RAGDOLL_CAPSULE_RADIUS: float = 0.5


func _become_corpse() -> void:
	# If reset_level released this enemy back to the pool during DEATH_HOLD,
	# the await fires on a now-pooled (parent-less) instance — bail before we
	# re-register it in the "corpses" group on a stale node.
	if not is_inside_tree():
		return
	SpatialGrid.unregister(self)
	remove_from_group(&"enemies")
	add_to_group(&"corpses")
	_hovered = false
	_tooltip_locked = false
	_refresh_outline()
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
	if floor_ring != null:
		floor_ring.visible = false
	get_tree().call_group(&"corpse_manager", &"register_corpse", self)

func _face_direction(dir: Vector3) -> void:
	if visual == null or dir.length_squared() < 0.0001:
		return
	visual.look_at(visual.global_position + dir, Vector3.UP)

func _play_anim(candidates: Array[StringName], speed: float = 1.0) -> bool:
	if anim_player == null:
		return false
	for anim_name in candidates:
		if not anim_player.has_animation(anim_name):
			continue
		var name_str := String(anim_name)
		if anim_player.current_animation == name_str and anim_player.is_playing():
			return true
		anim_player.speed_scale = speed
		anim_player.play(name_str)
		return true
	return false

func _ensure_loop(candidates: Array[StringName]) -> void:
	if anim_player == null:
		return
	for anim_name in candidates:
		if not anim_player.has_animation(anim_name):
			continue
		var anim := anim_player.get_animation(anim_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		return
