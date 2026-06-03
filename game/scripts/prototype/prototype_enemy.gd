extends CharacterBody3D
class_name PrototypeEnemy

signal died
signal revived

# Knockback decays quadratically over this window so enemies coast to a stop
# instead of snapping back to chase mid-shove. Pre-decay this was a hard
# velocity hold + abrupt cutoff, which read as bouncy.
const KNOCKBACK_DURATION := CombatConstants.KNOCKBACK_DURATION

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
# Floor on the spread roll — a fully-missing shot still gets at least
# this much angular variance so misses don't all line up on the same
# vector. Lost during the enemy module extraction; restored here.
const ENEMY_MISS_MIN_SPREAD: float = 0.06

# Health bar fill colors — passed to the health_bar.gdshader via
# instance shader parameters. Hostile = red, friendly (charmed pets) =
# green so the player can scan a knot of bodies and tell allies from
# hostiles without inspecting each one. Lost during the visuals
# extraction; restored here.
const _HP_BAR_HOSTILE := Color(1.0, 0.28, 0.32, 1.0)
const _HP_BAR_FRIENDLY := Color(0.30, 1.0, 0.45, 1.0)

const GRAVITY := CombatConstants.GRAVITY
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
# Chase stuck: if chasing but unable to close distance for this long, warp
# to the next nav waypoint. Fires more aggressively than return-stuck because
# the player is watching and a frozen enemy reads as broken.
# Was 2.0s — felt sluggish, enemies stayed wedged on prop corners
# for 2 full seconds before the warp kicked in. 0.9s feels reactive
# without firing under normal nav slowdowns (e.g. tight doorways).
const CHASE_STUCK_TIMEOUT := 0.9
# Was 1.0m / 2.0s = 0.5 m/s minimum closing rate. Loosened to 0.4 so
# tight nav corners (where enemies briefly slow as the agent finds a
# new waypoint) don't false-trigger the stuck warp.
const CHASE_STUCK_PROGRESS_SQ := 0.4
# Nav-throttle: only re-push target_position to NavigationAgent3D when
# the target has moved >sqrt(_NAV_REPATH_DIST_SQ) since the last set.
# Setting target_position is what triggers the agent to recompute its
# path internally — for 200 enemies all chasing the player, doing it
# every tick spends real CPU even when the player is standing still.
# 0.5m threshold (squared = 0.25) is small enough that a moving player
# still gets responsive chase, big enough that idle / standing-still
# fights drop nav work to near zero.
const _NAV_REPATH_DIST_SQ: float = 0.25
# Idle-tick throttle: IDLE enemies more than this distance from the
# player only process 1 tick out of every _IDLE_TICK_DIVISOR. They're
# not chasing, casting, or moving — their state machine has nothing to
# advance per-tick, so 60Hz is overkill. Boss / named / affixed enemies
# are exempt (their auras and behaviour shouldn't skip frames). The
# moment the player closes the distance or the enemy aggros, the gate
# stops firing and they tick at full rate.
const _IDLE_SKIP_DISTANCE_SQ: float = 25.0 * 25.0
const _IDLE_TICK_DIVISOR: int = 6  # process 1 in 6 → effective 10Hz
# Near IDLE throttle: even enemies within _IDLE_SKIP_DISTANCE_SQ get a
# moderate tick reduction while they're sitting in IDLE. Without this,
# a starting room with 15-20 visible IDLE enemies cost ~25ms/frame
# from full-rate ticking on entities that weren't doing anything yet
# (perf log 2026-05-24 showed 40ms steady-state idle proc until the
# player moved to a less crowded view). Divisor 3 = 20Hz; player input
# (aggro on hit / approach) still flips state to CHASING within 50ms,
# well below perceptual threshold. CHASING / CASTING / etc. stay at
# 60Hz so combat reactions remain crisp.
const _NEAR_IDLE_TICK_DIVISOR: int = 3  # process 1 in 3 → effective 20Hz
# Distant chasers also throttle — less aggressively than idle since
# they're actively engaging, but a 25m+ chaser doesn't need 60Hz nav
# updates. Without this, firing a single shot cascades aggro through
# the pack (PrototypeEnemy.aggro()), pulling 50+ distant idles out of
# the IDLE throttle into full-rate CHASING in the same frame — visible
# as a Phys spike to 50+ ms when you open fire in a crowded level.
# Divisor 3 = 20Hz effective tick rate for distant chasers; they keep
# their previous velocity vector across the skipped frames so movement
# stays smooth.
const _CHASE_SKIP_DISTANCE_SQ: float = 25.0 * 25.0
const _CHASE_TICK_DIVISOR: int = 3  # process 1 in 3 → effective 20Hz
# Front-row stagger: when multiple ranged enemies cluster around the same
# target, the ones closest to the player push in by up to this many metres.
# This naturally creates front/back rows so rear enemies have clear LoS
# instead of shuffling sideways trying to path around allies in front.
const RANGED_FRONT_ROW_PUSH := 2.5  # max kite reduction for the closest enemy
const RANGED_GROUP_SCAN_RADIUS := 6.0  # radius to check for ranged allies
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

# ── Footstep SFX ────────────────────────────────────────────────────────────
const ENEMY_FOOTSTEP_DISTANCE: float = 1.8
const ENEMY_FOOTSTEP_DB: float = -24.0  # quieter than player steps (-20 dB)
var _footstep_accum: float = 0.0
var _footstep_last_pos: Vector3 = Vector3.ZERO
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
	Vector2i(2, 3),     # 1 — first encounter, no DR yet, potions not guaranteed
	Vector2i(3, 5),     # 2
	Vector2i(3, 6),     # 3
	Vector2i(4, 7),     # 4
	Vector2i(4, 6),     # 5
	Vector2i(5, 8),     # 6
	Vector2i(5, 9),     # 7
	Vector2i(6, 11),    # 8
	Vector2i(8, 13),    # 9
	Vector2i(9, 15),    # 10
	Vector2i(11, 18),   # 11
	Vector2i(13, 22),   # 12
	Vector2i(16, 26),   # 13
	Vector2i(19, 31),   # 14
	Vector2i(22, 38),   # 15
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
const BOSS_HP_MULT := 12.0
const BOSS_DAMAGE_MULT := 3.0
# Bosses move at this multiple of CHASE_SPEED so the encounter has more
# pressure than a kited trash mob. Applied in _movement_speed_base().
const BOSS_SPEED_MULT := 1.35
const BOSS_VISUAL_SCALE := 1.6
const BOSS_RING_EMISSION := Color(1.0, 0.05, 0.05)
const MAX_AGGRO_CASCADE := 2

const ANIM_IDLE := CombatConstants.ANIM_IDLE
const ANIM_RUN := CombatConstants.ANIM_RUN
const ANIM_ATTACK := CombatConstants.ANIM_ATTACK
const ANIM_FIRE := CombatConstants.ANIM_FIRE
# Playback speed for the rifle-hold pose between shots. The Mixamo
# "Firing Rifle 2" clip bakes a continuous-fire recoil cycle into the
# loop — at 1.0× that recoil reads as a fast wobble in sync with the
# enemy's breathing, which looks broken when the enemy is just standing
# ready (no shot mid-flight). Slowing the picker-side play to 0.4×
# stretches that cycle to a calm aim-breath cadence; the cast_attack
# windup still bumps speed back to 1.0× for the actual shot, so each
# shot reads as: slow breath → snap fire → slow breath.
const _ANIM_FIRE_IDLE_HOLD_SPEED: float = 0.4
const ANIM_CROUCH_IDLE := CombatConstants.ANIM_CROUCH_IDLE
const ANIM_CROUCH_RUN: Array[StringName] = [&"Crouch_Walk_Forward", &"Crouch_Walk", &"CROUCH_WALK", &"Crouch_Idle", &"CROUCH_IDLE"]
const ANIM_JUMP := CombatConstants.ANIM_JUMP
const ANIM_DEATH := CombatConstants.ANIM_DEATH
const ANIM_HIT_LEFT := CombatConstants.ANIM_HIT_LEFT
const ANIM_HIT_RIGHT := CombatConstants.ANIM_HIT_RIGHT
const ANIM_HIT_BACK := CombatConstants.ANIM_HIT_BACK
const ANIM_HIT_BIG := CombatConstants.ANIM_HIT_BIG

# Hit-react one-shot suppresses the locomotion picker for this many
# seconds after a big-enough hit. Mixamo small-react clips are
# ~0.9-1.1s authored; played at _HIT_REACT_SMALL_SPEED they fit
# inside the small window. The big-variant gets a longer, slightly
# slower playback so it reads as weightier without dragging.
const _HIT_REACT_SMALL_DURATION: float = 0.45
const _HIT_REACT_BIG_DURATION: float = 0.65
const _HIT_REACT_SMALL_SPEED: float = 2.2  # ~1.0s clip → ~0.45s playback
const _HIT_REACT_BIG_SPEED: float = 1.6    # heavier feel, longer window
# Damage threshold (fraction of max_health) below which we skip the
# hit-react anim entirely. Tiny grazes shouldn't interrupt the chase
# or attack cycle.
const _HIT_REACT_MIN_DMG_PCT: float = 0.10
# Currently-playing hit-react anim, remaining duration, and playback
# speed. While remain > 0, the locomotion picker plays the hit anim
# at the configured speed instead of idle/run.
var _hit_react_remain: float = 0.0
# Mirrors player's _fire_pose_holding. Set true by the anim-finished
# hook when ANIM_FIRE plays out under HOLD mode (slow ranged
# enemies); the per-tick picker checks this so it doesn't restart
# the fire anim on every frame after it ends, waiting instead for
# the next attack windup to replay from frame 0.
var _fire_pose_holding: bool = false

# Mob body variants. Non-boss enemies override the EnemyClass-authored
# mesh with a randomly-rolled riot_guard variant (4 total — 2 male, 2
# female) so squads read as varied bodies instead of clones. Bosses
# fall through to enemy_class.character_mesh (crimson_vein_titan, etc.)
# so boss silhouettes stay unique. The picked variant is stored in
# `_mob_variant_index` at _init_enemy time and read by _apply_class_mesh,
# so the same enemy doesn't flicker between bodies if _apply_class_mesh
# runs more than once during a spawn cycle.
# Per-gender Y position for the riot_guard mesh Character node, tuned
# so feet sit ON the floor at the CharacterBody3D origin. The Meshy
# player meshes use 0.20m for female because their origin sits 0.20m
# above the feet; riot_guard imports have their origins LOWER than the
# Meshy meshes, so they need a negative lift for males and a smaller
# positive lift for females. Tune here if specific variants drift.
const _ENEMY_FEET_Y_MALE: float = -0.10
const _ENEMY_FEET_Y_FEMALE: float = 0.10


const _MOB_MESH_VARIANTS: Array = [
	{
		&"mesh": preload("res://assets/characters/riot_guard_male_1/riot_guard_male_1.fbx"),
		&"gender": &"male",
	},
	{
		&"mesh": preload("res://assets/characters/riot_guard_male_2/riot_guard_male_2.fbx"),
		&"gender": &"male",
	},
	{
		&"mesh": preload("res://assets/characters/riot_guard_female_1/riot_guard_female_1.fbx"),
		&"gender": &"female",
	},
	{
		&"mesh": preload("res://assets/characters/riot_guard_female_2/riot_guard_female_2.fbx"),
		&"gender": &"female",
	},
]
var _mob_variant_index: int = -1
var _hit_react_anim: Array[StringName] = []
var _hit_react_speed: float = 1.0

const OUTLINE_GROW := 0.06           # match HoverableInteractable for parity with chests / switches
const OUTLINE_LOCKED_COLOR := Color(1.0, 0.15, 0.15)
# Amber-gold for rare/named/boss enemies on hover, matching the gold the
# tooltip uses for affix labels and the named_monster.ring_tint default.
# Reads as "this one's special" without competing with the red locked-target
# signal — locked still wins when both apply.
const OUTLINE_SPECIAL_COLOR := Color(1.0, 0.85, 0.2)

# Random name palette for trash mobs — flavor for the augmentation-facility setting.
# Bosses set their own display_name (assigned by the spawner) and skip the roll.
const NAME_PALETTE: Array[String] = [
	"Husk", "Stray", "Wretch", "Drone", "Brawler",
	"Reject", "Patient", "Recoverer", "Cultist", "Augmented",
]
const NAME_PALETTE_NUMBERED: Array[String] = ["Subject", "Specimen", "Unit"]

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

## Fluid the enemy bleeds — picked up by every blood spawn (burst,
## splatter, pool, wall splat, bootprint trail from corpses they fall
## near). &"human" / &"cyborg" / &"machine" map to colors in
## PrototypeAttackIndicator.BLOOD_PALETTES; add an entry there to support
## a new fluid. Default keeps existing trash mobs bleeding red.
@export var blood_type: StringName = &"human"

@onready var visual: Node3D = $Visual
## Set in _apply_class_mesh() after the mesh swap, because the scene's
## authored Character mesh may not include an AnimationPlayer (Meshy
## rigged-mesh-only FBXs don't ship one). Was previously @onready but
## that resolved before the swap and logged a "Node not found" error
## when the default mesh lacked the node. _apply_class_mesh creates one
## on the fly if the new Character doesn't bring its own.
var anim_player: AnimationPlayer = null
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
var _last_hit_weapon_base_id: StringName = &""
var _last_hit_was_crit: bool = false
# Throttle hit_flesh playback so a single multi-pellet shotgun blast
# (12 pellets landing within ~1 frame) doesn't stack 12 simultaneous
# impact sounds. Each pellet still does damage + visuals; only the
# audio is gated.
var _last_hit_sfx_msec: int = -10000
const _HIT_SFX_THROTTLE_MS: int = 60
# Set in take_damage; consumed by _die's dismemberment roll. Explosion
# deaths get a 25% dismember chance; crits always dismember regardless
# of damage source.
var _last_hit_was_explosion: bool = false
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
# Last position passed to NavigationAgent3D.target_position. Compared
# against the current target each tick; we only re-set the property
# (which triggers internal path-recompute work) when the target has
# moved >sqrt(_NAV_REPATH_DIST_SQ) since the last update. Cuts nav
# work from per-tick × per-enemy to ~stationary-fight = zero.
# INF sentinel = "never set" so the first tick always pushes a target.
var _nav_last_target: Vector3 = Vector3.INF
# Tick-skip counter for distant idle enemies. See _physics_process
# header — IDLE enemies >_IDLE_SKIP_DISTANCE from the player process
# 1 tick out of every _IDLE_TICK_DIVISOR.
var _idle_skip_counter: int = 0
var _hover_hooked: bool = false
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
# Support overlay: _support_tick_t counts down to next emit.
var _support_tick_t: float = 0.0

# Thin delegates for sniper/taser bonuses — state lives in EnemyAfflictions.
func consume_taser_static_build() -> float:
	_afflictions._taser_hit_count += 1
	if _afflictions._taser_hit_count % EnemyAfflictions.TASER_STATIC_INTERVAL == 0:
		return EnemyAfflictions.TASER_STATIC_RELEASE_MULT
	return 1.0

func consume_sniper_first_mark() -> float:
	var now: float = Time.get_ticks_msec() / 1000.0
	var bonus: float = 1.0
	if now - _afflictions._sniper_last_hit_t > EnemyAfflictions.SNIPER_FIRST_MARK_FRESH_INTERVAL:
		bonus = EnemyAfflictions.SNIPER_FIRST_MARK_BONUS_MULT
	_afflictions._sniper_last_hit_t = now
	return bonus

# Skill system — _special_skills assigned by spawner, combat module manages cooldowns.
var _special_skills: Array[EnemySkill] = []
# Generation counter — incremented on every reset(). Post-await code captures
# the generation before yielding and bails if it changed, preventing stale
# continuations from executing on a pool-recycled entity.
var _generation: int = 0
var _combat: EnemyCombat
var _afflictions: EnemyAfflictions
var _visuals: EnemyVisuals

