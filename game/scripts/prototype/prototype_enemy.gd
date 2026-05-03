extends CharacterBody3D
class_name PrototypeEnemy

signal died

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
const ITEM_DROP_CHANCE_BASE: float = 0.12
const ITEM_DROP_CHANCE_PER_LEVEL: float = 0.06
# Item level rolls within this window around the player's current level so
# drops stay relevant — not 1-100 spread.
const ITEM_DROP_ILVL_OFFSET_MIN: int = -1
const ITEM_DROP_ILVL_OFFSET_MAX: int = 1

const GRAVITY := 22.0
const CHASE_SPEED := 3.2
const AGGRO_RANGE := 10.0
const GROUP_AGGRO_RANGE := 8.0
# Default attack params — used when `enemy_class` is null. Once every enemy
# scene has an EnemyClass assigned, these become unused and can be deleted.
# Until then they preserve current behaviour for unconfigured spawns.
const DEFAULT_ATTACK_RANGE := 2.2
const DEFAULT_ATTACK_COOLDOWN := 1.6
const DEFAULT_ATTACK_WINDUP := 0.4
const DEFAULT_ATTACK_CONE_DEG := 80.0
const DEFAULT_ATTACK_KNOCKBACK := 5.0
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
# Returning enemies take this fraction of damage (5% — effectively immune)
# and skip knockback entirely. Stops the player from kiting an enemy past
# its leash and then sniping it on the walk back.
const RETURNING_DAMAGE_MULT := 0.05

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
# Tuned so L1 sits near the previous fixed values (40 HP / 10 dmg) and each
# step up roughly 1.6×s the threat to keep scaling readable in friends-mode.
const MAX_LEVEL := 3
const LEVEL_HP_RANGE: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(30, 45),
	Vector2i(55, 80),
	Vector2i(90, 130),
]
const LEVEL_DAMAGE_RANGE: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(8, 12),
	Vector2i(14, 20),
	Vector2i(22, 30),
]
# Floor-ring emission color per level. Higher levels glow hotter so a player
# can read threat at a glance from across the room.
const LEVEL_RING_EMISSION: Array[Color] = [
	Color.BLACK,
	Color(1.0, 0.3, 0.18),
	Color(1.0, 0.65, 0.15),
	Color(1.0, 0.25, 0.05),
]

# Boss tuning: levels above the trash cap, multipliers stacked on the rolled
# stats, and a deep-red glow distinct from any trash tier.
const BOSS_LEVEL := 5
const BOSS_HP_MULT := 3.0
const BOSS_DAMAGE_MULT := 1.5
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
## Enemy level. 0 means "auto-roll 1..MAX_LEVEL on init"; spawners that want
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
var _player_ref: Node3D
var _outlined_meshes: Array[MeshInstance3D] = []
var _hover_hooked: bool = false
var _hovered: bool = false
# Locked overrides hovered: red persists past mouse-exit until LMB release.
var _tooltip_locked: bool = false
var _hit_tween: Tween
var _hit_flash_tween: Tween
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
var _floor_ring_mat: StandardMaterial3D
@onready var _nav_agent: NavigationAgent3D = $NavigationAgent3D
# Spawn position captured on reset() — enemies leash back to this point
# when they chase too far. Set whenever the enemy is reused from the pool
# at a new position.
var _spawn_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	_init_enemy()
	_setup_hover()

func _init_enemy() -> void:
	add_to_group(&"enemies")
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
	_health = max_health
	_state = State.IDLE
	_knockback_remain = 0.0
	_attack_cd = 0.0
	_want_dir = Vector3.ZERO
	_player_ref = null
	set_physics_process(true)
	collision_layer = 2
	collision_mask = 1 | 2 | 4
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
		_stand_test_shape.radius = 0.55
		_stand_test_shape.height = STAND_HEIGHT
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
## anything else (including pooled re-acquires) auto-rolls 1..MAX_LEVEL.
func _apply_level_stats() -> void:
	if is_boss:
		_apply_boss_stats()
		return
	var lv := clampi(level, 0, MAX_LEVEL)
	if lv <= 0:
		lv = randi_range(1, MAX_LEVEL)
	level = lv
	var hp_range := LEVEL_HP_RANGE[lv]
	var dmg_range := LEVEL_DAMAGE_RANGE[lv]
	max_health = randi_range(hp_range.x, hp_range.y)
	_attack_damage = randi_range(dmg_range.x, dmg_range.y)
	_apply_floor_ring_tint(lv)

