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
const CHASE_STUCK_TIMEOUT := 2.0
const CHASE_STUCK_PROGRESS_SQ := 1.0  # must close ~1m in 2s or stuck
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
const ANIM_CROUCH_IDLE := CombatConstants.ANIM_CROUCH_IDLE
const ANIM_CROUCH_RUN: Array[StringName] = [&"Crouch_Walk_Forward", &"Crouch_Walk", &"CROUCH_WALK", &"Crouch_Idle", &"CROUCH_IDLE"]
const ANIM_JUMP := CombatConstants.ANIM_JUMP
const ANIM_DEATH := CombatConstants.ANIM_DEATH

const OUTLINE_GROW := 0.04
const OUTLINE_LOCKED_COLOR := Color(1.0, 0.15, 0.15)

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
var _last_hit_weapon_base_id: StringName = &""
var _last_hit_was_crit: bool = false
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
	# this is safe / idempotent).
	if visual != null:
		var default_skel := _find_skeleton(visual)
		if default_skel != null:
			_normalize_skeleton_bone_prefix(visual, default_skel)


# Move every MeshInstance3D under `visual` off the default visual layer
# (1) onto layer 2. Blood decals project with cull_mask = layer 1 only,
# so decals stop painting themselves onto the character mesh — which
# would otherwise stick to the world-space spot where the decal was
# spawned, looking detached when the corpse moves (ragdoll launch, sink
# tween). The camera's default cull_mask covers all 20 layers, so
# layer-2 meshes remain visible to the player.
func _isolate_visual_from_decals() -> void:
	if visual == null:
		return
	_walk_set_visual_layers(visual, 2)


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
	if enemy_class == null or enemy_class.character_mesh == null:
		return
	if visual == null:
		return
	# Skip if the current Character already came from this scene —
	# checking scene_file_path is the cheapest way to compare since
	# PackedScene resource_path is canonical.
	var current_char := visual.get_node_or_null(^"Character") as Node3D
	if current_char != null and current_char.scene_file_path == enemy_class.character_mesh.resource_path:
		return
	if current_char != null:
		visual.remove_child(current_char)
		current_char.queue_free()
	var new_char := enemy_class.character_mesh.instantiate() as Node3D
	if new_char == null:
		return
	new_char.name = "Character"
	visual.add_child(new_char)
	# Per-class yaw correction for meshes authored facing the wrong
	# axis (military_man faces opposite X Bot, so the class sets PI).
	if absf(enemy_class.mesh_yaw_offset) > 0.0001:
		new_char.rotation.y = enemy_class.mesh_yaw_offset
	# Re-resolve anim_player — the @onready cached the OLD Character's
	# AnimationPlayer, which is about to be freed. find_child walks the
	# subtree because the FBX-imported scene's AnimationPlayer node may
	# be at a non-fixed path depending on importer version.
	var new_ap := new_char.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if new_ap != null:
		anim_player = new_ap
		XBotAnimations.install_on(anim_player)
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
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
		_hit_tween = null
	_apply_level_stats()
	# Apply the EnemyClass's character_mesh override AFTER _apply_level_stats
	# so any named-monster class swap (which happens inside that function)
	# is in effect first — the named monster's class drives the mesh, not
	# the spawner-set base class.
	_apply_class_mesh()
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
	var head := global_position + Vector3(0.0, 1.8, 0.0)
	DamageNumber.spawn(get_parent(), head, amount, multistrike, is_crit)
	# Subliminal "this is landing" layer. -15 dB was inaudible against the
	# weapon fire mix; -3 dB sits just under the weapon fire volume so the
	# pop reads as a confirmation rather than competing for attention.
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
	_visuals.update_health_bar()
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
			_holding_position = false
			var away := -to_target / dist
			_want_dir = away
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
		_nav_agent.target_position = target.global_position
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
	# Kill scene = primary splat + 2-4 satellite stains. Direction
	# biases the spray pattern away from the shooter so the gore arcs
	# toward where the body's heading.
	PrototypeAttackIndicator.spawn_blood_kill_scene(get_parent(), global_position, death_dir, blood_type)
	# Wall splatter — cast horizontally in the spray direction; if we
	# hit a wall, paint it. Crits get extra perpendicular shots so the
	# wall mess looks more chaotic (1 main + 2 spread).
	_try_spawn_wall_blood(death_pos, death_dir, _last_hit_was_crit)
	# Death = immediate limp ragdoll. Two variants depending on which
	# character mesh is in use:
	#
	#   X Bot (has a Skeleton3D with the PhysicalBone3D rig that
	#     XBotRagdoll.setup builds): stop the animation player, build the
	#     physical bones, activate physics with the kill impulse. Body
	#     goes limp and falls under gravity; impact direction launches it
	#     via apply_central_impulse on the hip/spine bones.
	#
	#     Known visual: Godot 4.6.2's PhysicalBoneSimulator initialises
	#     each rigid body from the bone REST pose (T-pose for Mixamo)
	#     regardless of pre-start state. There's a brief frame of T-pose
	#     at the moment of activation before gravity + impulse take over
	#     — usually hidden by the body's immediate motion. See
	#     `project_xbot_ragdoll` memory for the diagnostic history.
	#
	#   Legacy UAL1 / Quaternius (no Skeleton3D): fall through to the
	#     PrototypeRagdollCorpse spawn — duplicates the visual onto a
	#     RigidBody3D capsule that tumbles, hides the original.
	var did_skeletal_ragdoll := false
	if visual != null:
		var skel := _find_skeleton(visual)
		if skel != null:
			# Stop the animation player so it can't fight physics — bones
			# now belong to the physics simulator. stop(true) keeps the
			# cached pose so the player's last state doesn't snap to t=0.
			if anim_player != null:
				anim_player.stop(true)
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
	if not did_skeletal_ragdoll:
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
# Delay between ragdoll settling and the corpse starting to sink. Long
# enough that the kill-time splatter is the visual focus, short enough
# that bodies don't overstay their welcome at horde scale.
const _CORPSE_DESPAWN_DELAY: float = 5.0
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
# again. Death-time splatters carry the visual blood; no per-corpse
# pool is spawned here (removed to let the death splatter shapes read
# instead of getting covered by a smooth puddle).
func _on_ragdoll_settled() -> void:
	_despawn_token += 1
	_schedule_corpse_despawn(_despawn_token)


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
	# Drop ourselves out of the corpse_manager ring so it doesn't try to
	# evict (and double-release) a pool-recycled body later.
	get_tree().call_group(&"corpse_manager", &"deregister_corpse", self)
	EntityPool.release(self)


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
	var result := Footsteps.tick(self, _footstep_accum, _footstep_last_pos,
		ENEMY_FOOTSTEP_DISTANCE, ENEMY_FOOTSTEP_DB, false)
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