@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
# Spawn position captured on reset() — enemies leash back to this point
# when they chase too far. Set whenever the enemy is reused from the pool
# at a new position.
var _spawn_position: Vector3 = Vector3.ZERO
var _return_stuck_timer: float = 0.0
var _return_last_dist_sq: float = 0.0
var _chase_stuck_timer: float = 0.0
var _chase_last_dist_sq: float = 0.0
var _hit_leash_extend_sq: float = 0.0

# Networking: synced by the MultiplayerSynchronizer to clients. Authority
# (host) writes these each physics tick; clients read them for visuals.
var net_health: int = 0
var net_max_health: int = 0
var net_state: int = 0  # State enum as int
var _net_prev_pos: Vector3 = Vector3.ZERO

func _ready() -> void:
	_combat = EnemyCombat.new()
	_combat.name = &"EnemyCombat"
	_combat.setup(self)
	add_child(_combat)
	_afflictions = EnemyAfflictions.new()
	_afflictions.name = &"EnemyAfflictions"
	_afflictions.setup(self)
	add_child(_afflictions)
	_visuals = EnemyVisuals.new()
	_visuals.name = &"EnemyVisuals"
	_visuals.setup(self)
	add_child(_visuals)
	# X Bot uses external animation FBXs (Mixamo workflow — one anim per
	# file). Merge them into a named library on this enemy's AnimationPlayer
	# so the candidate-array lookup in _play_anim can find them via
	# "xbot/idle", "xbot/punch", etc. No-op for legacy UAL1 enemies; their
	# animations come from the FBX directly and the library install just
	# adds an unused namespace.
	XBotAnimations.install_on(anim_player)
	_isolate_visual_from_decals()
	# Pause AnimationPlayer when the LoS culler hides this enemy AND the
	# enemy is in IDLE (i.e. not mid-attack / mid-cast where the AI state
	# machine might depend on animation_finished firing). With 200+ enemies
	# at level start, all of them ticking their AnimationPlayer every frame
	# was ~40ms/frame of pure cost even for off-screen idles. Pausing
	# invisible-idle enemies recovers that cost without breaking any
	# state-driven anim transitions. visibility_changed survives pool reuse.
	visibility_changed.connect(_update_anim_player_active)
	# Pre-build the per-bone ragdoll skeleton so _die() can flip it into
	# physics simulation instantly. Deferred — the FBX's Skeleton3D may not
	# Physics-bone ragdoll disabled — death pose comes from the Mixamo
	# death animation now (see _on_died for the play call). The setup
	# function builds 20 PhysicalBone3D children per skeleton which we
	# never activate; skipping the call saves the per-enemy memory and
	# physics-server registration overhead. XBotRagdoll.setup() / activate()
	# stay defined for revival when Godot's PhysicalBoneSimulator can
	# initialize bodies from the current pose instead of the rest pose.
	# call_deferred(&"_setup_ragdoll")
	_init_enemy()
	_setup_hover()
	# Normalise scene-default mesh's bones too — alien/vanguard might
	# also use non-mixamorig_ prefixes (we know vanguard is fine, but
	# this is safe / idempotent). Also backfill null surface materials
	# on the default char so the renderer doesn't fire `material_*:
	# Parameter "material" is null` at scene load (before _apply_class_mesh
	# would have run the same backfill on a swapped-in mesh).
	if visual != null:
		var default_skel := _find_skeleton(visual)
		if default_skel != null:
			_normalize_skeleton_bone_prefix(visual, default_skel)
		XBotRagdoll.ensure_surface_materials(visual)


# Move every MeshInstance3D under `visual` off the default visual layer
# (1) onto layer 2. Blood decals project with cull_mask = layer 1 only,
# so decals stop painting themselves onto the character mesh — which
# would otherwise stick to the world-space spot where the decal was
# spawned, looking detached when the corpse moves (ragdoll launch, sink
# tween).
#
# Layer 3 (mask = 4) is the CHARACTER_BLOOD layer — the parallel
# "blood ON characters" pipeline (PrototypeAttackIndicator.spawn_blood_on_character)
# parents its decals to the visual root and targets only this layer,
# so the splat moves with the body but world-blood decals still
# ignore the character. Setting BOTH bits keeps the visual rendered
# (camera sees all 20 layers) and receives character-blood projections.
func _isolate_visual_from_decals() -> void:
	if visual == null:
		return
	_walk_set_visual_layers(visual, 2 | PrototypeAttackIndicator.CHARACTER_BLOOD_LAYER)


static func _walk_set_visual_layers(node: Node, mask: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = mask
	for child in node.get_children():
		_walk_set_visual_layers(child, mask)


# Normalises non-standard Mixamo bone-name prefixes so the shared X Bot
# animation library plays on any rig. Some FBX exports use `mixamorig1_`
# (Mixamo re-exports through Blender often add the `1`), `mixamorig:`
# (colon convention), etc. X Bot animations target `mixamorig_*` paths
# directly, so a mesh with any other prefix would T-pose.
#
# Two-part rename: Skeleton3D bone names AND every MeshInstance3D's
# Skin bind names. Renaming only the bones leaves the mesh's skin
# bindings pointing at the OLD names → vertices can't find their bones
# → limbs detach and float (see the "broken specimen" symptom). The
# Skin binds use a separate name table and must be patched too.
static func _normalize_skeleton_bone_prefix(visual_root: Node, skel: Skeleton3D) -> int:
	if skel == null or skel.get_bone_count() == 0:
		return 0
	var first: String = skel.get_bone_name(0)
	var prefix_from: String = ""
	if first.begins_with("mixamorig1_"):
		prefix_from = "mixamorig1_"
	elif first.begins_with("mixamorig:"):
		prefix_from = "mixamorig:"
	# Already on the canonical mixamorig_ prefix → nothing to do.
	if prefix_from == "":
		return 0
	var prefix_to := "mixamorig_"
	var renamed: int = 0
	for i in skel.get_bone_count():
		var bn: String = skel.get_bone_name(i)
		if bn.begins_with(prefix_from):
			skel.set_bone_name(i, prefix_to + bn.substr(prefix_from.length()))
			renamed += 1
	# Walk from the FBX/visual root because MeshInstance3D children
	# typically sit as siblings to Skeleton3D (not under it). Skin is
	# shared-by-reference, so duplicate before patching to avoid
	# corrupting the cached resource for future spawns of this FBX.
	if visual_root != null:
		_rebind_skins_under(visual_root, prefix_from, prefix_to)
	return renamed


static func _rebind_skins_under(node: Node, prefix_from: String, prefix_to: String) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.skin != null:
			var new_skin: Skin = mi.skin.duplicate()
			var n: int = new_skin.get_bind_count()
			for i in n:
				var bind_name: String = new_skin.get_bind_name(i)
				if bind_name.begins_with(prefix_from):
					new_skin.set_bind_name(i, prefix_to + bind_name.substr(prefix_from.length()))
			mi.skin = new_skin
	for child in node.get_children():
		_rebind_skins_under(child, prefix_from, prefix_to)


# Replaces the Visual/Character child mesh with the EnemyClass's
# character_mesh override (if any). Re-resolves `anim_player`, reinstalls
# the X Bot animation library on the new AnimationPlayer, and reapplies
# decal-layer isolation. Idempotent — if the current Character is
# already the requested mesh, this skips the swap. Called from
# _init_enemy on every spawn so pool re-acquires with a different class
# pick up the right mesh too.
func _apply_class_mesh() -> void:
	if visual == null:
		return
	# Mob variant override: non-boss enemies use a random riot_guard
	# variant rolled in _init_enemy regardless of what EnemyClass.
	# character_mesh authored. Bosses fall through to the authored
	# mesh (crimson_vein_titan, etc.) so boss silhouettes stay unique.
	var picked_mesh: PackedScene = null
	var picked_gender: StringName = &"male"
	if _mob_variant_index >= 0 and _mob_variant_index < _MOB_MESH_VARIANTS.size():
		var variant: Dictionary = _MOB_MESH_VARIANTS[_mob_variant_index]
		picked_mesh = variant.get(&"mesh") as PackedScene
		picked_gender = variant.get(&"gender", &"male") as StringName
	elif enemy_class != null and enemy_class.character_mesh != null:
		picked_mesh = enemy_class.character_mesh
		# Boss mesh has no built-in gender concept — male grip table
		# is the default fallback in WeaponAttachment anyway.
		picked_gender = &"male"
	# If the EnemyClass doesn't override the mesh, the scene's authored
	# Character node stays. We still need to resolve anim_player from it
	# (or create one if the authored mesh didn't ship an AnimationPlayer),
	# otherwise anim_player remains the null default from line 384.
	var current_char := visual.get_node_or_null(^"Character") as Node3D
	if picked_mesh == null:
		if current_char != null:
			_ensure_anim_player_on(current_char)
		return
	# Skip the swap if the current Character already came from this scene —
	# checking scene_file_path is the cheapest way to compare since
	# PackedScene resource_path is canonical.
	if current_char != null and current_char.scene_file_path == picked_mesh.resource_path:
		# Even on the no-swap path, refresh the gender meta in case a
		# pool re-acquire shifted us to a different variant of the same
		# mesh family. WeaponAttachment grip table depends on this.
		current_char.set_meta(&"gender", picked_gender)
		# Female meshes ship with their geometric origin ~0.20m above
		# the feet (same as the player path); lift them so feet sit at
		# floor level. Male meshes stay at y=0.
		current_char.position.y = _ENEMY_FEET_Y_FEMALE if picked_gender == &"female" else _ENEMY_FEET_Y_MALE
		_ensure_anim_player_on(current_char)
		return
	if current_char != null:
		visual.remove_child(current_char)
		current_char.queue_free()
	var new_char := picked_mesh.instantiate() as Node3D
	if new_char == null:
		return
	new_char.name = "Character"
	# Stash the gender meta so WeaponAttachment._resolve_skeleton_gender
	# can pick the right grip table (per-weapon offset/rotation/scale
	# tuned for female bone proportions). Matches player setup.
	new_char.set_meta(&"gender", picked_gender)
	# Female meshes need a Y lift so feet sit at floor level (geometric
	# origin sits ~0.20m above the feet on the Meshy female imports).
	new_char.position.y = _ENEMY_FEET_Y_FEMALE if picked_gender == &"female" else _ENEMY_FEET_Y_MALE
	# Backfill null surface materials BEFORE the node enters the tree.
	# Doing it after add_child leaves one frame where the renderer sees
	# the null surfaces and spams material_*: Parameter is null. Same
	# pattern the player path uses.
	XBotRagdoll.ensure_surface_materials(new_char)
	visual.add_child(new_char)
	# Per-class yaw correction for meshes authored facing the wrong
	# axis (military_man faces opposite X Bot, so the class sets PI).
	if enemy_class != null and absf(enemy_class.mesh_yaw_offset) > 0.0001:
		new_char.rotation.y = enemy_class.mesh_yaw_offset
	# Re-resolve anim_player — the @onready cached the OLD Character's
	# AnimationPlayer, which is about to be freed. find_child walks the
	# subtree because the FBX-imported scene's AnimationPlayer node may
	# be at a non-fixed path depending on importer version.
	_ensure_anim_player_on(new_char)
	# Re-apply layer isolation so blood decals don't paint on the new
	# mesh — _ready's call ran on the old subtree.
	_isolate_visual_from_decals()
	# Normalise non-standard bone prefixes (mixamorig1_, mixamorig:) to
	# the canonical mixamorig_ that X Bot animations target. Without
	# this, crypto-skinned enemies T-pose because the animation tracks
	# can't find matching bone names on the new skeleton.
	var new_skel := _find_skeleton(new_char)
	if new_skel != null:
		_normalize_skeleton_bone_prefix(new_char, new_skel)
		# Bake uniform scale into the FBX's intermediate Armature / Skeleton
		# nodes so future PhysicalBone3D children Jolt builds at ragdoll
		# time inherit a clean parent chain. Stop at Visual so we don't
		# touch the CharacterBody3D itself. See xbot_ragdoll comment for
		# the historical Jolt _try_build_shape spam this prevents.
		XBotRagdoll.normalize_parent_chain_scale(new_skel, visual)
	# Per-class color tint. Multiplied into each surface's albedo via the
	# material's per-instance modulate path — keeps the authored PBR
	# textures intact while letting a shared mesh read as distinct
	# archetypes (e.g. crimson_vein_titan tinted red for snipers, green
	# for healers).
	if enemy_class.mesh_tint != Color(1.0, 1.0, 1.0, 1.0):
		_apply_mesh_tint(new_char, enemy_class.mesh_tint)
	# Re-collect the outline mesh list — the swap freed every node in
	# `_outlined_meshes`, and EnemyVisuals.collect_meshes() is otherwise
	# only called from _setup_hover() (one-shot, in _ready). Without this,
	# pool-acquired enemies of a different class than they last held lose
	# their hover-highlight because every cached mesh fails is_instance_valid.
	if _visuals != null:
		_visuals.collect_meshes()


# Finds an AnimationPlayer under `char_root` (or creates one when the
# Meshy FBX shipped without one), stores it on anim_player, and ensures
# the X Bot animation library is installed. Replaces the previous
# @onready resolution path so a default authored Character mesh that
# lacks an AnimationPlayer doesn't log "Node not found" at ready.
func _ensure_anim_player_on(char_root: Node3D) -> void:
	var ap := char_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		char_root.add_child(ap)
	anim_player = ap
	XBotAnimations.install_on(anim_player)
	# HOLD-mode fire-pose flag: set true when a non-looping fire anim
	# finishes so the per-tick picker can keep it held at end frame.
	if not anim_player.animation_finished.is_connected(_on_fire_anim_finished):
		anim_player.animation_finished.connect(_on_fire_anim_finished)


func _on_fire_anim_finished(anim_name: StringName) -> void:
	if anim_name in ANIM_FIRE:
		_fire_pose_holding = true


# Walks every MeshInstance3D descendant of `root` and multiplies `tint`
# into each surface's albedo. Duplicates the material per-surface so the
# tint doesn't leak across class variants that share the underlying mesh
# resource. A no-op when `tint` is opaque white (caller already guards
# this, but cheap to defend in case of future call sites).
func _apply_mesh_tint(root: Node, tint: Color) -> void:
	if tint == Color(1.0, 1.0, 1.0, 1.0):
		return
	for node in _walk_mesh_instances(root):
		var mi: MeshInstance3D = node
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for surf in range(mesh.get_surface_count()):
			# Per-surface override pulls either an instance override (set
			# previously) or the mesh's authored material. Duplicate so we
			# don't mutate a shared resource.
			var src_mat: Material = mi.get_active_material(surf)
			if src_mat == null:
				continue
			var mat: BaseMaterial3D = src_mat.duplicate() as BaseMaterial3D
			if mat == null:
				continue
			mat.albedo_color = mat.albedo_color * tint
			mi.set_surface_override_material(surf, mat)


func _walk_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_walk_mesh_instances(c))
	return out


func _setup_ragdoll() -> void:
	if visual == null:
		return
	# Find ANY Skeleton3D in the visual subtree — the FBX's Skeleton3D
	# might not be named exactly "Skeleton3D" after the BoneMap retarget
	# (some Godot versions rename it).
	var skel := _find_skeleton(visual)
	if skel == null:
		return
	XBotRagdoll.setup(skel)


# Walks a Node3D subtree looking for any Skeleton3D. find_child requires
# matching the node name; for FBX imports the skeleton node may use a
# different name depending on the source (e.g. "Armature", "GeneralSkeleton").
func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


# Mounts the EnemyClass's weapon model on the enemy's right-hand bone.
# Enemies share the X Bot skeleton with the player, so the same grip
# offsets apply. Runs on host and client — enemy_class (hence weapon_id)
# is replicated, so client avatars show the weapon too. Bare-handed
# classes (empty weapon_id) clear the model.
func _apply_enemy_weapon_model() -> void:
	var skel := _find_skeleton(visual)
	if skel == null:
		return
	var weapon_id: StringName = enemy_class.weapon_id if enemy_class != null else &""
	WeaponAttachment.set_weapon_for_enemy(skel, weapon_id)
	# Keep the weapon model off render layer 1 (floor blood decals) and
	# on the enemy's blood layer, same as the body mesh.
	var mount := WeaponAttachment.get_mount(skel)
	if mount != null:
		_walk_set_visual_layers(mount, 2 | PrototypeAttackIndicator.CHARACTER_BLOOD_LAYER)


