class_name PlayerCombat
extends Node

## Handles skill resolution, damage rolling, cooldown tracking, and projectile
## spawning for the player. Extracted from PrototypePlayer to keep that file
## focused on movement, input, and state management.

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_projectile.tscn")

const PROTO_BASE_CRIT_CHANCE: float = 0.15
const PROTO_BASE_CRIT_MULT: float = 1.5

# Point-blank spread penalty for ranged attacks. When a hitscan fires
# within MELEE_RANGE_THRESHOLD of the nearest target, effective accuracy
# is multiplied by MELEE_RANGE_ACCURACY_MULT before computing spread —
# wider cone at point blank pushes the player toward sprint-disengage.
# Projectiles apply the penalty at spawn time. Melee skills (cone / AoE)
# are unaffected.
const MELEE_RANGE_THRESHOLD: float = 2.5
const MELEE_RANGE_ACCURACY_MULT: float = 0.75

# Maximum angular spread (radians) at 0% accuracy. At 100% accuracy the
# shot is perfectly straight. Linear interpolation:
#   spread = (1 - accuracy) * INACCURACY_SPREAD_MAX
# 0.25 rad ≈ 14° — at range 20, a 0% accuracy shot deviates up to ~5m.
const INACCURACY_SPREAD_MAX: float = 0.25

# Hitscan cone half-angle for SpatialGrid.query_cone hit detection. The
# cone tests against enemy center-points, so it needs to be wide enough
# to catch enemies whose capsule edge overlaps the beam visually. 4° at
# range 10 ≈ 0.7m, matching the 0.75m enemy collision radius.
const HITSCAN_CONE_HALF_DEG: float = 4.0

# Count Exile constants. EXILE_CURSE_DURATION is the medium-long window
# the curse persists after the FIRST hit. Subsequent hits while the curse
# is active do NOT refresh the timer — the window is fixed from the moment
# of application, so the player has to commit damage inside it. When the
# timer expires on a still-alive target, fire_exile_shot lands a fixed
# massive shot that isn't tied to any equipped weapon (works barehanded /
# mid-reload). Damage scales with gear bonuses.
const EXILE_CURSE_DURATION: float = 4.0
const EXILE_AUTO_SHOT_BASE_DAMAGE: int = 60
const EXILE_AUTO_SHOT_KNOCKBACK: float = 4.0

# Overclock — Survivalist talent. When the roll succeeds, the attack deals
# +25% damage but loses 25% range. Visuals scale up 25% to sell the hit.
const OVERCLOCK_DAMAGE_MULT: float = 1.25
const OVERCLOCK_RANGE_MULT: float = 0.75
const OVERCLOCK_VISUAL_SCALE: float = 1.25

# Mindlink — Polymath talent. When active, each hit echoes full damage to
# the nearest other enemy within this radius of the primary target.
const MINDLINK_RADIUS: float = 6.0

var _host: PrototypePlayer
var _cooldowns: Dictionary = {}
# Resolved aim direction from the most recent hitscan / projectile fire.
# Used by Double Tap to copy the exact same trajectory for the follow-up.
var _last_resolved_aim: Vector3 = Vector3.FORWARD
# Per-attack overclock state — set at the top of resolve_skill_hit, read
# by damage rolling and visual spawn functions during that same call.
var _overclock_active: bool = false
# Guard flag so Mindlink echoes don't trigger further echoes.
var _mindlink_echoing: bool = false
# Per-equipment-slot cooldowns for the multi-weapon LMB path. Two identical
# weapons in different slots (Forged Amalgamation) have independent timers
# because the key is the slot StringName, not the Skill resource. Non-LMB
# skills still use _cooldowns (keyed by Skill).
var _slot_cooldowns: Dictionary = {}

func setup(host: PrototypePlayer) -> void:
	_host = host

func tick_cooldowns(delta: float) -> void:
	for skill in _cooldowns.keys():
		_cooldowns[skill] = maxf(0.0, _cooldowns[skill] - delta)
	for slot in _slot_cooldowns.keys():
		_slot_cooldowns[slot] = maxf(0.0, _slot_cooldowns[slot] - delta)

