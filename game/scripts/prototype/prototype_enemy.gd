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
const ATTACK_RANGE := 2.2
const ATTACK_COOLDOWN := 1.6

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
const ATTACK_WINDUP := 0.4
const ATTACK_CONE_DEG := 80.0
const ATTACK_KNOCKBACK := 5.0
const MAX_AGGRO_CASCADE := 2

const ANIM_IDLE: Array[StringName] = [&"Idle_Normal", &"Idle", &"IDLE_NORMAL"]
const ANIM_RUN: Array[StringName] = [&"Jog_Fwd", &"Walk_Normal", &"JOG_FWD", &"WALK_NORMAL"]
const ANIM_ATTACK: Array[StringName] = [&"Sword_Attack", &"Punch_Cross", &"SWORD_ATTACK", &"PUNCH_CROSS"]
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

@onready var visual: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/Character/AnimationPlayer
@onready var health_bar: MeshInstance3D = $HealthBar
@onready var collision: CollisionShape3D = $Collision
@onready var floor_ring: MeshInstance3D = $FloorRing

var _health: int
var _alive: bool = true
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0
var _attack_cd: float = 0.0
var _attack_damage: int = 10
var _casting: bool = false
var _want_dir: Vector3 = Vector3.ZERO
var _player_ref: Node3D
var _outlined_meshes: Array[MeshInstance3D] = []
var _hover_hooked: bool = false
var _hovered: bool = false
# Locked overrides hovered: red persists past mouse-exit until LMB release.
var _tooltip_locked: bool = false
var _hit_tween: Tween
var _floor_ring_mat: StandardMaterial3D
var _aggroed: bool = false

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
	_alive = true
	_knockback_remain = 0.0
	_attack_cd = 0.0
	_casting = false
	_aggroed = false
	_want_dir = Vector3.ZERO
	_player_ref = null
	set_physics_process(true)
	collision_layer = 1
	collision_mask = 1
	if collision != null:
		collision.disabled = false
	if floor_ring != null:
		floor_ring.visible = true
	_ensure_loop(ANIM_IDLE)
	_ensure_loop(ANIM_RUN)
	_play_anim(ANIM_IDLE)
	if health_bar != null:
		health_bar.visible = false

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
	if not _alive:
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
	if not _alive:
		return
	if DebugState.config != null and DebugState.config.one_shot_enemies:
		amount = max(amount, max_health)
	_health -= amount
	_update_health_bar()
	var head := global_position + Vector3(0.0, 1.8, 0.0)
	DamageNumber.spawn(get_parent(), head, amount, multistrike, is_crit)
	if knockback_strength > 0.0:
		var dir := global_position - knockback_from
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			_knockback_vel = dir.normalized() * knockback_strength
			_knockback_remain = KNOCKBACK_DURATION
	if not _aggroed:
		aggro()
	_play_hit_squash()
	if _health <= 0:
		_die()

func _play_hit_squash() -> void:
	if visual == null or not _alive:
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
	health_bar.visible = _alive and ratio < 1.0
	health_bar.set_instance_shader_parameter(&"fill_ratio", ratio)

func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	if _knockback_remain > 0.0:
		# Quadratic ease-out: full velocity at the moment of impact, near-zero
		# by the end of the window — replaces the previous hard-stop bounce.
		var t: float = _knockback_remain / KNOCKBACK_DURATION
		var falloff: float = t * t
		velocity.x = _knockback_vel.x * falloff
		velocity.z = _knockback_vel.z * falloff
		_knockback_remain -= delta
		_want_dir = Vector3.ZERO
	elif _casting:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		_chase_tick()
	move_and_slide()

	if _alive and not _casting and _knockback_remain <= 0.0:
		if _want_dir.length_squared() > 0.01:
			_play_anim(ANIM_RUN)
			_face_direction(_want_dir)
		else:
			_play_anim(ANIM_IDLE)

## Force this enemy into aggro state and alert nearby enemies.
## depth caps the cascade so aggro doesn't chain across the entire level.
func aggro(depth: int = 0) -> void:
	if _aggroed:
		return
	_aggroed = true
	if depth >= MAX_AGGRO_CASCADE:
		return
	for enode: Node3D in SpatialGrid.query_radius(global_position, GROUP_AGGRO_RANGE, &"enemies"):
		if enode == self:
			continue
		if enode.has_method(&"aggro"):
			enode.aggro(depth + 1)

func _chase_tick() -> void:
	_want_dir = Vector3.ZERO
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group(&"player") as Node3D
	var player := _player_ref
	if player == null:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	# Normal proximity aggro.
	if not _aggroed and dist <= AGGRO_RANGE:
		aggro()
	if not _aggroed or dist < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if dist <= ATTACK_RANGE and _attack_cd <= 0.0:
		_cast_attack(player, to_player / dist)
		return
	var dir := to_player / dist
	_want_dir = dir
	velocity.x = dir.x * CHASE_SPEED
	velocity.z = dir.z * CHASE_SPEED

func _cast_attack(player: Node3D, aim: Vector3) -> void:
	_casting = true
	_attack_cd = ATTACK_COOLDOWN
	velocity.x = 0.0
	velocity.z = 0.0
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.2)
	PrototypeAttackIndicator.spawn_cone(self, aim, ATTACK_RANGE, ATTACK_CONE_DEG, ATTACK_WINDUP)
	await get_tree().create_timer(ATTACK_WINDUP).timeout
	_casting = false
	if not _alive or not is_instance_valid(player):
		return
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist > ATTACK_RANGE or dist < 0.001:
		return
	var half_cos := cos(deg_to_rad(ATTACK_CONE_DEG * 0.5))
	if aim.dot(to_p / dist) < half_cos:
		return
	if player.has_method(&"take_damage"):
		player.take_damage(_attack_damage, global_position, ATTACK_KNOCKBACK)

func _die() -> void:
	_alive = false
	# Drop out of the spatial grid immediately so AoE/cone queries during the
	# DEATH_HOLD window stop "hitting" the corpse-in-progress. The actual
	# group/collision teardown still waits for _become_corpse so the death
	# animation and drops can finish.
	SpatialGrid.unregister(self)
	collision_layer = 0
	collision_mask = 0
	if collision != null:
		collision.disabled = true
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