func _init_enemy() -> void:
	_generation += 1
	add_to_group(&"enemies")
	# SpatialGrid drives AI queries (aggro, support, AoE) — only the host
	# needs it. Clients skip registration since they don't run AI.
	if not _is_remote_enemy():
		SpatialGrid.register(self, &"enemies")
	if not is_boss:
		_visuals.roll_display_name()
	# Reset transient visuals before _apply_level_stats so boss scaling, applied
	# inside that call, isn't immediately stomped back to ONE.
	if visual != null:
		visual.rotation = Vector3.ZERO
		visual.scale = Vector3.ONE
	# Pool re-acquire: clear facing-slew state so the first _face_direction
	# on the new spawn snaps to its initial target instead of slewing
	# from the previous occupant's last facing.
	_target_facing_set = false
	_target_facing_y = 0.0
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
		_hit_tween = null
	_apply_level_stats()
	# Roll a mob-body variant BEFORE _apply_class_mesh reads it. Non-boss
	# enemies show one of the 4 riot_guard variants; bosses skip the roll
	# and use the EnemyClass-authored mesh. Rolled here so the pick is
	# fresh on every pool re-acquire (matches _generation bump above).
	if is_boss:
		_mob_variant_index = -1
	else:
		_mob_variant_index = randi() % _MOB_MESH_VARIANTS.size()
	# Apply the EnemyClass's character_mesh override AFTER _apply_level_stats
	# so any named-monster class swap (which happens inside that function)
	# is in effect first — the named monster's class drives the mesh, not
	# the spawner-set base class.
	_apply_class_mesh()
	# Mount the class's weapon model on the (possibly rebuilt) skeleton.
	# Done here rather than inside _apply_class_mesh so a pooled enemy
	# that kept its mesh but was re-acquired as a different class still
	# gets the correct weapon swapped in.
	_apply_enemy_weapon_model()
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
	# Reset perf-throttle state so a recycled pool entry doesn't carry
	# the previous enemy's nav-target cache or its mid-skip counter.
	_nav_last_target = Vector3.INF
	_idle_skip_counter = 0
	set_physics_process(true)
	collision_layer = EnemyAfflictions._LAYER_ENEMY
	collision_mask = EnemyAfflictions._DEFAULT_ENEMY_MASK
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
	_afflictions.reset()
	_special_skills.clear()
	_combat.reset(_special_skills)
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
		tint_color = _visuals.class_ring_color()
	_visuals.apply_floor_ring_tint_color(tint_color)
	_visuals.apply_model_tint(tint_color)
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
	_visuals.apply_floor_ring_tint_color(BOSS_RING_EMISSION)
	_visuals.apply_model_tint(BOSS_RING_EMISSION)
	add_to_group(&"bosses")
	# Register from here (not from the spawn slot) so MP clients — who get
	# bosses replicated via MultiplayerSpawner rather than running the
	# spawn slot's _spawn() locally — also flip into the boss phase.
	# register_boss is idempotent, so duplicate calls from the spawn slot
	# on the host are harmless.
	MissionState.register_boss()

## Class-tint constants — used by EnemyVisuals.class_ring_color.
const _CLASS_TINT_MELEE := Color(1.0, 0.25, 0.15)
const _CLASS_TINT_RANGED := Color(0.25, 0.65, 1.0)
const _CLASS_TINT_SUPPORT := Color(0.25, 1.0, 0.45)


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
	_visuals.reset()
	# Clear level + boss flag so the next reset() re-rolls cleanly. Spawners
	# that need a fixed level/boss reassign these after acquire() and before reset().
	level = 0
	is_boss = false
	display_name = "Enemy"
	remove_from_group(&"bosses")
	_visuals.refresh_outline()

## Re-initialize an enemy returned from the pool.
func reset() -> void:
	remove_from_group(&"corpses")
	remove_from_group(&"ragdoll_corpses")
	# Clear ragdoll state so the pooled enemy starts its next life as a
	# fresh non-ragdoll. PhysicalBone3D children that setup() attached
	# stay on the skeleton — XBotRagdoll.setup is idempotent so a
	# re-acquired enemy doesn't rebuild them. If sim was still running
	# (unlikely with the 2s settle stop but possible if the corpse was
	# evicted mid-launch), stop it now so the freshly-spawned enemy
	# isn't part physics-driven.
	if _ragdoll_simulating and visual != null:
		var skel := _find_skeleton(visual)
		if skel != null:
			skel.physical_bones_stop_simulation()
	_ragdoll_simulating = false
	_ragdoll_settle_timer = 0.0
	_despawn_token += 1  # cancels any pending corpse-despawn timer
	set_process(false)
	# Restore the visual the ragdoll spawn hid on death — pool re-acquire
	# would otherwise show an invisible enemy. Also reset the sink tween's
	# position offset so a recycled body doesn't spawn half-buried.
	if visual != null:
		visual.visible = true
		visual.position = Vector3.ZERO
	_init_enemy()
	# EnemySpawner sets global_position right before calling reset(), so
	# capturing here gives us the correct spawn point even when the enemy
	# is reused from the pool at a new location.
	_spawn_position = global_position
	_hit_leash_extend_sq = 0.0
	_footstep_accum = 0.0
	_footstep_last_pos = Vector3.ZERO
	# Note: `affixes` is set by the spawner BEFORE reset() in pack-spawn
	# paths, and cleared (re-set to []) by the spawner for non-pack spawns,
	# so a pool-recycled body never inherits the previous owner's modifiers.
	# We don't clear here because the spawner's pre-reset assignment would
	# be wiped.

func _setup_hover() -> void:
	_visuals.collect_meshes()
	if not _hover_hooked:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		_build_hover_zone()
		_hover_hooked = true

const _HOVER_RADIUS: float = 1.1
const _HOVER_HEIGHT: float = 2.2

func _build_hover_zone() -> void:
	var area := Area3D.new()
	area.name = &"HoverZone"
	area.collision_layer = 0
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = false
	area.input_ray_pickable = true
	area.position = Vector3(0.0, 0.8, 0.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _HOVER_RADIUS
	cap.height = _HOVER_HEIGHT
	shape.shape = cap
	area.add_child(shape)
	add_child(area)
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	_visuals.on_mouse_entered()
	add_to_group(&"tooltip_target")

func _on_mouse_exited() -> void:
	_visuals.on_mouse_exited()
	remove_from_group(&"tooltip_target")


func set_tooltip_locked(on: bool) -> void:
	_visuals.set_tooltip_locked(on)

func refresh_locked_tooltip() -> void:
	_visuals.push_tooltip()

## Static helper: route damage to an enemy, handling SP / MP host / MP client
## transparently. Every damage source (player_combat, projectile, grenade,
## trap, telekinesis, doomsayer) calls this instead of target.take_damage().
## In SP or on the host, calls take_damage directly. On a MP client, sends
## the hit to the host via RPC. Hit visuals (damage number, flash, squash)
## are broadcast to ALL clients by the host's take_damage via _client_show_hit,
## so the client path no longer spawns local feedback.
static func deal_damage(target: Node3D, amount: int, knockback_from: Vector3, knockback_strength: float = 0.0, multistrike: int = 1, is_crit: bool = false, weapon_base_id: StringName = &"", is_explosion: bool = false) -> void:
	if NetState.is_in_lobby() and not NetState.is_host():
		target.request_damage.rpc_id(1, amount, knockback_from, knockback_strength, multistrike, is_crit, weapon_base_id, is_explosion)
		return
	target.take_damage(amount, knockback_from, knockback_strength, multistrike, is_crit, weapon_base_id, is_explosion)

## RPC endpoint: any peer can request damage on an enemy. Only the host
## (authority) actually applies it — clients' local take_damage is gated.
## Clients call `request_damage.rpc_id(1, ...)` to route hits to the host.
@rpc("any_peer", "call_remote", "reliable")
func request_damage(amount: int, knockback_from: Vector3, knockback_strength: float, multistrike: int, is_crit: bool, weapon_base_id: StringName = &"", is_explosion: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if not is_inside_tree():
		return
	take_damage(amount, knockback_from, knockback_strength, multistrike, is_crit, weapon_base_id, is_explosion)

## Host → all clients: play hit visuals (damage number, squash, flash).
## Sent from take_damage after the host applies damage so every client
## sees every hit, not just the attacker. Unreliable because a dropped
## damage number is cosmetic — no gameplay impact.
@rpc("authority", "call_remote", "unreliable")
func _client_show_hit(amount: int, multistrike: int, is_crit: bool) -> void:
	var head := global_position + Vector3(0.0, 1.8, 0.0)
	DamageNumber.spawn(get_parent(), head, amount, multistrike, is_crit)
	_visuals.play_hit_squash()
	_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween)

func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0, multistrike: int = 1, is_crit: bool = false, weapon_base_id: StringName = &"", is_explosion: bool = false) -> void:
	if not _is_alive():
		return
	# Clients don't apply damage locally — they route hits through
	# request_damage RPC to the host.
	if _is_remote_enemy():
		return
	# Captured for _die — drives the dismemberment roll (crits always
	# dismember, explosion deaths roll 25%).
	_last_hit_was_explosion = is_explosion
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
	if _afflictions._curse_damage_pct > 0.0:
		amount = int(round(float(amount) * (1.0 + _afflictions._curse_damage_pct * 0.01)))
	if _afflictions._isr_vuln_count > 0:
		amount = int(round(float(amount) * (1.0 + float(_afflictions._isr_vuln_count) * (ISRDrone.VULN_MULT - 1.0))))
	_health -= amount
	_last_hit_weapon_base_id = weapon_base_id
	_last_hit_was_crit = is_crit
	_visuals.update_health_bar()
	# Blood burst per hit. Direction = away from the shooter (or upward
	# fallback when knockback_from isn't set, e.g. DoT ticks). Crits get
	# a bigger spray; the kill case below adds another, larger one.
	var hit_pos := global_position + Vector3(0.0, 1.0, 0.0)
	var blood_dir: Vector3 = (hit_pos - knockback_from)
	blood_dir.y = 0.5
	if blood_dir.length_squared() < 0.0001:
		blood_dir = Vector3.UP
	else:
		blood_dir = blood_dir.normalized()
	var hit_mult: float = 3.0 if is_crit else 1.5
	# Blade weapons (melee_1h) ship a built-in bleed status, so the
	# kinetic-impact spray reads bigger to match — extra droplets +
	# extra velocity sells "slashed open" vs "shot through". Doubles
	# the multiplier on top of the crit bonus.
	if weapon_base_id == &"melee_1h":
		hit_mult *= 2.0
	# Shift the burst toward the exit side — pushing 30 cm along the shot
	# direction (XZ only, so the height stays at chest level) means the
	# spray emerges from the far side of the enemy mesh, not its centre.
	# Reads as an exit wound; without the offset, the first few frames of
	# droplets are buried inside the X Bot body.
	var exit_offset := Vector3(blood_dir.x, 0.0, blood_dir.z)
	if exit_offset.length_squared() > 0.0001:
		exit_offset = exit_offset.normalized() * 0.30
	var burst_pos := hit_pos + exit_offset
	PrototypeAttackIndicator.spawn_blood_burst(get_parent(), burst_pos, blood_dir, hit_mult, blood_type)
	# Per-hit ground droplets — small lobed stamps scattered in a cone
	# biased along the shot direction. Lands as faint, irregular drips
	# that read as "spray from the wound hit the floor", separate from
	# the bigger settle pool that forms when the corpse comes to rest.
	# Crits + bleed-rated weapons (melee_1h) get a richer scatter to
	# match the bigger spray burst.
	var droplet_count: int = 6
	if is_crit:
		droplet_count += 3
	if weapon_base_id == &"melee_1h":
		droplet_count += 4
	_stamp_hit_droplets(hit_pos, blood_dir, droplet_count)
	# Directional hit reaction — pick hit_left/right/back/big based on
	# where the hit came from relative to the enemy's facing. Threshold-
	# gated so a 5% graze doesn't stutter the chase mid-stride. Skipped
	# while in KNOCKBACK (the knockback motion IS the reaction).
	if _state != State.KNOCKBACK and max_health > 0:
		var dmg_pct: float = float(amount) / float(max_health)
		if is_crit or dmg_pct >= _HIT_REACT_MIN_DMG_PCT:
			_trigger_hit_react(knockback_from, is_crit or dmg_pct >= 0.25)
	var head := global_position + Vector3(0.0, 1.8, 0.0)
	DamageNumber.spawn(get_parent(), head, amount, multistrike, is_crit)
	# Subliminal "this is landing" layer. -15 dB was inaudible against the
	# weapon fire mix; -3 dB sits just under the weapon fire volume so the
	# pop reads as a confirmation rather than competing for attention.
	# Per-enemy throttle: multi-pellet weapons (shotgun = 12 pellets) all
	# resolve in the same frame, so without gating each pellet would
	# stack a full-volume hit_flesh and the result was painfully loud.
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_hit_sfx_msec >= _HIT_SFX_THROTTLE_MS:
		_last_hit_sfx_msec = now_ms
		WeaponSounds.play_generic(&"hit_flesh", global_position, -3.0)
	# Crit hitstop — brief time-scale dip on non-fatal crits from single-hit
	# weapons. Fatal crits route through _die for the longer crit-kill freeze.
	if is_crit and _health > 0:
		HitStop.on_crit(weapon_base_id)
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
	_visuals.play_hit_squash()
	_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween)
	# Splatter blood ON the character itself — parented to visual so it
	# follows movement / animation / ragdoll. Uses knockback_from as the
	# impact direction reference; falls back to a small forward offset
	# when knockback_from is zero (channel weapons, DoT ticks).
	if visual != null:
		var impact_pos: Vector3 = knockback_from if knockback_from != Vector3.ZERO else global_position + Vector3(0, 1.0, 0)
		PrototypeAttackIndicator.spawn_blood_on_character(visual, impact_pos, blood_type)
	_visuals.refresh_tooltip_if_hovered()
	# Broadcast hit visuals to all clients so every player sees every hit's
	# damage number, squash, and flash — not just the attacker.
	if NetState.is_in_lobby():
		_client_show_hit.rpc(amount, multistrike, is_crit)
	if _health <= 0:
		# Baseline death knockback even for weapons that carry no
		# knockback_bonus / skill.knockback (most normal weapons —
		# pistol, sniper, rifle, etc. — carry 0 by design so they don't
		# push enemies around mid-combat). The death moment IS where we
		# want a visible reaction, so derive a baseline from the killing
		# blow's damage. Big hits → bodies fly; little hits → modest
		# slide. The skill/weapon-driven knockback_strength still wins
		# when present (special skills, knockback_bonus affixes).
		var death_kb := knockback_strength
		if death_kb <= 0.0:
			# 0.4 m/damage gives sniper-class shots (50+ dmg) ≈ 20 force
			# = 8m slide + 2.4m arc; trash mob 5dmg = 2 force = 1m slide.
			death_kb = clampf(float(amount) * 0.4, 3.0, 25.0)
		_die(knockback_from, death_kb)

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


# Boss / named / affixed enemies are exempt from the IDLE tick-skip
# throttle. Bosses and named encounters are scripted set pieces;
# affixed (rare-pack) monsters often have aura effects (Vampiric heals
# allies, Threat radius pulses, etc.) that need per-tick processing.
func _is_special_enemy() -> bool:
	return is_boss or named_monster != null or not affixes.is_empty()


# Cheap squared-distance check against the cached player ref. Returns
# false when _player_ref hasn't resolved yet — that path is correct
# (the first non-skipped tick will resolve it via _chase_tick) and
# safer than returning true (a wrong "too far" classification could
# leave a fresh enemy permanently skipped if they spawned >25m away
# and never got a chance to tick).
func _is_far_from_player() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	return global_position.distance_squared_to(_player_ref.global_position) > _IDLE_SKIP_DISTANCE_SQ