func _apply_boss_stats() -> void:
	level = BOSS_LEVEL
	var top_hp := LEVEL_HP_RANGE[MAX_LEVEL]
	var top_dmg := LEVEL_DAMAGE_RANGE[MAX_LEVEL]
	max_health = int(round(randi_range(top_hp.x, top_hp.y) * BOSS_HP_MULT))
	_attack_damage = int(round(randi_range(top_dmg.x, top_dmg.y) * BOSS_DAMAGE_MULT))
	if visual != null:
		visual.scale = Vector3.ONE * BOSS_VISUAL_SCALE
	_apply_floor_ring_tint_color(BOSS_RING_EMISSION)
	add_to_group(&"bosses")

func _roll_display_name() -> void:
	if randf() < 0.4:
		var prefix: String = NAME_PALETTE_NUMBERED[randi() % NAME_PALETTE_NUMBERED.size()]
		display_name = "%s %02d" % [prefix, randi_range(1, 99)]
	else:
		display_name = NAME_PALETTE[randi() % NAME_PALETTE.size()]

func _apply_floor_ring_tint(lv: int) -> void:
	_apply_floor_ring_tint_color(LEVEL_RING_EMISSION[lv])

func _apply_floor_ring_tint_color(color: Color) -> void:
	if floor_ring == null:
		return
	if _floor_ring_mat == null:
		_floor_ring_mat = StandardMaterial3D.new()
		_floor_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_floor_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_floor_ring_mat.albedo_color = Color(0, 0, 0, 0)
		_floor_ring_mat.emission_enabled = true
		_floor_ring_mat.emission_energy_multiplier = 3.0
	_floor_ring_mat.emission = color
	floor_ring.material_override = _floor_ring_mat

## Called by EntityPool.release() before pooling. Disconnects stale listeners.
func _pool_release() -> void:
	for conn in died.get_connections():
		died.disconnect(conn["callable"])
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
	_init_enemy()
	# EnemySpawner sets global_position right before calling reset(), so
	# capturing here gives us the correct spawn point even when the enemy
	# is reused from the pool at a new location.
	_spawn_position = global_position

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
		_hover_hooked = true

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
	var label := "%s  %s" % [display_name, tr("HUD_LEVEL_FORMAT") % level]
	get_tree().call_group(&"interactable_tooltip", &"show_text", label)

func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_outline()
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func set_tooltip_locked(on: bool) -> void:
	_tooltip_locked = on
	_refresh_outline()

func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0, multistrike: int = 1, is_crit: bool = false) -> void:
	if not _is_alive():
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
	_health -= amount
	_update_health_bar()
	var head := global_position + Vector3(0.0, 1.8, 0.0)
	DamageNumber.spawn(get_parent(), head, amount, multistrike, is_crit)
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
	if _state == State.IDLE:
		aggro()
	_play_hit_squash()
	_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween)
	if _health <= 0:
		_die()

## Helper — DEAD is the only state in which the enemy should ignore inputs
## (damage, animation triggers, hover). All other states are "alive enough."
func _is_alive() -> bool:
	return _state != State.DEAD


# Per-class attack-param accessors. Each falls back to a DEFAULT_* constant
# when no EnemyClass is assigned, so unconfigured enemy scenes keep their
# pre-EnemyClass behaviour. Once every enemy has a class .tres, the
# fallbacks (and the DEFAULT_* consts) can be deleted.
func _attack_range() -> float:
	return enemy_class.attack_range if enemy_class != null else DEFAULT_ATTACK_RANGE