func is_on_cooldown(skill: Skill) -> bool:
	return _cooldowns.get(skill, 0.0) > 0.0

func start_cooldown(skill: Skill, atk_speed: float) -> void:
	var eff_atk_spd := atk_speed * (1.0 + _host._gear_attack_speed_bonus)
	var cdr := _host._gear_cooldown_reduction
	_cooldowns[skill] = skill.cooldown * (1.0 - cdr) / maxf(eff_atk_spd, 0.1)

func get_cooldown_ratio(skill: Skill) -> float:
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	var remaining: float = _cooldowns.get(skill, 0.0)
	return clampf(remaining / skill.cooldown, 0.0, 1.0)


func get_cooldown_remain(skill: Skill) -> float:
	if skill == null:
		return 0.0
	return maxf(_cooldowns.get(skill, 0.0), 0.0)

func is_slot_on_cooldown(slot: StringName) -> bool:
	return _slot_cooldowns.get(slot, 0.0) > 0.0

func start_slot_cooldown(slot: StringName, skill: Skill, atk_speed: float) -> void:
	if skill == null or skill.cooldown <= 0.0:
		return
	var eff_atk_spd := atk_speed * (1.0 + _host._gear_attack_speed_bonus)
	var cdr := _host._gear_cooldown_reduction
	_slot_cooldowns[slot] = skill.cooldown * (1.0 - cdr) / maxf(eff_atk_spd, 0.1)

func clear_cooldowns() -> void:
	_cooldowns.clear()
	_slot_cooldowns.clear()

# ---------------------------------------------------------------------------
# Skill resolution
# ---------------------------------------------------------------------------

func effective_range(skill: Skill, weapon: Item) -> float:
	if weapon != null and weapon.weapon_range > 0.0:
		return weapon.weapon_range
	return skill.skill_range

func resolve_skill_source(skill: Skill) -> Item:
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	if weapon != null and (weapon.fire_skill == skill or weapon.alt_fire_skill == skill):
		return weapon
	var offhand: Item = InventoryState.get_equipped(&"offhand")
	if offhand != null and (offhand.fire_skill == skill or offhand.alt_fire_skill == skill):
		return offhand
	return null

## Stagger delay between multistrike repeat attacks so each hit reads as a
## distinct visual event (separate cone flash, projectile, etc.).
const MULTISTRIKE_STAGGER: float = 0.08