## Restore HP up to max_health. Called by allied support enemies' ticks;
## a no-op on dead enemies (corpses don't recover).
func heal(amount: int) -> void:
	if not _is_alive() or amount <= 0:
		return
	var before := _health
	_health = mini(_health + amount, max_health)
	_visuals.update_health_bar()
	_visuals.refresh_tooltip_if_hovered()
	var gained := _health - before
	if gained > 0:
		_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween, HitFlash.HEAL_COLOR)
		var head := global_position + Vector3(0.0, 1.8, 0.0)
		DamageNumber.spawn_heal(get_parent(), head, gained)


func apply_damage_buff(magnitude: float, duration: float) -> void:
	_afflictions.apply_damage_buff(magnitude, duration)



func apply_curse(damage_pct: float, duration: float) -> void:
	_afflictions.apply_curse(damage_pct, duration)


# True when this enemy is currently controlled by the player (charmed
# via Doomsayer). The player's damage paths and debuffs check this and
# skip affected enemies — charmed enemies fight for the player, so
# player attacks would be friendly fire.
func is_player_friendly() -> bool:
	return _afflictions._charmed


# True when this enemy is actively pursuing the player (CHASING state and
# not on the player's team via charm). Used by the player's HP regen tick
# to gate "out of combat" — any nearby aggro'd enemy keeps regen paused
# even when the player isn't being hit. Knockback / stunned / grabbed
# count too: the enemy is meaningfully engaged, just not currently mobile.
func is_engaged_with_player() -> bool:
	if _afflictions._charmed:
		return false
	return _state == State.CHASING or _state == State.KNOCKBACK or _state == State.STUNNED or _state == State.GRABBED


## Frozen in place for `duration`. Interrupts whatever the enemy was doing
## (chase, mid-cast, return) by switching to State.STUNNED — the cast's
## post-windup _state check bails on its own. Refreshes to the longer of
## current vs new so a fresh proc never shortens an active stun. RETURNING
## enemies (leashed) ignore — leash is treated as CC immune.
func apply_ignite(dps: float, duration: float) -> void:
	_afflictions.apply_ignite(dps, duration)

func apply_bleed(duration: float, stacks: int = 1) -> void:
	_afflictions.apply_bleed(duration, stacks)

func apply_stun(duration: float) -> void:
	_afflictions.apply_stun(duration)


func is_charmable() -> bool:
	return not is_boss and named_monster == null and affixes.is_empty()

func apply_charm() -> bool:
	return _afflictions.apply_charm()

func release_charm() -> void:
	_afflictions.release_charm()

func apply_grab() -> bool:
	return _afflictions.apply_grab()

func release_grab() -> void:
	_afflictions.release_grab()

func apply_weaken(magnitude: float, duration: float) -> void:
	_afflictions.apply_weaken(magnitude, duration)

func apply_isr_mark() -> void:
	_afflictions.apply_isr_mark()

func remove_isr_mark() -> void:
	_afflictions.remove_isr_mark()



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
	if _afflictions._charmed and _is_target_alive(_afflictions._charm_target):
		return _afflictions._charm_target
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
	if new_state == State.CHASING:
		_chase_stuck_timer = 0.0
		_chase_last_dist_sq = 0.0
	# Active states need the anim ticking even off-screen (animation_finished
	# drives windup → fire / dismember triggers). IDLE-while-invisible is the
	# common case that pauses for perf — recompute on every state flip.
	_update_anim_player_active()


# Single source of truth for "should AnimationPlayer be active right now?"
# Reads two inputs — current visibility (set by LoS culler) and current
# state — and applies the policy: pause iff invisible AND idle. Called
# from visibility_changed and _change_state, so any input flip re-evaluates.
# Cheap (one bool read + at most one property write).
func _update_anim_player_active() -> void:
	if anim_player == null:
		return
	var should_pause: bool = not visible and _state == State.IDLE
	anim_player.active = not should_pause


func _physics_process(delta: float) -> void:
	if _is_remote_enemy():
		_remote_physics_process()
		_tick_facing(delta)
		return
	if _state == State.DEAD:
		return
	# Facing slew always runs (independent of distance throttle) so the
	# visual rotation isn't visibly chunky for distant enemies that
	# tick AI logic at lower rates.
	_tick_facing(delta)
	# Distance-throttle. Non-special enemies far from the player get a
	# reduced tick rate based on their state:
	#   - IDLE far  → 1 in _IDLE_TICK_DIVISOR (~10Hz)
	#   - CHASING far → 1 in _CHASE_TICK_DIVISOR (~20Hz, less aggressive)
	# CHASING-far throttle was added after firing was found to cascade
	# aggro across a pack, pulling 50+ distant idles into full-rate
	# CHASING in one frame (visible as Phys spiking to 50+ms when you
	# opened fire). Near enemies + special enemies always tick at full
	# 60Hz so attacks stay responsive.
	if not _is_special_enemy():
		var divisor: int = 0
		var far: bool = _is_far_from_player()
		if _state == State.IDLE:
			# Far IDLE: 10Hz. Near IDLE: 20Hz (won't react slow enough for
			# the player to notice — aggro fires within one ticked frame).
			divisor = _IDLE_TICK_DIVISOR if far else _NEAR_IDLE_TICK_DIVISOR
		elif _state == State.CHASING and far:
			divisor = _CHASE_TICK_DIVISOR
		# CHASING-near, CASTING, ATTACKING etc. stay at 60Hz for crisp
		# combat reactions (divisor stays 0 → no skip).
		if divisor > 1:
			_idle_skip_counter += 1
			if _idle_skip_counter < divisor:
				return
			_idle_skip_counter = 0
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_threat_retarget_t = maxf(0.0, _threat_retarget_t - delta)

	_crouch_probe_t -= delta
	if _crouch_probe_t <= 0.0:
		_crouch_probe_t = CROUCH_PROBE_INTERVAL
		_update_crouch_state()
	_jump_cooldown_remain = maxf(0.0, _jump_cooldown_remain - delta)
	if enemy_class != null and enemy_class.support_role != EnemyClass.SupportRole.NONE:
		_support_tick_t -= delta
		if _support_tick_t <= 0.0:
			_support_tick_t = enemy_class.support_interval
			_combat.emit_support()
	_combat.tick(delta)
	_afflictions.tick_curse(delta)
	_afflictions.tick(delta)

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
	_tick_footsteps()

	# Animation update — CASTING and KNOCKBACK own their own clips. JUMPING
	# plays the airborne pose. CROUCHING swaps in the crouch idle/walk pair.
	# Otherwise we fall back to the standard idle/run.
	# Guard: if the enemy died mid-tick (e.g. curse-expire auto-shot killed
	# it during _tick_curse above), skip the animation update so _die()'s
	# death clip / fallback pose isn't overwritten by the run/idle fallthrough.
	if _state == State.DEAD:
		return
	# Hit-react owns the picker for its brief window. Decrement here so
	# the timer counts in physics-frames; once it expires the locomotion
	# branch takes back over without snap-popping the hit anim. Speed
	# is passed through so a one-second Mixamo clip finishes inside the
	# 0.45s window (small) / 0.65s window (big).
	if _hit_react_remain > 0.0:
		_hit_react_remain -= delta
		if _hit_react_remain > 0.0 and not _hit_react_anim.is_empty():
			_play_anim(_hit_react_anim, _hit_react_speed)
			return
	var moving := _want_dir.length_squared() > 0.01
	# Class-aware stance — ranged enemies stand / move with the rifle
	# stance, melee enemies stay with the default unarmed stance.
	# Future: per-EnemyClass override (e.g. brute → axe_idle for
	# heavier silhouette).
	var is_ranged_enemy: bool = _combat != null and _combat.is_ranged()
	var weapon_class: StringName = &"rifle" if is_ranged_enemy else &"unarmed"
	# One-shot anim gate (axe_combo / punch swing, hit_react variants,
	# death). Without this, the moment cast_melee_attack flips state from
	# CASTING → CHASING after the windup, the very next picker tick
	# stomps the swing with the run/idle anim — visually the enemy reads
	# as "tried to swing, suddenly relaxed" and the user sees the slash
	# VFX with no follow-through. Mirrors the player-side _is_oneshot
	# gate added for melee combos.
	if _is_oneshot_anim_playing():
		if moving:
			_face_direction(_want_dir)
		return
	match _state:
		State.CASTING, State.KNOCKBACK:
			pass
		State.JUMPING:
			_play_anim(ANIM_JUMP)
		State.STUNNED, State.GRABBED:
			# Idle clip while frozen / lifted — no rigs have a dedicated
			# stun or grab pose. Freezing on the current frame would lock
			# unnatural mid-motion poses (mid-stride, mid-attack windup).
			_play_anim(XBotAnimations.idle_anim_for_class(weapon_class))
		_:
			if _crouching:
				_play_anim(ANIM_CROUCH_RUN if moving else ANIM_CROUCH_IDLE)
			elif moving:
				_play_anim(XBotAnimations.run_anim_for_class(weapon_class))
			elif is_ranged_enemy:
				# Ranged enemies hold the firing pose between shots
				# so their weapon stays visibly drawn. _play_fire_pose
				# branches HOLD/LOOP based on attack_cooldown vs clip
				# length so slow-firing enemies don't wobble (HOLD =
				# play once per attack windup, hold at end frame).
				_play_fire_pose(false)
			else:
				_play_anim(XBotAnimations.idle_anim_for_class(weapon_class))
			# Prefer _face_override (set by chase logic when we want to
			# look one way while moving another — e.g. ranged backpedal
			# keeps the weapon trained on the player). Falls back to the
			# move direction when no override is set.
			if _face_override.length_squared() > 0.0001:
				_face_direction(_face_override)
			elif moving:
				_face_direction(_want_dir)


# Pick a directional hit-react anim based on where the hit came from
# relative to the enemy's facing. Sets up the picker-suppression
# timer so the anim actually has time to play before the locomotion
# branch restarts idle/run. `big` triggers the heavy-impact variant
# regardless of direction.
func _trigger_hit_react(hit_from: Vector3, big: bool) -> void:
	if visual == null:
		_set_hit_react(ANIM_HIT_BIG if big else ANIM_HIT_BACK, big)
		return
	if big:
		_set_hit_react(ANIM_HIT_BIG, true)
		return
	# Hit direction in XZ. fallback to back when hit_from isn't set
	# (DoT, environment damage) — feels right since DoT comes "from
	# inside" / "ambient".
	var to_hit := global_position - hit_from
	to_hit.y = 0.0
	if to_hit.length_squared() < 0.0001:
		_set_hit_react(ANIM_HIT_BACK, false)
		return
	to_hit = to_hit.normalized()
	# Enemy faces along -visual.transform.basis.z (Godot convention:
	# forward is -Z). Project hit direction onto facing axes.
	var fwd: Vector3 = -visual.global_transform.basis.z
	var right: Vector3 = visual.global_transform.basis.x
	fwd.y = 0.0
	right.y = 0.0
	if fwd.length_squared() > 0.0001:
		fwd = fwd.normalized()
	if right.length_squared() > 0.0001:
		right = right.normalized()
	var dot_fwd: float = -to_hit.dot(fwd)  # negate: hit FROM front = +1
	var dot_right: float = -to_hit.dot(right)  # hit FROM right = +1
	# Wedge: front-back if |dot_fwd| > |dot_right|, else left-right.
	if absf(dot_fwd) > absf(dot_right):
		# Front hits feel like a chest-region impact — use the
		# generic "hit_big" (front-facing impact). Back hits get
		# the back-specific anim.
		_set_hit_react(ANIM_HIT_BACK if dot_fwd < 0.0 else ANIM_HIT_BIG, false)
	else:
		_set_hit_react(ANIM_HIT_RIGHT if dot_right > 0.0 else ANIM_HIT_LEFT, false)


# Sets the hit-react state vars in one place so the duration / speed
# constants stay in sync. `big` picks the heavier playback profile.
func _set_hit_react(anim_set: Array[StringName], big: bool) -> void:
	_hit_react_anim = anim_set
	if big:
		_hit_react_remain = _HIT_REACT_BIG_DURATION
		_hit_react_speed = _HIT_REACT_BIG_SPEED
	else:
		_hit_react_remain = _HIT_REACT_SMALL_DURATION
		_hit_react_speed = _HIT_REACT_SMALL_SPEED

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
			# Mirror the authority-path death visual: pick a random Mixamo
			# death anim. The legacy xbot/death (singular) candidate in
			# ANIM_DEATH never matches the library (which keys deaths as
			# xbot/death_0..N), so clients used to fall through to no
			# anim and the skeleton crumbled limp. Authority ragdoll
			# state is not synced today, so anim is the only client-side
			# death visual.
			var death_anim: StringName = XBotAnimations.random_death_anim()
			if not _play_anim([death_anim] as Array[StringName], 1.0):
				_play_anim(ANIM_DEATH, 1.0)
		return
	_state = synced_state as State
	# Update health bar from synced values.
	_health = net_health
	max_health = net_max_health
	_visuals.update_health_bar()
	# Animation from synced state — simplified, no crouch/jump on client yet.
	# Class-aware idle/run mirrors the authority picker so remotes see
	# the right stance.
	var is_ranged_remote: bool = _combat != null and _combat.is_ranged()
	var weapon_class_remote: StringName = &"rifle" if is_ranged_remote else &"unarmed"
	match _state:
		State.CASTING, State.KNOCKBACK:
			pass
		State.JUMPING:
			_play_anim(ANIM_JUMP)
		State.STUNNED, State.GRABBED:
			_play_anim(XBotAnimations.idle_anim_for_class(weapon_class_remote))
		_:
			# Infer movement from position delta — the synchronizer writes
			# global_position directly; velocity isn't meaningful on clients.
			var delta_pos := global_position - _net_prev_pos
			delta_pos.y = 0.0
			var moving := delta_pos.length_squared() > 0.0001
			if moving:
				_play_anim(XBotAnimations.run_anim_for_class(weapon_class_remote))
			elif is_ranged_remote:
				# Match the local picker — _play_fire_pose handles
				# HOLD vs LOOP based on the enemy's attack cooldown.
				_play_fire_pose(false)
			else:
				_play_anim(XBotAnimations.idle_anim_for_class(weapon_class_remote))
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
		if _afflictions._stun_remain > 0.0:
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


# Returns a kite-distance reduction (0 to RANGED_FRONT_ROW_PUSH) based on
# how many ranged allies are FURTHER from the target than this enemy. When
# multiple ranged enemies converge on the same target, the closest ones get
# the biggest push-in so they form a front row and leave LoS for the back.
func _front_row_kite_reduction(my_dist_sq: float, target_pos: Vector3) -> float:
	var allies := SpatialGrid.query_radius(global_position, RANGED_GROUP_SCAN_RADIUS, &"enemies")
	var total_ranged := 0
	var behind_me := 0  # allies further from target than me
	for ally: Node3D in allies:
		if ally == self:
			continue
		var e := ally as PrototypeEnemy
		if e != null and e._combat != null and e._combat.is_ranged() and e._state == State.CHASING:
			total_ranged += 1
			var ally_dist_sq := ally.global_position.distance_squared_to(target_pos)
			if ally_dist_sq > my_dist_sq:
				behind_me += 1
	if total_ranged == 0:
		return 0.0
	# Fraction of the group behind me: 1.0 = I'm the closest, 0.0 = I'm the furthest
	var front_ratio := float(behind_me) / float(total_ranged)
	return RANGED_FRONT_ROW_PUSH * front_ratio