func _attack_cooldown() -> float:
	return enemy_class.attack_cooldown if enemy_class != null else DEFAULT_ATTACK_COOLDOWN

func _attack_windup() -> float:
	return enemy_class.attack_windup if enemy_class != null else DEFAULT_ATTACK_WINDUP

func _melee_cone_deg() -> float:
	return enemy_class.melee_cone_deg if enemy_class != null else DEFAULT_ATTACK_CONE_DEG

func _melee_knockback() -> float:
	return enemy_class.melee_knockback if enemy_class != null else DEFAULT_ATTACK_KNOCKBACK

func _is_ranged() -> bool:
	return enemy_class != null and enemy_class.attack_mode == EnemyClass.AttackMode.RANGED

func _ranged_kite_distance() -> float:
	return enemy_class.ranged_kite_distance if enemy_class != null else 8.0


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
	var buff_duration := enemy_class.support_interval * 1.1
	for ally: Node in SpatialGrid.query_radius(global_position, radius, &"enemies"):
		if ally == null or not is_instance_valid(ally):
			continue
		if not (ally is PrototypeEnemy):
			continue
		var ae: PrototypeEnemy = ally
		if not ae._is_alive():
			continue
		match role:
			EnemyClass.SupportRole.HEAL:
				ae.heal(int(round(float(ae.max_health) * magnitude)))
			EnemyClass.SupportRole.DAMAGE_BUFF:
				ae.apply_damage_buff(magnitude, buff_duration)


## Restore HP up to max_health. Called by allied support enemies' ticks;
## a no-op on dead enemies (corpses don't recover).
func heal(amount: int) -> void:
	if not _is_alive() or amount <= 0:
		return
	_health = mini(_health + amount, max_health)
	_update_health_bar()


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
## (configured per archetype) compounded with active support-aura buff.
func _outgoing_damage_mult() -> float:
	var class_mult := enemy_class.attack_damage_mult if enemy_class != null else 1.0
	return class_mult * (1.0 + _damage_buff_mult)


## Single point of state transitions. Currently a thin setter; entry/exit
## hooks (e.g. clearing horizontal velocity on enter-CASTING, releasing the
## hit-tween on enter-DEAD) live at the call sites for now. If hook count
## grows beyond a couple per state, switch to a dispatch table here.
func _change_state(new_state: State) -> void:
	if _state == new_state:
		return
	_state = new_state