func resolve_skill_hit(skill: Skill, aim: Vector3, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	var eff_range := effective_range(skill, weapon)
	# Overclock roll — Survivalist talent. On proc: +25% damage, -25% range,
	# visually fatter/brighter shot. The flag is read by _roll_skill_damage
	# and visual spawn helpers during this same call stack.
	var oc_chance := Effects.get_aggregate(&"overclock_chance")
	_overclock_active = oc_chance > 0.0 and randf() < oc_chance
	if _overclock_active:
		eff_range *= OVERCLOCK_RANGE_MULT
	var hits := PerkState.roll_multistrike()
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			CombatVisuals.spawn_hit_cone(_host, aim, eff_range, skill.cone_deg)
			_resolve_cone(skill, aim, eff_range, weapon)
			for extra in hits - 1:
				var delay := MULTISTRIKE_STAGGER * float(extra + 1)
				_host.get_tree().create_timer(delay).timeout.connect(func() -> void:
					if not _host._alive:
						return
					CombatVisuals.spawn_hit_cone(_host, aim, eff_range, skill.cone_deg)
					_resolve_cone(skill, aim, eff_range, weapon)
				, CONNECT_ONE_SHOT)
		Skill.TargetingMode.AOE_RADIAL:
			CombatVisuals.spawn_hit_radial(_host, eff_range)
			_resolve_aoe(skill, eff_range, weapon)
			for extra in hits - 1:
				var delay := MULTISTRIKE_STAGGER * float(extra + 1)
				_host.get_tree().create_timer(delay).timeout.connect(func() -> void:
					if not _host._alive:
						return
					CombatVisuals.spawn_hit_radial(_host, eff_range)
					_resolve_aoe(skill, eff_range, weapon)
				, CONNECT_ONE_SHOT)
		Skill.TargetingMode.PROJECTILE:
			for i in hits:
				_spawn_projectile(skill, aim, eff_range, weapon, source_offset)
			_try_double_tap(skill, aim, eff_range, weapon, source_offset)
		Skill.TargetingMode.HITSCAN:
			for i in hits:
				_resolve_hitscan(skill, aim, eff_range, weapon, source_offset)
			_try_double_tap(skill, aim, eff_range, weapon, source_offset)
	_overclock_active = false

# ---------------------------------------------------------------------------
# Double Tap — Count talent: chance to fire a consecutive follow-up shot
# with the same aim as the primary. Only projectile / hitscan; melee
# patterns (cone, AoE) don't double-tap.
# ---------------------------------------------------------------------------

## Delay before the follow-up shot fires — short enough to read as a rapid
## double-shot, long enough that both beams / bolts are visually distinct.
const DOUBLE_TAP_DELAY: float = 0.10

func _try_double_tap(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3) -> void:
	var chance := Effects.get_aggregate(&"double_tap_chance")
	if chance <= 0.0 or randf() >= chance:
		return
	var tap_aim := _last_resolved_aim
	_host.get_tree().create_timer(DOUBLE_TAP_DELAY).timeout.connect(func() -> void:
		if not _host._alive:
			return
		match skill.targeting_mode:
			Skill.TargetingMode.PROJECTILE:
				_spawn_projectile_exact(skill, tap_aim, eff_range, weapon, source_offset)
			Skill.TargetingMode.HITSCAN:
				_resolve_hitscan_exact(skill, tap_aim, eff_range, weapon, source_offset)
	, CONNECT_ONE_SHOT)

# ---------------------------------------------------------------------------
# Hit patterns
# ---------------------------------------------------------------------------

## Knockback applied per hit. Normal weapon skills carry skill.knockback = 0;
## the &"knockback_bonus" affix on the firing weapon adds raw push units on
## top. Special skills (grenades, shield bash) keep their inherent knockback
## via skill.knockback. No weapon, no skill knockback → no push.
func _knockback_for(skill: Skill, weapon: Item) -> float:
	var bonus: float = 0.0
	if weapon != null:
		bonus = float(weapon.get_effective_modifier(&"knockback_bonus"))
	return skill.knockback + bonus

## Convenience wrapper — delegates to the static PrototypeEnemy.deal_damage
## so PlayerCombat call sites stay short. See PrototypeEnemy.deal_damage for
## the SP / MP routing logic.
func _deal_damage(target: Node3D, amount: int, knockback_from: Vector3, knockback_strength: float, multistrike: int, is_crit: bool) -> void:
	PrototypeEnemy.deal_damage(target, amount, knockback_from, knockback_strength, multistrike, is_crit)


func _resolve_cone(skill: Skill, aim: Vector3, eff_range: float, weapon: Item) -> void:
	var half_cos := cos(deg_to_rad(skill.cone_deg * 0.5))
	var kb := _knockback_for(skill, weapon)
	for enode: Node3D in SpatialGrid.query_cone(_host.global_position, aim, eff_range, half_cos, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		if is_player_friendly(enode):
			continue
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		_deal_damage(enode, dmg, _host.global_position, kb, 1, is_crit)
		_apply_exile_curse_if_active(enode)
		_apply_mindlink(enode, dmg, is_crit)
		_try_spawn_isr_drone(enode)

func _resolve_aoe(skill: Skill, eff_range: float, weapon: Item) -> void:
	var kb := _knockback_for(skill, weapon)
	for enode: Node3D in SpatialGrid.query_radius(_host.global_position, eff_range, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		if is_player_friendly(enode):
			continue
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		_deal_damage(enode, dmg, _host.global_position, kb, 1, is_crit)
		_apply_exile_curse_if_active(enode)
		_apply_mindlink(enode, dmg, is_crit)
		_try_spawn_isr_drone(enode)


# Cheap duck-typed check — charmed enemies expose is_player_friendly()
# returning true. Anything that doesn't have the method is treated as
# a normal target. Centralised so the player-friendly skip rule lives
# in one place across all damage paths.
func is_player_friendly(target: Node) -> bool:
	return target.has_method(&"is_player_friendly") and target.is_player_friendly()

## Random spread (radians) applied to extra-arm projectiles so they
## converge toward the main-hand target without looking perfectly identical.
const EXTRA_ARM_SPREAD_RAD := 0.04

func _spawn_projectile(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	var proj: PrototypeProjectile = EntityPool.acquire(PROJECTILE_SCENE)
	if proj == null:
		return
	var aim_norm := aim.normalized()
	# Extra arms spawn offset from the player. To hit the same target as
	# the main hand, re-aim from the offset spawn position toward the
	# main-hand's target point (player + aim * range). Adds slight random
	# spread so the volley looks organic, not robotic.
	var spawn_pos := _host.global_position + Vector3(0.0, 1.0, 0.0) + source_offset
	if source_offset != Vector3.ZERO:
		var target_point := _host.global_position + Vector3(0.0, 1.0, 0.0) + aim_norm * eff_range
		aim_norm = (target_point - spawn_pos).normalized()
		var spread := randf_range(-EXTRA_ARM_SPREAD_RAD, EXTRA_ARM_SPREAD_RAD)
		aim_norm = aim_norm.rotated(Vector3.UP, spread)
	# Accuracy-based angular spread — inaccurate weapons scatter shots
	# around the aim direction. Stray shots can still hit nearby enemies.
	aim_norm = _apply_aim_spread(aim_norm, weapon)
	_last_resolved_aim = aim_norm
	proj.direction = aim_norm
	proj.speed = skill.projectile_speed
	proj.max_range = eff_range
	proj.knockback_strength = _knockback_for(skill, weapon)
	proj.source_position = _host.global_position
	if weapon != null and weapon.damage_max > 0:
		proj.damage_min = weapon.effective_damage_min() + _host._gear_base_damage_bonus
		proj.damage_max = weapon.effective_damage_max() + _host._gear_base_damage_bonus
		proj.crit_chance = weapon.effective_crit_chance() + _host._gear_crit_chance_bonus
	else:
		proj.damage_min = skill.damage + _host._gear_base_damage_bonus
		proj.damage_max = skill.damage + _host._gear_base_damage_bonus
	proj.damage_mult = skill.damage_multiplier
	if _overclock_active:
		proj.damage_mult *= OVERCLOCK_DAMAGE_MULT
	proj.blast_radius = skill.blast_radius
	var vis := skill.damage_multiplier if skill.damage_multiplier > 1.0 else 1.0
	if _overclock_active:
		vis *= OVERCLOCK_VISUAL_SCALE
	proj.visual_scale = vis
	# Bullet weapons (LMG/SMG/sniper/RPG) flag the projectile so it
	# renders as a tracer streak instead of an energy bolt.
	proj.is_bullet = weapon != null and weapon.is_bullet_weapon()
	_host.get_parent().add_child(proj)
	proj.global_position = spawn_pos
	proj.monitoring = true
	proj.reset()

func _resolve_hitscan(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	var origin := _host.global_position + Vector3(0.0, 1.0, 0.0) + source_offset
	var aim_norm := aim.normalized()
	# Re-aim from the offset origin toward the main-hand target point so
	# extra arms converge on the same spot instead of firing parallel.
	if source_offset != Vector3.ZERO:
		var target_point := _host.global_position + Vector3(0.0, 1.0, 0.0) + aim_norm * eff_range
		aim_norm = (target_point - origin).normalized()
		var spread := randf_range(-EXTRA_ARM_SPREAD_RAD, EXTRA_ARM_SPREAD_RAD)
		aim_norm = aim_norm.rotated(Vector3.UP, spread)
	# Point-blank penalty widens spread when target is close. The Count
	# "Point Blank" talent waives this.
	var acc_mult := 1.0
	var ignore_penalty := Effects.get_aggregate(&"ignore_point_blank_penalty") > 0.0
	if not ignore_penalty:
		for enode: Node3D in SpatialGrid.query_radius(origin, MELEE_RANGE_THRESHOLD, &"enemies"):
			if enode.has_method(&"take_damage") and not is_player_friendly(enode):
				acc_mult = MELEE_RANGE_ACCURACY_MULT
				break
	aim_norm = _apply_aim_spread(aim_norm, weapon, acc_mult)
	_last_resolved_aim = aim_norm
	var wall_dist := eff_range
	var hit_target: Node3D = null
	var space := _host.get_world_3d().direct_space_state
	var ray_end := origin + aim_norm * eff_range
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, 1)
	var result := space.intersect_ray(query)
	if not result.is_empty():
		wall_dist = origin.distance_to(result["position"])
	var half_cos := cos(deg_to_rad(HITSCAN_CONE_HALF_DEG))
	var closest_dist := INF
	for enode: Node3D in SpatialGrid.query_cone(origin, aim_norm, wall_dist, half_cos, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		if is_player_friendly(enode):
			continue
		var dist := origin.distance_squared_to(enode.global_position)
		if dist < closest_dist:
			closest_dist = dist
			hit_target = enode
	var beam_end := wall_dist
	if hit_target != null:
		beam_end = minf(beam_end, origin.distance_to(hit_target.global_position))
	CombatVisuals.spawn_beam(_host, aim_norm, beam_end, source_offset)
	if hit_target != null:
		CombatVisuals.spawn_impact_burst(_host, hit_target.global_position + Vector3(0.0, 0.9, 0.0))
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		_deal_damage(hit_target, dmg, _host.global_position, _knockback_for(skill, weapon), 1, is_crit)
		_apply_exile_curse_if_active(hit_target)
		_apply_mindlink(hit_target, dmg, is_crit)
		_try_spawn_isr_drone(hit_target)

# ---------------------------------------------------------------------------
# Double Tap follow-up variants — fire along a pre-resolved aim direction
# with no additional spread. Single hit, no multistrike.
# ---------------------------------------------------------------------------

func _spawn_projectile_exact(skill: Skill, aim_norm: Vector3, eff_range: float, weapon: Item, source_offset: Vector3) -> void:
	var proj: PrototypeProjectile = EntityPool.acquire(PROJECTILE_SCENE)
	if proj == null:
		return
	var spawn_pos := _host.global_position + Vector3(0.0, 1.0, 0.0) + source_offset
	proj.direction = aim_norm
	proj.speed = skill.projectile_speed
	proj.max_range = eff_range
	proj.knockback_strength = _knockback_for(skill, weapon)
	proj.source_position = _host.global_position
	if weapon != null and weapon.damage_max > 0:
		proj.damage_min = weapon.effective_damage_min() + _host._gear_base_damage_bonus
		proj.damage_max = weapon.effective_damage_max() + _host._gear_base_damage_bonus
		proj.crit_chance = weapon.effective_crit_chance() + _host._gear_crit_chance_bonus
	else:
		proj.damage_min = skill.damage + _host._gear_base_damage_bonus
		proj.damage_max = skill.damage + _host._gear_base_damage_bonus
	proj.damage_mult = skill.damage_multiplier
	proj.blast_radius = skill.blast_radius
	proj.visual_scale = skill.damage_multiplier if skill.damage_multiplier > 1.0 else 1.0
	proj.is_bullet = weapon != null and weapon.is_bullet_weapon()
	_host.get_parent().add_child(proj)
	proj.global_position = spawn_pos
	proj.monitoring = true
	proj.reset()


func _resolve_hitscan_exact(skill: Skill, aim_norm: Vector3, eff_range: float, weapon: Item, source_offset: Vector3) -> void:
	var origin := _host.global_position + Vector3(0.0, 1.0, 0.0) + source_offset
	var wall_dist := eff_range
	var hit_target: Node3D = null
	var space := _host.get_world_3d().direct_space_state
	var ray_end := origin + aim_norm * eff_range
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, 1)
	var result := space.intersect_ray(query)
	if not result.is_empty():
		wall_dist = origin.distance_to(result["position"])
	var half_cos := cos(deg_to_rad(HITSCAN_CONE_HALF_DEG))
	var closest_dist := INF
	for enode: Node3D in SpatialGrid.query_cone(origin, aim_norm, wall_dist, half_cos, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		if is_player_friendly(enode):
			continue
		var dist := origin.distance_squared_to(enode.global_position)
		if dist < closest_dist:
			closest_dist = dist
			hit_target = enode
	var beam_end := wall_dist
	if hit_target != null:
		beam_end = minf(beam_end, origin.distance_to(hit_target.global_position))
	CombatVisuals.spawn_beam(_host, aim_norm, beam_end, source_offset)
	if hit_target != null:
		CombatVisuals.spawn_impact_burst(_host, hit_target.global_position + Vector3(0.0, 0.9, 0.0))
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		_deal_damage(hit_target, dmg, _host.global_position, _knockback_for(skill, weapon), 1, is_crit)
		_apply_exile_curse_if_active(hit_target)
		_apply_mindlink(hit_target, dmg, is_crit)
		_try_spawn_isr_drone(hit_target)


# ---------------------------------------------------------------------------
# Damage rolling
# ---------------------------------------------------------------------------

func _roll_crit(weapon: Item = null) -> bool:
	var base_crit := weapon.effective_crit_chance() if weapon != null and weapon.crit_chance > 0.0 else PROTO_BASE_CRIT_CHANCE
	var chance := base_crit + Effects.get_aggregate(&"crit_chance_pct") + _host._gear_crit_chance_bonus
	# AIM_HOLD (Sniper Focus) flat-adds to crit chance while RMB is held.
	chance += _host.aim_hold_crit_bonus()
	return randf() < chance

## Vertical spread is half horizontal — enough to see shots angle into
## the air or hit the floor, but left/right remains the dominant miss axis.
const VERTICAL_SPREAD_RATIO: float = 0.5
## Minimum horizontal spread on a miss (radians). Guarantees the shot
## visibly goes wide rather than grazing the target.
const MISS_MIN_SPREAD: float = 0.06

## Accuracy is a hit/miss roll: 75% accuracy = 75% of shots fly true,
## 25% get visible spread applied. accuracy_mult handles situational
## modifiers (e.g. point-blank penalty). Misses spread in both yaw and
## pitch so stray shots fly high / low as well as left / right.
func _apply_aim_spread(aim: Vector3, weapon: Item, accuracy_mult: float = 1.0) -> Vector3:
	var acc := weapon.effective_accuracy() if weapon != null else 1.0
	acc += _host._gear_hit_chance_bonus
	# AIM_HOLD (Tripod / Focus) layers a flat accuracy bonus while RMB is
	# held — the buff is intentional flat-add (not a multiplier) so the
	# Tripod's +0.3 reads as "30 more points of accuracy" regardless of
	# the rolled accuracy on the weapon.
	acc += _host.aim_hold_accuracy_bonus()
	acc *= accuracy_mult
	acc = clampf(acc, 0.0, 1.0)
	# Hit roll — accurate shots fly straight at the target.
	if randf() < acc:
		return aim
	# Miss — apply spread. Range is [MISS_MIN_SPREAD, INACCURACY_SPREAD_MAX]
	# so misses always visibly go wide, never graze.
	var yaw := atan2(aim.x, aim.z)
	var pitch := asin(clampf(aim.y, -1.0, 1.0))
	var h_spread := randf_range(MISS_MIN_SPREAD, INACCURACY_SPREAD_MAX)
	if randf() < 0.5:
		h_spread = -h_spread
	var v_max := INACCURACY_SPREAD_MAX * VERTICAL_SPREAD_RATIO
	var v_spread := randf_range(-v_max, v_max)
	yaw += h_spread
	pitch += v_spread
	pitch = clampf(pitch, -PI * 0.5, PI * 0.5)
	var cos_p := cos(pitch)
	return Vector3(sin(yaw) * cos_p, sin(pitch), cos(yaw) * cos_p)

func _roll_skill_damage(skill: Skill, weapon: Item) -> int:
	var base: int
	if weapon != null and weapon.damage_max > 0:
		base = randi_range(weapon.effective_damage_min(), weapon.effective_damage_max())
	else:
		base = skill.damage
	base += _host._gear_base_damage_bonus
	var dmg_mult := skill.damage_multiplier
	if _overclock_active:
		dmg_mult *= OVERCLOCK_DAMAGE_MULT
	return int(round(float(base) * dmg_mult))

func _crit_damage(base: int, is_crit: bool) -> int:
	if not is_crit:
		return base
	var mult := PROTO_BASE_CRIT_MULT + Effects.get_aggregate(&"crit_damage_pct")
	return int(round(float(base) * mult))

# ---------------------------------------------------------------------------
# Count Exile — apply curse on hit + auto-fire massive shot on expire
# ---------------------------------------------------------------------------

func _apply_exile_curse_if_active(enemy: Node) -> void:
	var pct: float = Effects.get_aggregate(&"exile_curse_damage_pct")
	if pct <= 0.0:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method(&"apply_curse"):
		enemy.apply_curse(pct, EXILE_CURSE_DURATION)


func fire_exile_shot(target: Node3D) -> void:
	# Curse can outlive the player — _tick_curse on the enemy keeps
	# counting down regardless of player state. If the player is already
	# dead when the timer expires, swallow the auto-shot. Otherwise a
	# corpse would still finish the kill, which reads as the player
	# winning a fight they actually lost.
	if _host == null or not _host.is_alive():
		return
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method(&"take_damage"):
		return
	if is_player_friendly(target):
		return
	var origin := _host.global_position + Vector3(0.0, 1.0, 0.0)
	var aim := target.global_position + Vector3(0.0, 1.0, 0.0) - origin
	var dist := aim.length()
	if dist < 0.001:
		return
	var aim_norm := aim / dist
	CombatVisuals.spawn_beam(_host, aim_norm, dist)
	CombatVisuals.spawn_impact_burst(_host, target.global_position + Vector3(0.0, 0.9, 0.0))
	var mult := 1.0
	var dmg := int(round(float(EXILE_AUTO_SHOT_BASE_DAMAGE) * mult))
	_deal_damage(target, dmg, _host.global_position, EXILE_AUTO_SHOT_KNOCKBACK, 1, false)


# ---------------------------------------------------------------------------
# Polymath Mindlink — echo damage to a nearby enemy
# ---------------------------------------------------------------------------

func _apply_mindlink(primary: Node3D, dmg: int, is_crit: bool) -> void:
	if _mindlink_echoing:
		return
	if Effects.get_aggregate(&"mindlink_active") <= 0.0:
		return
	if primary == null or not is_instance_valid(primary):
		return
	var best: Node3D = null
	var best_d2 := MINDLINK_RADIUS * MINDLINK_RADIUS
	for n: Node3D in SpatialGrid.query_radius(primary.global_position, MINDLINK_RADIUS, &"enemies"):
		if n == primary:
			continue
		if not n.has_method(&"take_damage"):
			continue
		if is_player_friendly(n):
			continue
		var d2 := primary.global_position.distance_squared_to(n.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	if best == null:
		return
	# Visual: beam from primary to echo target so the link reads clearly.
	var link_dir := best.global_position - primary.global_position
	var link_dist := link_dir.length()
	if link_dist > 0.001:
		CombatVisuals.spawn_beam(primary, link_dir.normalized(), link_dist)
	CombatVisuals.spawn_impact_burst(_host, best.global_position + Vector3(0.0, 0.9, 0.0))
	_mindlink_echoing = true
	_deal_damage(best, dmg, _host.global_position, 0.0, 1, is_crit)
	_mindlink_echoing = false


# ---------------------------------------------------------------------------
# Automaton ISR Drone — chance to spawn a surveillance drone on hit
# ---------------------------------------------------------------------------

func _try_spawn_isr_drone(enemy: Node3D) -> void:
	var chance := Effects.get_aggregate(&"isr_drone_chance")
	if chance <= 0.0 or randf() >= chance:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if is_player_friendly(enemy):
		return
	ISRDrone.spawn_on(enemy)