# Drives IDLE / CHASING / RETURNING — _physics_process routes all three
# here. Each branch may transition between them; CASTING and JUMPING are
# entered from CHASING via _cast_attack / _on_link_reached.
func _chase_tick() -> void:
	# Reset the facing override every tick — branches that want it set
	# (currently just ranged-backpedal) will assign before returning.
	_face_override = Vector3.ZERO
	# Wall-stuck timer also resets whenever we're not in active backpedal
	# (handled in the backpedal branch). Reset here too so leaving the
	# backpedal range cleanly clears the timer for next time.
	if _state != State.CHASING:
		_wall_stuck_timer = 0.0
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
	if _afflictions._charmed and player_dist_sq > _FOLLOW_TELEPORT_DISTANCE * _FOLLOW_TELEPORT_DISTANCE:
		var snap_pos := player.global_position
		var bearing := randf() * TAU
		snap_pos.x += cos(bearing) * _FOLLOW_DISTANCE_TARGET
		snap_pos.z += sin(bearing) * _FOLLOW_DISTANCE_TARGET
		global_position = snap_pos
		velocity = Vector3.ZERO
		_want_dir = Vector3.ZERO
		_afflictions._charm_target = _pick_nearest_other_enemy()
		return

	if _afflictions._charmed and (_afflictions._charm_target == null or not _is_target_alive(_afflictions._charm_target)):
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
	# Special skill check disabled — enemy skills need a balance/design pass
	# before they're ready for playtest. Basic attacks still function.
	#var special := _combat.pick_skill(dist, has_los)
	#if special != null:
	#	_combat.cast_skill(target, to_target / dist, special)
	#	return

	if _combat.is_ranged() and not charmed:
		var base_kite := _combat.ranged_kite_distance()
		# Front-row stagger: when grouped with other ranged, the closest
		# enemies push in tighter so rear allies can get line of sight.
		var kite := maxf(base_kite - _front_row_kite_reduction(dist * dist, target.global_position), 1.5)
		if dist <= _combat.attack_range() and _attack_cd <= 0.0 and has_los:
			_holding_position = false
			_combat.cast_attack(target, to_target / dist)
			return
		if dist < kite * 0.7:
			# Wall-stuck check: if we've been trying to backpedal but
			# the actual horizontal velocity has been near zero for
			# WALL_STUCK_TIMEOUT seconds, treat as "wall behind me" and
			# commit to firing from here. Otherwise the enemy runs the
			# same futile back-step forever and the player can stand
			# still farming them.
			var actual_horiz_sq: float = velocity.x * velocity.x + velocity.z * velocity.z
			var delta_t: float = get_physics_process_delta_time()
			if actual_horiz_sq < _WALL_STUCK_VEL_SQ:
				_wall_stuck_timer += delta_t
			else:
				_wall_stuck_timer = 0.0
			if _wall_stuck_timer >= _WALL_STUCK_TIMEOUT and has_los:
				# Treat as the hold band → fire if cooldown allows, else
				# stand and stare. Picker face_override keeps weapon on
				# target so the locomotion branch doesn't spin them.
				_holding_position = true
				_face_override = to_target / dist
				_want_dir = Vector3.ZERO
				velocity.x = 0.0
				velocity.z = 0.0
				if _attack_cd <= 0.0:
					_combat.cast_attack(target, to_target / dist)
				return
			_holding_position = false
			var away := -to_target / dist
			_want_dir = away
			# Face the player while backpedaling — the picker's default of
			# "face the move direction" turned ranged enemies away from
			# their target. _face_override is consumed in the locomotion
			# branch above.
			_face_override = to_target / dist
			var back_speed := CHASE_SPEED * 0.55 * _crouch_speed_factor() * _combat.affix_move_speed_mult() * _combat._self_buff_speed_mult
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
	elif (dist <= _combat.attack_range() or (_holding_position and dist <= _combat.attack_range() + ATTACK_RANGE_HYSTERESIS)) and has_los:
		if dist <= _combat.attack_range() and _attack_cd <= 0.0:
			_holding_position = false
			_combat.cast_attack(target, to_target / dist)
		else:
			# Melee on cooldown — strafe sideways instead of standing
			# still. Per-enemy L/R bias from instance_id parity so a
			# pack doesn't all strafe the same way. _face_override
			# keeps the weapon on target while moving perpendicular.
			_holding_position = true
			_face_override = to_target / dist
			var to_target_norm := to_target / dist
			var perp := Vector3.UP.cross(to_target_norm).normalized()
			var strafe_dir := perp if (get_instance_id() & 1) == 0 else -perp
			var strafe_speed: float = CHASE_SPEED * 0.45 \
				* _crouch_speed_factor() \
				* _combat.affix_move_speed_mult() \
				* _combat._self_buff_speed_mult
			_want_dir = strafe_dir
			velocity.x = strafe_dir.x * strafe_speed
			velocity.z = strafe_dir.z * strafe_speed
		return

	# Reaching the chase block means the enemy is meaningfully outside
	# attack/kite range — explicitly drop the hold flag so the next
	# in-range entry uses the strict threshold, not the buffered one.
	_holding_position = false

	# Chase stuck detection: if the enemy hasn't closed distance for
	# CHASE_STUCK_TIMEOUT seconds, warp it to the next nav waypoint.
	# Catches enemies wedged on destructibles, props, or stale navmesh.
	var dist_sq := dist * dist
	var chase_progress := _chase_last_dist_sq - dist_sq
	_chase_last_dist_sq = dist_sq
	if chase_progress < CHASE_STUCK_PROGRESS_SQ * get_physics_process_delta_time():
		_chase_stuck_timer += get_physics_process_delta_time()
		if _chase_stuck_timer >= CHASE_STUCK_TIMEOUT:
			_chase_stuck_timer = 0.0
			if _nav_agent != null and _nav_agent.get_navigation_map().is_valid():
				_nav_agent.target_position = target.global_position
				# Keep _nav_last_target in sync with the explicit re-target
				# so the throttle below doesn't immediately push the same
				# position again next tick.
				_nav_last_target = target.global_position
				if not _nav_agent.is_navigation_finished():
					var warp_pos := _nav_agent.get_next_path_position()
					warp_pos.y = global_position.y
					global_position = warp_pos
	else:
		_chase_stuck_timer = 0.0

	# Pathfind via NavigationAgent — routes around walls and pit edges
	# instead of charging straight at the target. Falls back to direct
	# vector chase when no nav agent (legacy scene), no map (navmesh
	# bake hasn't finished yet), or the agent is already on top of the
	# target.
	var dir := to_target / dist
	if _nav_agent != null and _nav_agent.get_navigation_map().is_valid():
		# Only push a new target to the NavigationAgent3D when the target
		# has actually moved enough to justify a path recompute. With 100+
		# enemies chasing the player, doing this every tick spends real
		# CPU even when the player is standing still. See _NAV_REPATH_DIST_SQ
		# header for the threshold rationale.
		var tgt_pos: Vector3 = target.global_position
		if _nav_last_target.distance_squared_to(tgt_pos) >= _NAV_REPATH_DIST_SQ:
			_nav_agent.target_position = tgt_pos
			_nav_last_target = tgt_pos
		if not _nav_agent.is_navigation_finished():
			var next_pos := _nav_agent.get_next_path_position()
			var nav_dir := next_pos - global_position
			nav_dir.y = 0.0
			if nav_dir.length_squared() > 0.0001:
				dir = nav_dir.normalized()
	_want_dir = dir
	var chase_speed := _movement_speed_base() * _crouch_speed_factor() * _combat.affix_move_speed_mult() * _combat._self_buff_speed_mult
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed
	# Group spacing — small repulsion from other nearby CHASING enemies
	# so the pack spreads out around obstacles instead of merging into
	# one clump. Only applied to actively-chasing enemies (skipped for
	# holding-position and the strafe branch above) so it doesn't fight
	# the attack-range stopping logic.
	_apply_group_repulsion()


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


# Base movement speed before crouch / affix / per-tick modifiers. For
# charmed pets this returns the player's current move_speed so they can
# keep up at run pace. Non-charmed enemies use the normal CHASE_SPEED
# constant. Called by _chase_tick (chasing an enemy or returning to
# spawn) and _follow_player_loose (loose pet follow).
func _movement_speed_base() -> float:
	if _afflictions._charmed and _player_ref != null and is_instance_valid(_player_ref) and _player_ref is PrototypePlayer:
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
	if _afflictions._charmed:
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
		_afflictions._loose_running = false
		return
	var dir := to_player / dist
	var max_speed := _movement_speed_base() * 1.2 * _crouch_speed_factor() * _combat.affix_move_speed_mult()
	var excess := dist - _FOLLOW_DISTANCE_TARGET
	var speed := clampf(excess * _FOLLOW_SPRING_GAIN, 0.0, max_speed)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if _afflictions._loose_running:
		if speed < _LOOSE_RUN_STOP_SPEED:
			_afflictions._loose_running = false
	else:
		if speed > _LOOSE_RUN_START_SPEED:
			_afflictions._loose_running = true
	if _afflictions._loose_running:
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
	var return_speed := CHASE_SPEED * _crouch_speed_factor() * _combat.affix_move_speed_mult()
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

func _die(kill_from: Vector3 = Vector3.ZERO, kill_force: float = 0.0) -> void:
	_change_state(State.DEAD)
	# Death sting at the corpse position — distinct from hit_flesh so kills
	# feel weightier than chip damage. Run quiet so a horde clear doesn't
	# dominate the mix.
	WeaponSounds.play_generic(&"enemy_death", global_position, -12.0)
	# Kill hitstop — brief time-scale dip so the killing blow lands with
	# weight. Crit kills get the longest freeze.
	if _last_hit_was_crit:
		HitStop.on_crit_kill(_last_hit_weapon_base_id)
	else:
		HitStop.on_kill(_last_hit_weapon_base_id)
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
	# Strip every status-effect visual on death so corpses don't show
	# stale markers. Full reset so pool re-acquire starts clean.
	_afflictions.reset()
	PlayerState.gain_xp(PlayerState.xp_award_for_enemy(level))
	# On-kill sustain: notify all nearby players so each one heals from
	# their own gear stats. In SP there's only one; in MP every player
	# within range benefits (XP should follow the same pattern — tracked
	# as a follow-up).
	for p in get_tree().get_nodes_in_group(&"player"):
		if p is PrototypePlayer and p.is_alive():
			p.on_enemy_killed()
	_drop_credits()
	_drop_item()
	# Detach the enemy's equipped weapon and let it fall to the floor as
	# its own physics body. Visual flair on top of the random-item drop;
	# the dropped weapon isn't pickup-able (yet) — purely cosmetic.
	_drop_weapon_physically(kill_from)
	# Death blood — bigger spray than per-hit, plus a floor splatter at
	# the kill location. Crit kills get a more dramatic burst (sniper-
	# style explosive exit wound feel). Splatter decal is single-instance
	# per kill regardless of crit (the dismemberment kick is the crit
	# visual upgrade; doubling decals would just flood the floor cap).
	var death_pos := global_position + Vector3(0.0, 1.0, 0.0)
	var death_dir: Vector3 = (death_pos - kill_from) if kill_from != Vector3.ZERO else Vector3.UP
	death_dir.y = 0.7
	death_dir = death_dir.normalized()
	var death_mult: float = 6.0 if _last_hit_was_crit else 4.0
	PrototypeAttackIndicator.spawn_blood_burst(get_parent(), death_pos, death_dir, death_mult, blood_type)
	# Kill-site floor pool intentionally NOT spawned here — pools form
	# where the corpse actually lands instead (via _spawn_settle_pool
	# fired from _on_ragdoll_settled when the death anim / ragdoll
	# completes). Stamping at kill time scattered pools at every shot
	# location regardless of where the body ended up, which read as
	# floor mess that didn't correspond to any corpse.
	# Side-paint on nearby props/interactables still wants the kill-
	# site frame of reference (blood sprays outward from where the
	# wound opened, not where the body falls), so route that one piece
	# of spawn_blood_kill_scene's behavior directly.
	PrototypeAttackIndicator.spawn_blood_on_receivers(get_parent(), global_position, blood_type)
	# Wall splatter — cast horizontally in the spray direction; if we
	# hit a wall, paint it. Crits get extra perpendicular shots so the
	# wall mess looks more chaotic (1 main + 2 spread).
	_try_spawn_wall_blood(death_pos, death_dir, _last_hit_was_crit)
	# Death visuals — two branches:
	#
	#   Explosion / crit kills: ragdoll for the physics flair (limbs
	#     fly, body tumbles from the blast). A Mixamo death anim would
	#     look static next to a flying body, so we skip it.
	#
	#   Normal kills (the common path): play one of the Mixamo death
	#     anims through to its lying-down pose, then schedule the
	#     corpse despawn. No ragdoll — the anim is the visual.
	#
	# For meshes without a Skeleton3D (legacy UAL1 / Quaternius), both
	# branches fall through to _spawn_ragdoll_corpse — those rigs
	# never had a death anim hooked up, so the legacy ragdoll capsule
	# stays.
	var use_ragdoll := _last_hit_was_explosion or _last_hit_was_crit
	var did_skeletal_ragdoll := false
	var did_death_anim := false
	if visual != null:
		var skel := _find_skeleton(visual)
		if skel != null and use_ragdoll:
			# Stop the animation player so it can't fight physics — bones
			# now belong to the physics simulator. stop(true) keeps the
			# cached pose so the player's last state doesn't snap to t=0.
			if anim_player != null:
				anim_player.stop(true)
			# Ratelimit ragdoll setup+activate via the global queue. Each
			# setup() builds 20 PhysicalBone3D + Jolt joints (~30-50ms);
			# a 5-kill explosion would otherwise stack all five in one
			# frame and produce a 100-200ms hitch (perf logs confirmed
			# the correlation). await_slot returns true once a slot is
			# granted (max ~8-frame wait) or false if the budget
			# saturated — in which case we fall back to the legacy capsule
			# corpse rather than block further. Re-validate is_inside_tree
			# after the await; the enemy could be freed during a level
			# reload mid-death.
			var slot_gen := _generation
			var got_slot := await RagdollQueue.await_slot()
			if not is_inside_tree() or _generation != slot_gen:
				return
			if not got_slot:
				# Budget denied — degrade to legacy capsule corpse (cheap,
				# no per-bone rigid bodies). Set did_skeletal_ragdoll so
				# the fallback path below doesn't double-spawn.
				_spawn_ragdoll_corpse(kill_from, kill_force)
				if visual != null:
					visual.visible = false
				did_skeletal_ragdoll = true
				var gen3 := _generation
				await get_tree().create_timer(DEATH_HOLD).timeout
				if not is_inside_tree() or _generation != gen3:
					return
				_become_corpse()
				return
			XBotRagdoll.setup(skel)
			# Crit kills dismember 1-2 random tip bones (hands/feet/forearms).
			# Must happen between setup() and activate() — the dismember
			# step sets `joint_type = JOINT_TYPE_NONE` on the chosen bones,
			# and that value is read by physical_bones_start_simulation in
			# activate(). After sim starts, the dismembered bones have no
			# parent joint and fly free when impulses apply.
			var dismembered: Array[PhysicalBone3D] = []
			# Crit deaths always dismember (any weapon). Explosion deaths
			# roll a 25% chance. Both paths take 2 random tip bones —
			# hands/feet/forearms most likely to break off in either case.
			var should_dismember := _last_hit_was_crit or (_last_hit_was_explosion and randf() < 0.25)
			if should_dismember:
				dismembered = XBotRagdoll.dismember_random_tips(skel, 2)
			# Pass ZERO/0 — the kill impulse goes through
			# apply_explosion_impulse below so it benefits from the
			# physics-frame await (apply_central_impulse on a body that
			# hasn't yet been simulated is silently dropped, and the
			# impulse-inside-activate path doesn't await).
			XBotRagdoll.activate(skel, Vector3.ZERO, 0.0)
			_ragdoll_setup_done = true
			_ragdoll_simulating = true
			_ragdoll_settle_timer = 0.0
			set_process(true)  # _tick_ragdoll_settle runs while simulating
			add_to_group(&"ragdoll_corpses")
			did_skeletal_ragdoll = true
			# Body launch + dismember kick. Two independent triggers:
			#   - kill_force > 0: kinetic kill, launch body away from
			#     shooter (sniper round, etc.). 0.05 scale tunes for
			#     "visible shove + arc" without yeeting bodies room-
			#     length. Trash force=3 → 1.2 m/s; sniper force=20 → 8 m/s.
			#   - dismembered non-empty: limbs need their own outward kick
			#     OR they just dangle in place (no joint to inherit body
			#     motion from). Apply even on DoT/zero-force kills so the
			#     detach actually reads visually.
			# Both paths need a physics_frame await so the sim is live
			# when impulses land — apply_central_impulse on a body that
			# hasn't yet been simulated is silently dropped.
			if kill_force > 0.0 or not dismembered.is_empty():
				await get_tree().physics_frame
				if is_inside_tree() and is_instance_valid(self):
					if kill_force > 0.0:
						apply_explosion_impulse(kill_from, kill_force * 0.05)
					if not dismembered.is_empty():
						_apply_dismember_kick(kill_from, dismembered)
		elif skel != null:
			# Anim path — play a random Mixamo death clip and let it
			# settle into its lying-down pose. _on_ragdoll_settled
			# schedules the corpse despawn (sink tween + free) once the
			# anim finishes. Add to the ragdoll_corpses group so AoE
			# pushes (e.g. a late explosion landing nearby) can still
			# kick the body via apply_explosion_impulse.
			var death_anim: StringName = XBotAnimations.random_death_anim()
			var played := _play_anim([death_anim] as Array[StringName], 1.0)
			if not played:
				played = _play_anim(ANIM_DEATH, 1.0)
			if played:
				did_death_anim = true
				add_to_group(&"ragdoll_corpses")
				# Schedule the despawn pipeline when the anim finishes.
				# Lambda captures self.instance_id so a freed enemy
				# (level reset mid-death) doesn't fire the callback on
				# stale state.
				if anim_player != null:
					var enemy_id := get_instance_id()
					anim_player.animation_finished.connect(
						func(_anim_name: StringName) -> void:
							var e := instance_from_id(enemy_id) as PrototypeEnemy
							if e != null and is_instance_valid(e) and e.is_inside_tree():
								e._on_ragdoll_settled(),
						CONNECT_ONE_SHOT
					)
	# Fall through to the legacy ragdoll spawn for meshes without a
	# Skeleton3D, OR for X Bot meshes when neither branch succeeded
	# (e.g. anim couldn't resolve and ragdoll path was disabled).
	if not did_skeletal_ragdoll and not did_death_anim:
		_spawn_ragdoll_corpse(kill_from, kill_force)
		if visual != null:
			visual.visible = false
	var gen := _generation
	await get_tree().create_timer(DEATH_HOLD).timeout
	if not is_inside_tree() or _generation != gen:
		return
	_become_corpse()