func _play_hit_squash() -> void:
	if visual == null or not _is_alive():
		return
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	visual.scale = Vector3.ONE
	_hit_tween = create_tween()
	_hit_tween.tween_property(visual, "scale", HIT_SQUASH_SCALE, HIT_SQUASH_IN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(visual, "scale", Vector3.ONE, HIT_SQUASH_OUT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _update_health_bar() -> void:
	if health_bar == null:
		return
	var ratio := clampf(float(_health) / float(max_health), 0.0, 1.0)
	health_bar.visible = _is_alive() and ratio < 1.0
	health_bar.set_instance_shader_parameter(&"fill_ratio", ratio)

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)

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

	# Floor-snap is suppressed during JUMPING so the takeoff impulse set by
	# _start_jump (which runs from the agent's link_reached signal AFTER our
	# physics_process this frame) survives into the next frame's gravity
	# pass instead of being zeroed by is_on_floor().
	if _state == State.JUMPING or not is_on_floor():
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
	var moving := _want_dir.length_squared() > 0.01
	match _state:
		State.CASTING, State.KNOCKBACK:
			pass
		State.JUMPING:
			_play_anim(ANIM_JUMP)
		_:
			if _crouching:
				_play_anim(ANIM_CROUCH_RUN if moving else ANIM_CROUCH_IDLE)
			else:
				_play_anim(ANIM_RUN if moving else ANIM_IDLE)
			if moving:
				_face_direction(_want_dir)


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

	# Leash logic — runs even in IDLE (so an idle enemy at edge of leash
	# range can't be tricked into RETURNING). Player-close suppression keeps
	# the leash from tripping mid-fight; player-close re-engage prevents the
	# leashed enemy from getting a free walk past the player.
	var spawn_dist_sq := global_position.distance_squared_to(_spawn_position)
	var player_dist_sq := global_position.distance_squared_to(player.global_position)
	var player_close := player_dist_sq <= KEEP_CHASE_PLAYER_RANGE_SQ
	if _state == State.CHASING and spawn_dist_sq > MAX_CHASE_FROM_SPAWN_SQ and not player_close:
		_change_state(State.RETURNING)
	elif _state == State.RETURNING and player_close:
		_change_state(State.CHASING)

	if _state == State.RETURNING:
		_tick_return(spawn_dist_sq)
		return

	# IDLE & CHASING share the proximity-aggro check — an IDLE enemy that
	# the player walks toward should wake up the same way a previously-engaged
	# one would re-engage.
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	# Single LoS lookup serves both the aggro and attack-initiation checks
	# below. The damage-time check inside _cast_attack re-queries on purpose,
	# since it runs after the windup await.
	var has_los := LosCuller.has_los_to_player(self)
	if _state == State.IDLE and dist <= AGGRO_RANGE and has_los:
		aggro()

	if _state != State.CHASING or dist < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	# Ranged enemies kite to ~ranged_kite_distance: too close → backpedal,
	# in band → hold + fire when ready, too far → chase. Melee enemies skip
	# this branch and fall through to the close-and-swing path below.
	if _is_ranged():
		var kite := _ranged_kite_distance()
		if dist <= _attack_range() and _attack_cd <= 0.0 and has_los:
			_cast_attack(player, to_player / dist)
			return
		if dist < kite * 0.7:
			# Backpedal — direct vector, slower than chase. We don't pathfind
			# the retreat because navmesh wants to hug walls; a noisy bumpy
			# straight-line retreat reads as "skittish ranged enemy" and is
			# fine. Bumping into walls is the player's intended advantage.
			var away := -to_player / dist
			_want_dir = away
			var back_speed := CHASE_SPEED * 0.55 * (CROUCH_SPEED_MULT if _crouching else 1.0)
			velocity.x = away.x * back_speed
			velocity.z = away.z * back_speed
			return
		if dist <= kite:
			# Hold position in the firing band — wait for cooldown / LoS.
			_want_dir = Vector3.ZERO
			velocity.x = 0.0
			velocity.z = 0.0
			return
		# else: too far, fall through to navmesh chase below

	# Aggro'd melee chase the player. Won't start a swing through a wall —
	# the LoS check on attack initiation prevents through-wall hits.
	elif dist <= _attack_range() and _attack_cd <= 0.0 and has_los:
		_cast_attack(player, to_player / dist)
		return

	# Pathfind via NavigationAgent — routes around walls and pit edges
	# instead of charging straight at the player. Falls back to direct
	# vector chase when no nav agent (legacy scene), no map (navmesh
	# bake hasn't finished yet), or the agent is already on top of the
	# player.
	var dir := to_player / dist
	if _nav_agent != null and _nav_agent.get_navigation_map().is_valid():
		_nav_agent.target_position = player.global_position
		if not _nav_agent.is_navigation_finished():
			var next_pos := _nav_agent.get_next_path_position()
			var nav_dir := next_pos - global_position
			nav_dir.y = 0.0
			if nav_dir.length_squared() > 0.0001:
				dir = nav_dir.normalized()
	_want_dir = dir
	var chase_speed := CHASE_SPEED * (CROUCH_SPEED_MULT if _crouching else 1.0)
	velocity.x = dir.x * chase_speed
	velocity.z = dir.z * chase_speed


# Walks the enemy back to its spawn position. Transitions to IDLE on arrival.
func _tick_return(spawn_dist_sq: float) -> void:
	if spawn_dist_sq <= RETURN_THRESHOLD_SQ:
		_change_state(State.IDLE)
		velocity.x = 0.0
		velocity.z = 0.0
		return
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
	var return_speed := CHASE_SPEED * (CROUCH_SPEED_MULT if _crouching else 1.0)
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
	query.transform = Transform3D(Basis.IDENTITY,
		global_position + Vector3(0.0, STAND_HEIGHT * 0.5 + CAPSULE_BOTTOM_Y, 0.0))
	var blocked := not space.intersect_shape(query, 1).is_empty()
	if blocked != _crouching:
		_set_crouch(blocked)

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

func _cast_attack(player: Node3D, aim: Vector3) -> void:
	if _is_ranged():
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
	PrototypeAttackIndicator.spawn_cone(self, aim, range_now, cone_now, windup_now)
	await get_tree().create_timer(windup_now).timeout
	# Bail if anything preempted us during the windup (knockback, death,
	# leash). The state-machine transition is the source of truth — don't
	# reach back into _state here to "fix" it.
	if _state != State.CASTING:
		return
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
	# wall during the windup doesn't get hit through it.
	if not LosCuller.has_los_to_player(self):
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
	await get_tree().create_timer(windup_now).timeout
	if _state != State.CASTING:
		return
	_change_state(State.CHASING)
	if not is_instance_valid(player):
		return
	if not LosCuller.has_los_to_player(self):
		return
	# Re-aim at the player's CURRENT position — they may have strafed during
	# the windup. Aiming at the stale `aim` vector is the classic "bullet
	# follows where they used to be" tell.
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist < 0.001:
		return
	_spawn_enemy_projectile(to_p / dist)


func _spawn_enemy_projectile(aim: Vector3) -> void:
	var proj: PrototypeProjectile = EntityPool.acquire(enemy_class.projectile_scene)
	if proj == null:
		return
	proj.target_group = &"player"
	proj.direction = aim
	proj.speed = enemy_class.projectile_speed
	proj.max_range = enemy_class.projectile_max_range
	proj.knockback_strength = enemy_class.melee_knockback  # reuse the field — enemy projectiles inherit the same impact knockback
	proj.source_position = global_position
	var dmg := int(round(float(_attack_damage) * _outgoing_damage_mult()))
	proj.damage_min = dmg
	proj.damage_max = dmg
	proj.damage_mult = 1.0
	proj.accuracy = 1.0
	proj.crit_chance = 0.0
	get_parent().add_child(proj)
	proj.global_position = global_position + Vector3(0.0, 1.4, 0.0)
	proj.monitoring = true
	proj.reset()

func _die() -> void:
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
	PlayerState.gain_xp(PlayerState.xp_award_for_enemy(level))
	_drop_credits()
	_drop_item()
	var played := _play_anim(ANIM_DEATH, 1.0)
	if not played:
		if anim_player != null:
			anim_player.pause()
		if visual != null:
			var tween := create_tween()
			tween.tween_property(visual, "rotation:x", deg_to_rad(-75.0), DEATH_FALLBACK_DURATION)
	await get_tree().create_timer(DEATH_HOLD).timeout
	_become_corpse()

func _drop_credits() -> void:
	if randf() >= credit_drop_chance:
		return
	var parent := get_parent()
	if parent == null:
		return
	var pickup := EntityPool.acquire(CREDIT_PICKUP_SCENE)
	pickup.amount = randi_range(CREDIT_DROP_MIN, CREDIT_DROP_MAX)
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector3(0.0, 1.0, 0.0)
	pickup.reset()

func _drop_item() -> void:
	var drop_chance := ITEM_DROP_CHANCE_BASE + ITEM_DROP_CHANCE_PER_LEVEL * float(maxi(level - 1, 0))
	if randf() >= drop_chance:
		return
	var parent := get_parent()
	if parent == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ilvl := maxi(1, PlayerState.level + rng.randi_range(ITEM_DROP_ILVL_OFFSET_MIN, ITEM_DROP_ILVL_OFFSET_MAX))
	var item := ItemRoller.roll_random(ilvl, rng)
	var pickup := ITEM_PICKUP_SCENE.instantiate()
	pickup.configure(item)
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector3(0.0, 1.0, 0.0)

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