# Ragdoll state. `_setup` is one-shot (PhysicalBone3D children built);
# `_simulating` flips on/off as the body launches → settles → gets
# explosion-pushed → settles again. The settle check runs in _process
# while simulating and calls physical_bones_stop_simulation() once the
# corpse has been at rest for _RAGDOLL_SETTLE_DURATION. Without this,
# 100 max corpses × 20 active rigid bodies = 2000 perpetually-integrated
# rigid bodies in the physics scene even when nothing's moving.
var _ragdoll_setup_done: bool = false
var _ragdoll_simulating: bool = false
var _ragdoll_settle_timer: float = 0.0
const _RAGDOLL_SETTLE_VELOCITY: float = 0.15  # m/s — below this counts as "at rest"
const _RAGDOLL_SETTLE_DURATION: float = 1.0   # seconds at rest before freezing

# Increments on every settle/shove — _despawn_after_settle captures the
# value at scheduling time and aborts if it doesn't match when its
# timer fires (i.e. corpse was shoved again, or pool re-acquired us).
var _despawn_token: int = 0
# instance_id of the RigidBody3D this enemy dropped on death (if any),
# stashed by _drop_weapon_physically and freed by the corpse despawn
# coroutine so the weapon disappears the same moment the corpse does.
var _dropped_weapon_body_id: int = 0
# Delay between ragdoll settling and the corpse starting to sink. Long
# enough that the kill-time splatter is the visual focus, short enough
# that bodies don't overstay their welcome at horde scale.
const _CORPSE_DESPAWN_DELAY: float = 10.0
# Duration of the sink-into-the-floor tween that hides the corpse before
# we release it. Avoids the "body abruptly disappears" snap by easing
# the visual down past Y=0. Depth is generous enough that the full
# skeleton (hip ~1m, head ~1.7m) ends up below the floor by the time
# the tween finishes.
#
# Scale-squash was tried initially but Jolt Physics rejects any non-
# uniform scale on collision shapes — the squash propagated through the
# Skeleton3D to every PhysicalBone3D capsule, flooding the debugger
# with "Failed to correctly scale body" warnings. Position-only sink
# leaves the skeleton uniformly scaled, no warnings.
const _CORPSE_SINK_DURATION: float = 1.4
const _CORPSE_SINK_DEPTH: float = 1.6     # m the visual drops past origin


func _process(delta: float) -> void:
	if _ragdoll_simulating:
		_tick_ragdoll_settle(delta)
	else:
		set_process(false)


# Polls every PhysicalBone3D's linear_velocity once per render frame.
# Cheap — ~20 vector length-squared reads. When the max bone velocity
# is below _RAGDOLL_SETTLE_VELOCITY for _RAGDOLL_SETTLE_DURATION
# straight, calls physical_bones_stop_simulation() so the simulator
# stops integrating these bodies. Re-acquired by apply_explosion_impulse
# (which calls physical_bones_start_simulation again before pushing).
func _tick_ragdoll_settle(delta: float) -> void:
	if visual == null:
		return
	var skel := _find_skeleton(visual)
	if skel == null:
		return
	var thresh_sq: float = _RAGDOLL_SETTLE_VELOCITY * _RAGDOLL_SETTLE_VELOCITY
	var still := true
	for child in skel.get_children():
		if not (child is PhysicalBone3D):
			continue
		if (child as PhysicalBone3D).linear_velocity.length_squared() >= thresh_sq:
			still = false
			break
	if not still:
		_ragdoll_settle_timer = 0.0
		return
	_ragdoll_settle_timer += delta
	if _ragdoll_settle_timer >= _RAGDOLL_SETTLE_DURATION:
		skel.physical_bones_stop_simulation()
		_ragdoll_simulating = false
		_ragdoll_settle_timer = 0.0
		# Settle hook handles the slow-grow puddle + corpse-despawn timer.
		# Don't disable _process here — the bleed-out ticker may still be
		# running. _process's combined guard at the bottom handles it.
		_on_ragdoll_settled()


# Called once the ragdoll has been at rest for _RAGDOLL_SETTLE_DURATION.
# Schedules the corpse despawn. If the corpse gets shoved by another
# explosion before the despawn timer fires, apply_explosion_impulse
# bumps _despawn_token to invalidate the pending despawn — a fresh
# _on_ragdoll_settled then reschedules when the body comes to rest
# again.
#
# Settle-pool: spawn a slow-growing pool of blood under the body where
# it actually came to rest. Routed through spawn_blood_decal so it
# attach-or-grows the kill-time pool if the corpse landed near the
# kill site, or stamps a fresh pool if the body tumbled away.
func _on_ragdoll_settled() -> void:
	_despawn_token += 1
	_spawn_settle_pool()
	_schedule_corpse_despawn(_despawn_token)


# Returns where the body actually came to rest, with Y dropped to the
# death-Y so the pool projects onto the floor instead of mid-air. Two
# paths converge here:
#
#   Ragdoll: centroid (XZ) of the active PhysicalBone3D children —
#     the physics sim moved them away from the enemy node's origin,
#     which still sits where the enemy was standing when it died.
#
#   Anim: hip bone position on the skeleton — the death animation
#     translates the hip in the armature (Mixamo death clips have
#     baked root motion: the character falls forward / collapses),
#     so the visible body ends up offset from global_position. The
#     enemy node itself doesn't move during anim playback, so reading
#     global_position would stamp the pool at the kill spot instead
#     of under the corpse.
#
# Falls back to global_position only when there's no skeleton at all.
func _settled_corpse_position() -> Vector3:
	if visual == null:
		return global_position
	var skel := _find_skeleton(visual)
	if skel == null:
		return global_position
	# Ragdoll path: average the active physics bones.
	var sum := Vector3.ZERO
	var n := 0
	for child in skel.get_children():
		if child is PhysicalBone3D:
			sum += (child as PhysicalBone3D).global_position
			n += 1
	if n > 0:
		var avg := sum / float(n)
		return Vector3(avg.x, global_position.y, avg.z)
	# Anim path: hip bone gives the body's actual settled position.
	# Both X Bot rig variants (mixamorig:Hips and mixamorig_Hips) are
	# handled by find_bone falling back to substring match.
	var hip_idx := skel.find_bone(&"mixamorig:Hips")
	if hip_idx == -1:
		hip_idx = skel.find_bone(&"mixamorig_Hips")
	if hip_idx == -1:
		hip_idx = skel.find_bone(&"Hips")
	if hip_idx != -1:
		var hip_world := skel.global_transform * skel.get_bone_global_pose(hip_idx).origin
		return Vector3(hip_world.x, global_position.y, hip_world.z)
	return global_position


func _spawn_settle_pool() -> void:
	if not is_inside_tree():
		return
	# New liquid-shader path: stamp into the per-fluid LiquidLayer's
	# accumulator SubViewport. Overlapping stamps blend additively in
	# the mask, so adjacent corpses' pools merge into one continuous
	# wet surface with no per-stamp silhouette. Pulls the layer for
	# this enemy's blood_type via the group LiquidLayer adds itself to.
	var layer_group: StringName = StringName("liquid_layer:" + String(blood_type))
	var layer := get_tree().get_first_node_in_group(layer_group) as LiquidLayer
	if layer == null:
		# Fallback: any liquid layer at all (covers legacy levels where
		# the blood_type-specific layer wasn't instanced). Better than
		# silently dropping the stamp.
		layer = get_tree().get_first_node_in_group(&"liquid_layer") as LiquidLayer
	if layer == null:
		return
	# Slow expansion: a single Sprite2D in the LiquidLayer's mask tweens
	# its scale from a small starting footprint up to the final pool
	# size over 2.5s. Cumulative additive draws across those frames
	# build the visible footprint smoothly — no step jumps like the
	# previous "stamp at increasing radii" scheduler produced.
	var settle_pos := _settled_corpse_position()
	# Per-corpse size variance — final radius rolls between 65% and
	# 130% of the base so kill aftermath isn't a uniform field of
	# identical pools. Larger pools tend to look darker (more alpha
	# accumulation in the center), smaller pools read as quick spills.
	var radius_jitter: float = randf_range(0.65, 1.3)
	var final_radius: float = _POOL_FINAL_RADIUS * radius_jitter
	layer.stamp_growing(settle_pos, _get_settle_stamp_texture(),
		_POOL_INITIAL_RADIUS, final_radius, _POOL_EXPANSION_DURATION, 1.0)
	# Gameplay slip-zone — standalone Area3D so the player still gets
	# the Traction-mediated slow/stumble when walking through this
	# pool. LiquidLayer is visual-only; gameplay needs its own node.
	# Radius slightly smaller than the visual pool so the effect
	# triggers only inside the bulk of the stain, not its faded edge.
	# Slip zone uses the FINAL pool size — the slow effect applies as
	# soon as the player steps on the spawn point, even before the
	# visual finishes oozing out.
	var container := get_parent()
	if container != null:
		PrototypeAttackIndicator.spawn_blood_slip_zone(container, settle_pos, 0.75)


# Settle pool expansion tuning. LiquidLayer.stamp_growing drives the
# growth — a single sprite tweens its scale from initial → final radius
# over duration seconds, additively painting the mask each frame.
const _POOL_EXPANSION_DURATION: float = 2.5
const _POOL_INITIAL_RADIUS: float = 0.18
# Scaled back from 1.45 — at that size + per-enemy jitter pools were
# covering most of the playable floor in dense combat. 0.85 keeps the
# "lots of blood" read while leaving clean floor between pools.
const _POOL_FINAL_RADIUS: float = 0.85


# Per-hit droplet scatter — stamps `count` tiny lobed splatters around
# `hit_pos` (at floor level) in a cone biased toward `hit_dir`. The
# stamps go through the same LiquidLayer as the settle pool, so they
# read as the same fluid and merge naturally with nearby pools.
#
# `hit_dir` is the shot direction (away from the shooter). Droplets
# bias toward the away side ≈ 70/30, modelling exit-wound spray rather
# than an omnidirectional spritz.
func _stamp_hit_droplets(hit_pos: Vector3, hit_dir: Vector3, count: int) -> void:
	if count <= 0 or not is_inside_tree():
		return
	var layer_group: StringName = StringName("liquid_layer:" + String(blood_type))
	var layer := get_tree().get_first_node_in_group(layer_group) as LiquidLayer
	if layer == null:
		layer = get_tree().get_first_node_in_group(&"liquid_layer") as LiquidLayer
	if layer == null:
		return
	# Drop droplets onto the floor under the enemy. Y is taken from
	# enemy feet so the stamp lands on the actual walkable surface
	# regardless of where the hit landed on the body.
	var floor_y: float = global_position.y
	# Bias the spray cone toward `hit_dir`. Flatten to XZ — droplets
	# travel along the floor, not up/down.
	var bias := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if bias.length_squared() > 0.0001:
		bias = bias.normalized()
	else:
		bias = Vector3.ZERO
	for i in count:
		var theta: float
		if bias != Vector3.ZERO and randf() < 0.7:
			# Forward arc: ±55° around bias direction.
			theta = atan2(bias.z, bias.x) + randf_range(-0.96, 0.96)
		else:
			theta = randf() * TAU
		# Scatter 0.6-2.0m out — far enough that drops read as
		# individual spray spots distinct from the eventual corpse pool,
		# not as inner ring stamps that immediately merge into it.
		var dist: float = randf_range(0.6, 2.0)
		var offset := Vector3(cos(theta) * dist, 0.0, sin(theta) * dist)
		var pos := Vector3(hit_pos.x, floor_y, hit_pos.z) + offset
		# Mixed sizes — most are small specks, a few are bigger
		# drips. Heavy weighting toward small via squared roll so a
		# busy fight produces lots of fine spatter with occasional
		# fatter splotches, not a uniform field of identical blobs.
		var size_roll: float = randf()
		size_roll *= size_roll
		var radius: float = lerp(0.06, 0.22, size_roll)
		var intensity: float = randf_range(0.65, 1.0)
		layer.stamp(pos, _get_settle_stamp_texture(), radius, intensity)


# 12 chaotic soft-alpha stamp variants. The perimeter is shaped by 2D
# FastNoise sampled around a polar ring rather than by clean
# sine-wave lobes — at large sizes, periodic sines produced obvious
# flower-petal silhouettes. Per-stamp also gets internal alpha noise
# so the interior isn't a uniform disk; combined with additive
# blending, this produces messy splatter shapes that look like
# spilled liquid rather than geometric blobs.
const _SETTLE_STAMP_VARIANT_COUNT: int = 12
static var _settle_stamp_textures: Array[Texture2D] = []
static func _get_settle_stamp_texture() -> Texture2D:
	if _settle_stamp_textures.is_empty():
		var size := 128
		var center := Vector2(size, size) * 0.5
		var base_r: float = float(size) * 0.40
		for i in _SETTLE_STAMP_VARIANT_COUNT:
			# Two-octave perimeter noise. Low-octave gives broad lobed
			# silhouettes, high-octave adds jagged finger-like detail at
			# the rim. Together: messy spilled-liquid shapes, not
			# perturbed circles.
			var rim_lo := FastNoiseLite.new()
			rim_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			rim_lo.seed = 0x4B5A11 + i * 0x9E3779B9
			rim_lo.frequency = 2.2
			var rim_hi := FastNoiseLite.new()
			rim_hi.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			rim_hi.seed = 0x7C0DE5 + i * 0x517CC1B7
			rim_hi.frequency = 7.0
			# Inner alpha noise — breaks up the uniform interior with
			# density variation, so the stamp doesn't look painted-on.
			var inner_noise := FastNoiseLite.new()
			inner_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			inner_noise.seed = 0xC0FFEE + i * 0x12345
			inner_noise.frequency = 6.0
			# Rim amplitudes. The low octave warps the silhouette into
			# broad bulges; the high octave (smaller amp) adds the
			# jagged finger detail. Combined max ≈ ±55%.
			var rim_amp_lo: float = 0.40
			var rim_amp_hi: float = 0.15
			# Random rotation of the noise space per variant so the
			# "natural" axis of each splat differs.
			var rot: float = float(i) * 0.83 + 1.3
			var cs := cos(rot)
			var sn := sin(rot)
			var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
			img.fill(Color(0, 0, 0, 0))
			for y in size:
				for x in size:
					var dx := float(x) - center.x
					var dy := float(y) - center.y
					var dist := sqrt(dx * dx + dy * dy)
					var angle := atan2(dy, dx)
					# Sample 2D noise on a unit circle at this angle —
					# gives non-periodic angular noise.
					var nx: float = cos(angle)
					var ny: float = sin(angle)
					var rnx: float = cs * nx - sn * ny
					var rny: float = sn * nx + cs * ny
					var rim_l: float = rim_lo.get_noise_2d(rnx, rny)
					var rim_h: float = rim_hi.get_noise_2d(rnx * 2.5, rny * 2.5)
					var max_r: float = base_r * (1.0 + rim_amp_lo * rim_l + rim_amp_hi * rim_h)
					if dist >= max_r:
						continue
					var d: float = dist / max_r
					# Quadratic falloff for smooth additive merging.
					var a: float = 1.0 - d * d
					# Internal density noise — multiplies alpha in [0.7, 1.0]
					# so the interior has subtle dark/light variation,
					# preventing the "smooth disk" read at large sizes.
					var inner: float = inner_noise.get_noise_2d(float(x) * 0.5, float(y) * 0.5)
					var density: float = 0.85 + 0.15 * inner
					a *= density
					img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
			_settle_stamp_textures.append(ImageTexture.create_from_image(img))
	return _settle_stamp_textures[randi() % _settle_stamp_textures.size()]


# Coroutine: wait _CORPSE_DESPAWN_DELAY, sink the corpse into the floor,
# then release. Token check at every await so a re-shove (which bumps
# _despawn_token) or pool re-acquire (which bumps _generation) aborts
# the chain without releasing a live enemy.
func _schedule_corpse_despawn(token: int) -> void:
	var gen := _generation
	await get_tree().create_timer(_CORPSE_DESPAWN_DELAY).timeout
	if not is_inside_tree() or _generation != gen:
		return
	if token != _despawn_token:
		return  # cancelled by a shove or pool re-acquire
	if _ragdoll_simulating:
		return  # safety: still moving (shouldn't happen given _despawn_token gating)
	# Sink the visual into the floor so the body fades out instead of
	# popping. Position-only — see _CORPSE_SINK_DEPTH note for why we
	# don't scale. Quadratic ease-in starts gentle (you notice it begin)
	# and accelerates (last 30% is fast — no lingering half-buried body).
	if visual != null:
		var sink_tween := create_tween()
		sink_tween.set_ease(Tween.EASE_IN)
		sink_tween.set_trans(Tween.TRANS_QUAD)
		var target_y: float = visual.position.y - _CORPSE_SINK_DEPTH
		sink_tween.tween_property(visual, ^"position:y", target_y, _CORPSE_SINK_DURATION)
		await sink_tween.finished
		# Re-check: a shove during the sink (rare — collision is off and
		# the body's already half-buried) or a level reset could invalidate
		# us between the timer fire and now.
		if not is_inside_tree() or _generation != gen:
			return
		if token != _despawn_token:
			return
	# Free the dropped weapon at the exact moment we release the corpse,
	# so weapon + body disappear together. No-op when this enemy never
	# dropped a weapon (bare-handed) or when the body was already freed
	# (level reload, scene change).
	_free_dropped_weapon_body()
	# Drop ourselves out of the corpse_manager ring so it doesn't try to
	# evict (and double-release) a pool-recycled body later.
	get_tree().call_group(&"corpse_manager", &"deregister_corpse", self)
	EntityPool.release(self)


# Releases the RigidBody3D this enemy dropped on death, if any. Mirrors
# the corpse sink: freeze physics, tween position.y down by the same
# _CORPSE_SINK_DEPTH over _CORPSE_SINK_DURATION, then queue_free. Safe
# to call multiple times — the second call sees instance_id == 0 and
# noops.
func _free_dropped_weapon_body() -> void:
	if _dropped_weapon_body_id == 0:
		return
	var b := instance_from_id(_dropped_weapon_body_id)
	_dropped_weapon_body_id = 0
	if b == null or not is_instance_valid(b):
		return
	var body := b as RigidBody3D
	if body == null or not body.is_inside_tree():
		(b as Node).queue_free()
		return
	# Stop physics so the sink tween can drive position.y without the
	# simulator fighting the descent every frame.
	body.freeze = true
	var sink_tween := body.create_tween()
	sink_tween.set_ease(Tween.EASE_IN)
	sink_tween.set_trans(Tween.TRANS_QUAD)
	var target_y: float = body.position.y - _CORPSE_SINK_DEPTH
	sink_tween.tween_property(body, ^"position:y", target_y, _CORPSE_SINK_DURATION)
	sink_tween.tween_callback(body.queue_free)


# Apply an impulse to the corpse via the active physics ragdoll. Matches
# the signature PrototypeRagdollCorpse uses so explosion code
# (PrototypeGrenade, PrototypeProjectile blasts) calls uniformly across
# both corpse types.
#
# X Bot corpses always have an active ragdoll by the time they're in the
# &"ragdoll_corpses" group (activated in `_die`), so this is a pure
# "push the rigid bodies" path. Pushes every bone, not just hip+spine,
# so limbs go flying in different directions — reads as "the explosion
# threw the body apart" rather than "the body slid sideways".
# Extra outward impulse applied to dismembered tip bones (hands / feet /
# forearms) on crit kills. The body-wide explosion impulse already
# pushes every bone — this adds an additional kick along the same
# direction so the now-unconstrained tips clearly separate from the
# torso instead of falling alongside it. Tuned to read as "limb flies
# off" not "limb yeeted into orbit".
const _DISMEMBER_KICK_FORCE: float = 18.0  # Δv ~14-18 m/s on hand/foot mass — limbs should clearly arc away, not dangle
# Lifetime of the cosmetic flying-limb prop spawned on dismemberment.
# Long enough to land + roll, short enough that horde fights don't
# accumulate dozens of detached limbs in the scene.
const _DISMEMBER_PROP_LIFETIME: float = 4.0
# Skin tint of the cosmetic limb prop. X Bot is a generic figure — pick
# a neutral mid-tone that reads as "flesh" without trying to match the
# actual character texture. Sits dark enough that the blood splatters
# overlapping it stay legible.
const _DISMEMBER_PROP_COLOR: Color = Color(0.55, 0.42, 0.36)

# Spawns separate physics-driven limb props at each dismembered bone +
# kicks the underlying ragdoll. Mixamo X Bot has a single skinned mesh
# spanning all bones, so flipping a bone's joint_type to NONE on its
# own just produces a rubber-arm stretch — the mesh vertices follow the
# detached bone but don't visually separate. The cosmetic props are
# what actually reads to the player as "limb flew off": discrete
# RigidBody3D capsules at the bone position, launched with the same
# outward bias as the body kick, free after _DISMEMBER_PROP_LIFETIME.
func _apply_dismember_kick(kill_from: Vector3, bones: Array[PhysicalBone3D]) -> void:
	var dir: Vector3 = global_position - kill_from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 1.0, 0.0)
	else:
		dir = dir.normalized()
		dir.y = 0.7  # bias up so parts arc, not skid along the floor
		dir = dir.normalized()
	for pb in bones:
		# Per-bone mass keeps Δv consistent: small hand (0.8kg) and big
		# foot (1.5kg) end up at similar launch speeds.
		pb.apply_central_impulse(dir * _DISMEMBER_KICK_FORCE * pb.mass)
		_spawn_dismember_prop(pb, dir)


# Cosmetic flying-limb prop — a small flesh-toned capsule spawned at
# the dismembered bone's current world position, given an outward
# velocity + random spin, and freed after _DISMEMBER_PROP_LIFETIME.
# Collides with the world but not enemies / player (corpse layer 32,
# world mask 1) so it doesn't shove anyone around as it lands.
func _spawn_dismember_prop(bone: PhysicalBone3D, kick_dir: Vector3) -> void:
	if not is_instance_valid(bone):
		return
	var parent := get_parent()
	if parent == null:
		return
	var bone_pos := bone.global_position
	# Hand / foot / forearm dimensions — slightly different per part so a
	# trail of detached limbs reads as a mix, not a row of identical
	# pills. Default to "forearm" size for unknown bone names.
	var prop_radius: float = 0.05
	var prop_height: float = 0.20
	var name_str := String(bone.bone_name)
	if name_str.ends_with("Hand"):
		prop_radius = 0.045
		prop_height = 0.12
	elif name_str.ends_with("Foot"):
		prop_radius = 0.055
		prop_height = 0.20
	# Build the rigid body + collision + visual mesh.
	var rb := RigidBody3D.new()
	rb.collision_layer = 32  # corpses
	rb.collision_mask = 1    # world only — doesn't shove player/enemies
	rb.gravity_scale = 1.4
	rb.mass = bone.mass * 0.6
	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = prop_radius
	caps.height = prop_height
	col.shape = caps
	rb.add_child(col)
	var mesh_inst := MeshInstance3D.new()
	var cmesh := CapsuleMesh.new()
	cmesh.radius = prop_radius
	cmesh.height = prop_height
	cmesh.radial_segments = 6
	cmesh.rings = 2
	mesh_inst.mesh = cmesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _DISMEMBER_PROP_COLOR
	mat.roughness = 0.7
	mesh_inst.material_override = mat
	# Don't cast shadow — at horde scale dozens of tiny flying capsules
	# making per-frame shadow updates is wasted work.
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mesh_inst)
	parent.add_child(rb)
	rb.global_position = bone_pos
	# Launch with the same outward bias as the body kick, plus random
	# spin so each prop tumbles differently.
	rb.linear_velocity = kick_dir * _DISMEMBER_KICK_FORCE * 0.6
	rb.angular_velocity = Vector3(
		randf_range(-12.0, 12.0),
		randf_range(-12.0, 12.0),
		randf_range(-12.0, 12.0),
	)
	# Capture the rigid body's instance_id (int — value type) instead of
	# binding queue_free directly to the Object. If the prop is freed
	# early (level reset, scene unload) before the timer fires, the
	# bound Callable would trip "Lambda capture freed" warnings.
	var rb_id: int = rb.get_instance_id()
	get_tree().create_timer(_DISMEMBER_PROP_LIFETIME).timeout.connect(func() -> void:
		var node := instance_from_id(rb_id) as Node
		if node != null:
			node.queue_free()
	)


# Wall blood splatter — casts horizontally in the spray direction; if
# the ray hits a wall (vertical surface, |normal.y| < 0.6), spawns a
# decal there. Crits cast three rays: the main spray direction plus
# ±45° perpendicular spread so the wall mess is more dramatic.
#
# Async because intersect_ray requires the physics frame; awaiting one
# is harmless here — _die already has a longer DEATH_HOLD wait below.
const _WALL_BLOOD_MAX_RANGE: float = 6.0
const _WALL_BLOOD_FLOOR_NORMAL_THRESHOLD: float = 0.6  # |n.y| above = floor/ceiling
func _try_spawn_wall_blood(start_pos: Vector3, spray_dir: Vector3, is_crit: bool) -> void:
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
		if not is_inside_tree() or not is_instance_valid(self):
			return
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return
	var space := PhysicsServer3D.space_get_direct_state(world.space)
	if space == null:
		return
	# Cast horizontally in the spray direction (drop Y so we hit walls,
	# not floors/ceilings).
	var dir := Vector3(spray_dir.x, 0.0, spray_dir.z)
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	# Build the cast list. Crits get spread; normal kills get one cast.
	var cast_dirs: Array[Vector3] = [dir]
	if is_crit:
		var spread_l := dir.rotated(Vector3.UP, deg_to_rad(45.0))
		var spread_r := dir.rotated(Vector3.UP, deg_to_rad(-45.0))
		cast_dirs.append(spread_l)
		cast_dirs.append(spread_r)
	for d in cast_dirs:
		var query := PhysicsRayQueryParameters3D.create(start_pos, start_pos + d * _WALL_BLOOD_MAX_RANGE, 1)
		var result := space.intersect_ray(query)
		if result.is_empty():
			continue
		var hit_normal: Vector3 = result["normal"]
		# Skip floors / ceilings — those get the regular floor splat path.
		if absf(hit_normal.y) > _WALL_BLOOD_FLOOR_NORMAL_THRESHOLD:
			continue
		PrototypeAttackIndicator.spawn_blood_wall_splatter(get_parent(), result["position"], hit_normal, blood_type)


const _EXPLOSION_FORCE_MULT: float = 8.0  # impulse scale; tune for carnage
# Per-bone vertical velocity cap after impulse. With _EXPLOSION_FORCE_MULT=8
# a close-blast impulse imparts Δv=12 m/s per bone, which lets compound
# explosions (two RPGs on the same corpse before it settles) tunnel
# PhysicalBone3Ds through the 0.6m ceiling collision box at wall_height=3m.
# Discrete CCD catches a single hit fine but stacks losing time.
# Cap at 8 m/s vertical → ballistic max-height = v²/2g ≈ 3.2m, just barely
# enough to graze the ceiling underside. Bodies still "launch" visibly,
# just don't escape the room. Horizontal velocity is intentionally NOT
# capped — sideways "carnage" still reads as intended.
const _RAGDOLL_MAX_UP_VELOCITY: float = 8.0
func apply_explosion_impulse(force_origin: Vector3, force_strength: float) -> void:
	if visual == null:
		return
	var skel := _find_skeleton(visual)
	if skel == null:
		return
	# Re-activate simulation if the corpse had settled and stopped. PBs
	# stay attached, so physical_bones_start_simulation just resumes the
	# integration. Need a physics_frame await after re-start so impulses
	# aren't dropped — same hazard as the initial death activation.
	var was_settled := _ragdoll_setup_done and not _ragdoll_simulating
	if was_settled:
		skel.physical_bones_start_simulation()
		_ragdoll_simulating = true
		_ragdoll_settle_timer = 0.0
		set_process(true)
		# Cancel the pending corpse-despawn — the body is moving again.
		# When it settles a second time, _on_ragdoll_settled reschedules.
		_despawn_token += 1
		await get_tree().physics_frame
		if not is_instance_valid(self) or not is_instance_valid(skel):
			return
	var dir: Vector3 = global_position - force_origin
	var dist: float = maxf(dir.length(), 0.1)
	dir = dir.normalized() if dist > 0.0001 else Vector3.UP
	dir.y = maxf(dir.y, 0.5)  # strong upward bias so bodies launch, not skid
	dir = dir.normalized()
	# Distance falloff — close to explosion = full strength, far = trail off.
	var falloff: float = clampf(1.0 - (dist / 8.0), 0.1, 1.0)
	for child in skel.get_children():
		if not (child is PhysicalBone3D):
			continue
		var pb := child as PhysicalBone3D
		pb.apply_central_impulse(dir * force_strength * pb.mass * falloff * _EXPLOSION_FORCE_MULT)
		# Clamp post-impulse vertical velocity so compound explosions can't
		# stack Δv past the ceiling-tunneling threshold. See constant comment.
		if pb.linear_velocity.y > _RAGDOLL_MAX_UP_VELOCITY:
			var v := pb.linear_velocity
			v.y = _RAGDOLL_MAX_UP_VELOCITY
			pb.linear_velocity = v
	# Bodies are moving again — reset the settle timer so the new motion
	# isn't immediately re-frozen by an already-counting-up timer.
	_ragdoll_settle_timer = 0.0


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


# Walks `root`'s MeshInstance3D descendants and unions their AABBs into
# a single AABB expressed in root's LOCAL space (root.transform itself
# contributes nothing — only the relative chain from each descendant
# back to root). Used to size + center the dropped-weapon collision so
# the box matches the visible silhouette.
func _compute_local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mi in _find_all_mesh_instances_under(root):
		var rel: Transform3D = _local_transform_chain(mi, root)
		var mi_aabb: AABB = rel * mi.get_aabb()
		if first:
			result = mi_aabb
			first = false
		else:
			result = result.merge(mi_aabb)
	return result


func _find_all_mesh_instances_under(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_find_all_mesh_instances_under(child))
	return out


func _local_transform_chain(descendant: Node3D, root: Node3D) -> Transform3D:
	# Compose descendant.transform up through parents until we hit root.
	# Excludes root.transform itself — we want descendant in root's
	# LOCAL coordinate frame.
	var t := Transform3D.IDENTITY
	var n: Node = descendant
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# Detaches the equipped weapon mesh and re-parents it under a fresh
# RigidBody3D so it falls, tumbles, and settles on the floor. No-op when
# the enemy has no weapon attached (bare-handed melee variants etc.) or
# when the visual / skeleton has already been torn down.
#
# Visual only — the dropped weapon isn't pickup-able. Despawns at the
# same _CORPSE_DESPAWN_DELAY as the corpse it came from so the floor
# clears at one consistent moment.
#
# Perf: each drop = 1 RigidBody3D + 1 CollisionShape3D + the existing
# weapon mesh. Jolt sleeps the body once it settles (linear+angular
# damp + can_sleep), so a horde-clear's bodies all idle after ~2-3s.
func _drop_weapon_physically(kill_from: Vector3) -> void:
	if visual == null:
		return
	var skel := _find_skeleton(visual)
	if skel == null:
		return
	var weapon := WeaponAttachment.detach_weapon(skel)
	if weapon == null:
		return  # bare hands

	var parent := _find_pickups_container() as Node3D
	if parent == null:
		parent = get_parent()
	if parent == null:
		weapon.queue_free()
		return

	var body := RigidBody3D.new()
	body.name = "DroppedWeapon"
	body.mass = 0.5
	body.linear_damp = 1.5
	# High angular damp — without it, a thin shape can rock or roll
	# noticeably on the floor. 5.0 brings rotation to rest in ~1s after
	# the initial toss while still letting the toss read as a tumble.
	body.angular_damp = 5.0
	# Off all collision_layers so no other body (player, enemies) can
	# scan it — player was getting snagged on dropped weapons because
	# the player capsule's mask includes world layer 1. Mask stays 1
	# so the weapon still detects + falls onto the floor.
	body.collision_layer = 0
	body.collision_mask = 1
	body.can_sleep = true

	# Re-parent the weapon visual under the rigid body. Reset its local
	# transform — the grip-offset that fit the hand bone is irrelevant
	# now that it's free in world space.
	body.add_child(weapon)
	weapon.transform = Transform3D.IDENTITY

	# Compute the weapon's local AABB so the collision shape matches the
	# real silhouette and we can re-center the mesh inside the body.
	# Most weapon meshes have their origin at the grip end, not the
	# geometric center — without recentering, half the mesh extends past
	# the body origin and clips through the floor when the body lies on
	# its side.
	var weapon_aabb := _compute_local_aabb(weapon)
	# Shift the visual so its AABB midpoint coincides with body origin.
	weapon.position = -weapon_aabb.get_center()

	# Box shape sized to the actual weapon — flat-on-floor stable
	# (boxes don't roll like capsules) and tightly fitted so visual
	# matches collision.
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = weapon_aabb.size.max(Vector3(0.05, 0.05, 0.05))
	shape_node.shape = box
	body.add_child(shape_node)

	parent.add_child(body)
	# Restore world position from the snapshot detach_weapon stashed,
	# so the body starts where the hand was, not at origin.
	var world_xform: Transform3D = weapon.get_meta(&"world_xform", Transform3D.IDENTITY)
	body.global_transform = world_xform

	# Toss it away from the kill direction with a small upward bias +
	# random spin. Magnitudes are modest — we want a tumble, not a
	# launch across the room.
	var away := (body.global_position - kill_from).normalized() if kill_from != Vector3.ZERO else Vector3.UP
	if away.length() < 0.01:
		away = Vector3.UP
	away.y = clampf(away.y + 0.6, 0.0, 1.0)
	body.linear_velocity = away.normalized() * 2.5
	body.angular_velocity = Vector3(
		randf_range(-3.0, 3.0),
		randf_range(-3.0, 3.0),
		randf_range(-3.0, 3.0),
	)

	# Stash the body's instance_id so _schedule_corpse_despawn can free
	# it at the exact moment the corpse releases — fires from the same
	# coroutine that frees this enemy, so weapon + corpse always go
	# away together regardless of how long the death anim or settle
	# took. instance_id (not a node ref) survives level reloads.
	_dropped_weapon_body_id = body.get_instance_id()

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


# ── Footstep SFX ────────────────────────────────────────────────────────────
# Distance-based footstep sounds, same pattern as the player. Enemies use
# the world-position path (not at-listener) so steps have spatial presence.

func _tick_footsteps() -> void:
	# spawn_puff stays false — N enemies in a fight would flood the screen
	# with dust puffs. spawn_bloody_prints flips on so enemies CAN leave
	# bloody trails after stepping in a pool: the print emission is
	# already gated by is_in_blood() + a per-step decrementing counter,
	# so out-of-blood enemies cost ~one is_in_blood() ring scan every
	# 0.7 m of movement, which is cheap.
	var result := Footsteps.tick(self, _footstep_accum, _footstep_last_pos,
		ENEMY_FOOTSTEP_DISTANCE, ENEMY_FOOTSTEP_DB, false, false, true)
	_footstep_accum = result[0]
	_footstep_last_pos = result[1]


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
	_visuals._hovered = false
	_visuals._tooltip_locked = false
	_visuals.refresh_outline()
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
	if floor_ring != null:
		floor_ring.visible = false
	get_tree().call_group(&"corpse_manager", &"register_corpse", self)

# Per-frame angular slew toward the most recent _face_direction target.
# rad/sec — 8.0 ≈ 458°/s, fast enough that the enemy reorients within
# ~0.4s for a full 180° flip but slow enough that the turn reads as
# physical motion instead of a snap. Tune here if specific
# weapon-class enemies need to turn faster/slower.
const _FACING_TURN_SPEED: float = 8.0

# True once any _face_direction call has been made on this instance.
# The first call snaps so a newly-spawned enemy doesn't slowly rotate
# from its imported default orientation. Subsequent calls only update
# the target; the slew runs in _tick_facing.
var _target_facing_y: float = 0.0
var _target_facing_set: bool = false

# Per-tick "face this direction even though we're moving differently"
# override. When non-zero, the locomotion picker uses this instead of
# _want_dir so backpedaling ranged enemies keep their weapon trained
# on the player rather than spinning to face away. Reset to Vector3.ZERO
# at the top of _chase_tick so the override is opt-in per frame.
var _face_override: Vector3 = Vector3.ZERO

# Wall-stuck detection for ranged backpedal. When a ranged enemy
# wants to back away from the player but velocity stays near zero
# (wall behind them), they used to spin in place trying. Now: track
# how long the actual velocity has been below WALL_STUCK_VEL_SQ
# while in backpedal mode. After WALL_STUCK_TIMEOUT seconds the
# chase tick switches them into "commit to firing from here"
# instead of futile backpedal. Resets on every successful step.
const _WALL_STUCK_VEL_SQ: float = 0.5 * 0.5   # < 0.5 m/s wished but not moving
const _WALL_STUCK_TIMEOUT: float = 0.35
var _wall_stuck_timer: float = 0.0


func _face_direction(dir: Vector3) -> void:
	if visual == null or dir.length_squared() < 0.0001:
		return
	# Compute the target yaw via a temp basis so we don't snap the
	# visual node on every call. Basis.looking_at returns the rotation
	# that points the basis's -Z along `dir` — same orientation
	# convention look_at uses, just without the in-place mutation.
	var target_xform := Transform3D.IDENTITY
	target_xform.basis = target_xform.basis.looking_at(dir, Vector3.UP)
	_target_facing_y = target_xform.basis.get_euler().y
	if not _target_facing_set:
		_target_facing_set = true
		visual.rotation.y = _target_facing_y


# Soft repulsion from other actively-chasing enemies inside
# _GROUP_REPULSION_RADIUS. Adds (not replaces) horizontal velocity
# so movement still primarily follows the navmesh; the push just
# spreads densely-packed chasers out instead of letting them clip
# through each other into one mass. Held-position and strafing
# enemies are skipped (they're not in the "marching toward target"
# path that benefits from spacing).
const _GROUP_REPULSION_RADIUS: float = 1.4    # meters
const _GROUP_REPULSION_MAX: float = 1.8       # m/s peak push
func _apply_group_repulsion() -> void:
	if SpatialGrid == null:
		return
	var nearby: Array[Node3D] = SpatialGrid.query_radius(
		global_position, _GROUP_REPULSION_RADIUS, &"enemies")
	if nearby.is_empty():
		return
	var push := Vector3.ZERO
	for n in nearby:
		if n == self or n == null or not is_instance_valid(n):
			continue
		# Skip non-chasing neighbors so we don't push the held melee
		# enemies away from their attack position.
		if n is PrototypeEnemy:
			var e := n as PrototypeEnemy
			if e._state != State.CHASING or e._holding_position:
				continue
		var away := global_position - n.global_position
		away.y = 0.0
		var d: float = away.length()
		if d < 0.001 or d >= _GROUP_REPULSION_RADIUS:
			continue
		# Stronger when closer; zero at the radius edge.
		var strength: float = 1.0 - (d / _GROUP_REPULSION_RADIUS)
		push += (away / d) * strength
	if push.length_squared() < 0.0001:
		return
	# Cap the combined push so a dense cluster doesn't catapult the
	# enemy sideways at high speed.
	var len: float = push.length()
	if len > 1.0:
		push = (push / len)
	velocity.x += push.x * _GROUP_REPULSION_MAX
	velocity.z += push.z * _GROUP_REPULSION_MAX


# Smoothly rotates the visual toward the latest _face_direction target.
# Called from _physics_process; handles wrap-around via rotate_toward.
func _tick_facing(delta: float) -> void:
	if visual == null or not _target_facing_set:
		return
	visual.rotation.y = rotate_toward(
		visual.rotation.y, _target_facing_y, _FACING_TURN_SPEED * delta
	)

# Play a melee swing clip with playback speed calibrated so its visible
# impact frame lands at `impact_time` seconds from now. Used by EnemyCombat
# for blade / sledgehammer / heavy strikes — the previous fixed 1.6× speed
# made axe_combo clips peak ~0.4s in regardless of the weapon's actual
# windup, so sledge (windup 0.7s) showed the strike well before the damage
# moment. Computed: speed = (anim.length * SWING_IMPACT_FRAME_RATIO) / impact_time.
# Speed is clamped to [0.5, 2.5] so extreme windups don't grind to slow-
# motion or blur the swing into nothing.
const SWING_IMPACT_FRAME_RATIO: float = 0.5   # axe_combo clips peak ~mid-clip
func _play_swing_to_impact(candidates: Array[StringName], impact_time: float) -> void:
	if anim_player == null or impact_time <= 0.0:
		_play_anim(candidates, 1.6)
		return
	for anim_name in candidates:
		if not anim_player.has_animation(anim_name):
			continue
		var anim: Animation = anim_player.get_animation(anim_name)
		if anim == null or anim.length <= 0.0:
			continue
		var natural_impact: float = anim.length * SWING_IMPACT_FRAME_RATIO
		var speed: float = clampf(natural_impact / impact_time, 0.5, 2.5)
		_play_anim([anim_name], speed)
		return
	_play_anim(candidates, 1.6)


# Ranged-enemy fire pose with HOLD/LOOP branching, matching the player
# helper of the same name. Slow attack_cooldown ≥ clip.length triggers
# HOLD mode (play once per shot, freeze at end frame); faster cadences
# stay in LOOP mode with speed clamped so the recoil cycle doesn't
# wobble against the shot timing.
#
#   restart=true  → per-shot fire event (force restart from frame 0
#                    so the recoil cycle is visible)
#   restart=false → per-tick locomotion picker (leave the anim alone
#                    if it's playing or held)
func _play_fire_pose(restart: bool = false) -> bool:
	if anim_player == null:
		return false
	var chosen: StringName = &""
	for key in ANIM_FIRE:
		if anim_player.has_animation(key):
			chosen = key
			break
	if chosen == &"":
		return false
	var clip: Animation = anim_player.get_animation(chosen)
	if clip == null or clip.length <= 0.0:
		return _play_anim([chosen], 1.0)
	var fire_int: float = 1.0
	if _combat != null:
		fire_int = _combat.attack_cooldown()
	if fire_int <= 0.0:
		return _play_anim([chosen], 1.0)
	var is_slow: bool = fire_int > clip.length * 1.05
	var name_str: String = String(chosen)
	if is_slow:
		clip.loop_mode = Animation.LOOP_NONE
		var assigned: String = anim_player.assigned_animation
		var current: String = anim_player.current_animation
		if restart:
			_fire_pose_holding = false
			anim_player.speed_scale = 1.0
			anim_player.play(name_str, 0.15)
			return true
		if _fire_pose_holding and assigned == name_str:
			# Held at end frame — leave it.
			return true
		if current == name_str and anim_player.is_playing():
			# Mid-cycle on the fire anim — leave it.
			return true
		# Some other anim is showing (e.g. just transitioned from RUN),
		# or first frame after the enemy entered the ranged-ready state
		# before any shot fired. Start fresh.
		_fire_pose_holding = false
		anim_player.speed_scale = 1.0
		anim_player.play(name_str)
		return true
	# LOOP mode — continuous cycle scaled to attack_cooldown, clamped.
	clip.loop_mode = Animation.LOOP_LINEAR
	_fire_pose_holding = false
	var speed: float = clip.length / fire_int
	speed = clampf(speed, 0.5, 1.3)
	return _play_anim([chosen], speed)


func _play_anim(candidates: Array[StringName], speed: float = 1.0,
		blend: float = 0.15) -> bool:
	if anim_player == null:
		return false
	for anim_name in candidates:
		if not anim_player.has_animation(anim_name):
			continue
		var name_str := String(anim_name)
		# Always sync speed_scale to the requested speed, even on the
		# early-out path below. Otherwise an idle anim that's already
		# playing keeps whatever speed_scale was set by the last
		# non-1.0 call (most commonly a melee swing at 1.4-1.6×) —
		# manifests as the enemy's idle loop visibly wobbling at fast
		# playback after attacking. Reset before the early-out so
		# subsequent same-anim calls correct themselves.
		anim_player.speed_scale = speed
		if anim_player.current_animation == name_str and anim_player.is_playing():
			return true
		# Pass blend so transitions between run/idle/attack-windup pose
		# cross-fade instead of snapping. 0.15s is the player's default
		# and reads as natural posture-shift, not slow morph.
		anim_player.play(name_str, blend)
		return true
	return false

# True while a LOOP_NONE one-shot anim (swing, hit-react, death, jump)
# is mid-playback. Used by the locomotion picker in _process_visual_state
# to suppress run/idle overrides until the one-shot finishes — without
# this, the moment the state machine ticks out of CASTING the swing gets
# stomped on the next frame. The 0.05s end buffer prevents the gate
# from latching on the last sample (off-by-one with floating-point
# position vs length).
func _is_oneshot_anim_playing() -> bool:
	if anim_player == null or not anim_player.is_playing():
		return false
	var current: StringName = anim_player.current_animation
	if current == &"":
		return false
	var anim: Animation = anim_player.get_animation(current)
	if anim == null:
		return false
	if anim.loop_mode != Animation.LOOP_NONE:
		return false
	return anim_player.current_animation_position < anim_player.current_animation_length - 0.05


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
