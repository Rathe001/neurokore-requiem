class_name EnemyCombat
extends Node
## Extracted from PrototypeEnemy — attack execution, skill resolution,
## damage multipliers, support aura emit, and aim spread.

var _host: PrototypeEnemy

# Skill cooldown state — ticked per frame.
var _skill_cooldowns: Dictionary = {}

# Self-buff state (enrage skill).
var _self_buff_remain: float = 0.0
var _self_buff_damage_mult: float = 1.0
var _self_buff_speed_mult: float = 1.0

func setup(host: PrototypeEnemy) -> void:
	_host = host

func tick(delta: float) -> void:
	for skill in _skill_cooldowns.keys():
		_skill_cooldowns[skill] = maxf(0.0, _skill_cooldowns[skill] - delta)
	if _self_buff_remain > 0.0:
		_self_buff_remain -= delta
		if _self_buff_remain <= 0.0:
			_self_buff_remain = 0.0
			_self_buff_damage_mult = 1.0
			_self_buff_speed_mult = 1.0
	# Damage buff decay (applied by support allies).
	var afl := _host._afflictions
	if afl._damage_buff_remain > 0.0:
		afl._damage_buff_remain -= delta
		if afl._damage_buff_remain <= 0.0:
			afl._damage_buff_remain = 0.0
			afl._damage_buff_mult = 0.0

func reset(skills: Array[EnemySkill]) -> void:
	_skill_cooldowns.clear()
	_self_buff_remain = 0.0
	_self_buff_damage_mult = 1.0
	_self_buff_speed_mult = 1.0
	for skill in skills:
		if skill != null:
			_skill_cooldowns[skill] = 0.0


# ── Attack config getters ──────────────────────────────────────────────────
#
# Precedence: class fields win, basic_attack skill is the fallback. Several
# variant classes (e.g. ranged_laser vs ranged_laser_pistol) intentionally
# share a basic_attack .tres and override cadence per-class — when the skill
# wins, those variants play identically. Each class file already declares
# its full attack profile, so taking the class as authoritative respects
# the design while keeping the skill as a sane default for any class that
# omits a field.

func attack_range() -> float:
	var ec := _host.enemy_class
	if ec != null:
		return ec.attack_range
	return PrototypeEnemy.DEFAULT_ATTACK_RANGE

func attack_cooldown() -> float:
	var ec := _host.enemy_class
	var base: float
	if ec != null:
		base = ec.attack_cooldown
	else:
		base = PrototypeEnemy.DEFAULT_ATTACK_COOLDOWN
	return base * affix_attack_cooldown_mult()

func attack_windup() -> float:
	var ec := _host.enemy_class
	if ec != null:
		return ec.attack_windup
	return PrototypeEnemy.DEFAULT_ATTACK_WINDUP

func melee_cone_deg() -> float:
	var ec := _host.enemy_class
	if ec != null:
		return ec.melee_cone_deg
	return PrototypeEnemy.DEFAULT_ATTACK_CONE_DEG

func melee_knockback() -> float:
	var ec := _host.enemy_class
	if ec != null:
		return ec.melee_knockback
	return PrototypeEnemy.DEFAULT_ATTACK_KNOCKBACK

func is_ranged() -> bool:
	return _host.enemy_class != null and _host.enemy_class.attack_mode == EnemyClass.AttackMode.RANGED

func ranged_kite_distance() -> float:
	return _host.enemy_class.ranged_kite_distance if _host.enemy_class != null else 8.0

func affix_attack_cooldown_mult() -> float:
	var m := 1.0
	for affix in _host.affixes:
		if affix != null:
			m *= affix.attack_cooldown_mult
	return m

func affix_move_speed_mult() -> float:
	var m := 1.0
	for affix in _host.affixes:
		if affix != null:
			m *= affix.move_speed_mult
	return m


# ── Damage multiplier ──────────────────────────────────────────────────────

func outgoing_damage_mult() -> float:
	var class_mult := _host.enemy_class.attack_damage_mult if _host.enemy_class != null else 1.0
	return class_mult * (1.0 + _host._afflictions._damage_buff_mult) * _self_buff_damage_mult * (1.0 - _host._afflictions._weaken_mult)


# ── Support aura ───────────────────────────────────────────────────────────

func emit_support() -> void:
	var ec := _host.enemy_class
	if ec == null or ec.support_role == EnemyClass.SupportRole.NONE:
		return
	var radius := ec.support_radius
	var role := ec.support_role
	var magnitude := ec.support_magnitude
	var magnitude_max := ec.support_magnitude_max
	var buff_duration := ec.support_interval * 1.1
	for ally: Node in SpatialGrid.query_radius(_host.global_position, radius, &"enemies"):
		if ally == null or not is_instance_valid(ally):
			continue
		if not (ally is PrototypeEnemy):
			continue
		var ae: PrototypeEnemy = ally
		if not ae._is_alive():
			continue
		if _host._afflictions._charmed != ae._afflictions._charmed:
			continue
		match role:
			EnemyClass.SupportRole.HEAL:
				var pct := magnitude
				if magnitude_max > magnitude:
					pct = randf_range(magnitude, magnitude_max)
				ae.heal(int(round(float(ae.max_health) * pct)))
			EnemyClass.SupportRole.DAMAGE_BUFF:
				ae.apply_damage_buff(magnitude, buff_duration)


# ── Skill selection ────────────────────────────────────────────────────────

func pick_skill(dist: float, has_los: bool) -> EnemySkill:
	if _host._afflictions._charmed or _host._special_skills.is_empty():
		return null
	for skill: EnemySkill in _host._special_skills:
		if skill == null:
			continue
		if _skill_cooldowns.get(skill, 0.0) > 0.0:
			continue
		if skill.targeting_mode == EnemySkill.TargetingMode.SELF_BUFF:
			if _self_buff_remain <= 0.0:
				return skill
			continue
		if dist > skill.skill_range:
			continue
		if not has_los:
			continue
		return skill
	return null


func cast_skill(target: Node3D, aim: Vector3, skill: EnemySkill) -> void:
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


# ── Attack execution ───────────────────────────────────────────────────────

func cast_attack(player: Node3D, aim: Vector3) -> void:
	# Charmed enemies use whatever attack profile their class was built
	# with — forcing them to melee turned a ranged class's huge attack_range
	# into a melee cone that swept the whole room, which read as a giant
	# AoE spam instead of "this ranged ally fires at my target." The
	# projectile spawn below switches target_group on charm so allied
	# rounds hit enemies, not the player.
	if is_ranged():
		cast_ranged_attack(player, aim)
	else:
		cast_melee_attack(player, aim)


func cast_melee_attack(player: Node3D, aim: Vector3) -> void:
	_host._change_state(PrototypeEnemy.State.CASTING)
	_host._attack_cd = attack_cooldown()
	_host.velocity.x = 0.0
	_host.velocity.z = 0.0
	_host._face_direction(aim)
	var range_now := attack_range()
	var cone_now := melee_cone_deg()
	var windup_now := attack_windup()
	# Speed-scale the swing clip so its visible impact frame lands at
	# windup_now (the damage moment). Previously fixed at 1.6× — that
	# made sledge (windup 0.7s) finish the swing well before damage
	# fired, reading as "the hit comes after the animation already
	# happened." Blade (windup 0.35s) gets a faster speed here, sledge
	# gets a slower one, both ending on the damage frame.
	_host._play_swing_to_impact(XBotAnimations.random_enemy_melee_swing(), windup_now)
	CombatVisuals.spawn_cone(_host, aim, range_now, cone_now, windup_now)
	var gen := _host._generation
	await _host.get_tree().create_timer(windup_now).timeout
	if not _host.is_inside_tree() or _host._generation != gen or _host._state != PrototypeEnemy.State.CASTING:
		return
	var wid: StringName = _host.enemy_class.weapon_id if _host.enemy_class != null else &""
	if wid == &"blade":
		CombatVisuals.spawn_blade_slash(_host, aim, range_now, cone_now)
	elif wid == &"sledgehammer":
		CombatVisuals.spawn_hit_cone(_host, aim, range_now, cone_now)
		# Shockwave-ring radius tracks the actual hit range so the
		# visual ring lands at the same reach as the damage cone.
		CombatVisuals.spawn_hammer_impact(_host, range_now)
	else:
		CombatVisuals.spawn_hit_cone(_host, aim, range_now, cone_now)
	WeaponSounds.play_fire(wid, _host.global_position)
	_host._change_state(PrototypeEnemy.State.CHASING)
	if not is_instance_valid(player):
		return
	var to_p: Vector3 = player.global_position - _host.global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist > range_now or dist < 0.001:
		return
	var half_cos := cos(deg_to_rad(cone_now * 0.5))
	if aim.dot(to_p / dist) < half_cos:
		return
	if player is PrototypePlayer and not LosCuller.has_los_to_player(_host):
		return
	if player.has_method(&"take_damage"):
		var dmg := int(round(float(_host._attack_damage) * outgoing_damage_mult()))
		dmg = maxi(1, int(round(float(dmg) * PlayerCombat.range_falloff(dist, range_now))))
		player.take_damage(dmg, _host.global_position, melee_knockback())


func cast_ranged_attack(player: Node3D, aim: Vector3) -> void:
	if _host.enemy_class == null or _host.enemy_class.projectile_scene == null:
		cast_melee_attack(player, aim)
		return
	_host._change_state(PrototypeEnemy.State.CASTING)
	_host._attack_cd = attack_cooldown()
	_host.velocity.x = 0.0
	_host.velocity.z = 0.0
	_host._face_direction(aim)
	# Ranged enemies hold the firing-rifle pose during the windup so the
	# silhouette reads as "shooter aiming" rather than "puncher swinging".
	_host._play_fire_pose(true)
	var windup_now := attack_windup()
	var gen := _host._generation
	await _host.get_tree().create_timer(windup_now).timeout
	if not _host.is_inside_tree() or _host._generation != gen or _host._state != PrototypeEnemy.State.CASTING:
		return
	if not is_instance_valid(player):
		_host._change_state(PrototypeEnemy.State.CHASING)
		return
	if not LosCuller.has_los_to_player(_host):
		_host._change_state(PrototypeEnemy.State.CHASING)
		return
	var ba: EnemySkill = _host.enemy_class.basic_attack if _host.enemy_class != null else null
	var burst: int = ba.burst_count if ba != null and ba.burst_count > 1 else 1
	var burst_delay: float = ba.burst_delay if ba != null else 0.1
	var pellets: int = ba.projectile_count if ba != null and ba.projectile_count > 1 else 1
	var spread_deg: float = ba.projectile_spread_deg if ba != null else 15.0
	var ba_dmg_mult: float = ba.damage_mult if ba != null else 1.0
	var ba_blast: float = ba.projectile_blast_radius if ba != null else 0.0
	# One fire SFX per attack cycle — covers single-pellet, multi-pellet,
	# AND burst-fire weapons. Previously this was inside the burst loop,
	# which meant an LMG (burst_count=6, burst_delay=0.1) fired 6 sounds
	# over 0.6s — six ~0.3s fire clips overlapping reads as audible
	# phasing rather than rapid fire. One sound at the start represents
	# the trigger pull; the individual projectiles are the rapid-fire
	# follow-through and don't each need their own boom.
	var wid: StringName = _host.enemy_class.weapon_id if _host.enemy_class != null else &""
	if wid != &"":
		WeaponSounds.play_fire(wid, _host.global_position)
	for burst_i in burst:
		if burst_i > 0:
			await _host.get_tree().create_timer(burst_delay).timeout
			if not _host.is_inside_tree() or _host._generation != gen:
				return
			if not is_instance_valid(player):
				break
		var origin := _host.global_position + Vector3(0.0, 1.4, 0.0)
		var to_p: Vector3 = (player.global_position + Vector3(0.0, 1.0, 0.0)) - origin
		var dist := to_p.length()
		if dist < 0.001:
			break
		var center_aim := to_p / dist
		_host._face_direction(Vector3(center_aim.x, 0.0, center_aim.z).normalized())
		if pellets <= 1:
			_spawn_enemy_projectile(center_aim, ba_dmg_mult, ba_blast)
		else:
			var spread_rad := deg_to_rad(spread_deg)
			var half := (pellets - 1) * 0.5
			for i in pellets:
				var offset_angle := (float(i) - half) * spread_rad
				var rotated_aim := center_aim.rotated(Vector3.UP, offset_angle)
				_spawn_enemy_projectile(rotated_aim, ba_dmg_mult, ba_blast)
	_host._change_state(PrototypeEnemy.State.CHASING)


func _spawn_enemy_projectile(aim: Vector3, skill_damage_mult: float = 1.0, blast_radius: float = 0.0) -> void:
	if not _host.is_inside_tree():
		return
	var proj: PrototypeProjectile = EntityPool.acquire(_host.enemy_class.projectile_scene)
	if proj == null:
		return
	# Charmed allies shoot at the enemy faction; projectile.gd already
	# filters charmed pets out of the &"enemies" hit list so allied fire
	# can't friendly-fire other charms.
	proj.target_group = &"enemies" if _host._afflictions._charmed else &"player"
	proj.direction = apply_enemy_aim_spread(aim)
	proj.speed = _host.enemy_class.projectile_speed
	proj.max_range = _host.enemy_class.projectile_max_range
	proj.knockback_strength = 0.0
	proj.is_bullet = _host.enemy_class.projectile_is_bullet
	proj.blast_radius = blast_radius
	proj.source_position = _host.global_position
	var dmg := int(round(float(_host._attack_damage) * skill_damage_mult * outgoing_damage_mult()))
	proj.damage_min = dmg
	proj.damage_max = dmg
	proj.damage_mult = 1.0
	proj.accuracy = 1.0
	proj.crit_chance = 0.0
	_host.get_parent().add_child(proj)
	# Barrel offset — push the spawn forward + right of the body so
	# projectiles emerge from a "muzzle" position rather than the
	# chest center. Matches PlayerCombat's BARREL_FORWARD_OFFSET /
	# BARREL_RIGHT_OFFSET conventions. Safety-clamped (see helper
	# below) so the projectile spawn doesn't land inside a wall when
	# the enemy fires flush against geometry, or past the player when
	# firing at point-blank range — same fix shipped player-side.
	var aim_norm := proj.direction.normalized()
	proj.global_position = _safe_enemy_spawn_position(aim_norm)
	proj.monitoring = true
	proj.reset()
	# Fire sound is played ONCE per volley by the caller (basic_attack or
	# skill cast), not per projectile — shotgun / accelerator pellets all
	# emerge in the same frame and stacking 6 sounds reads as a phaser.


func apply_enemy_aim_spread(aim: Vector3) -> Vector3:
	var acc := _host.enemy_class.accuracy if _host.enemy_class != null else 0.75
	acc = clampf(acc, 0.0, 1.0)
	if randf() < acc:
		return aim
	var yaw := atan2(aim.x, aim.z)
	var pitch := asin(clampf(aim.y, -1.0, 1.0))
	var h_spread := randf_range(PrototypeEnemy.ENEMY_MISS_MIN_SPREAD, PrototypeEnemy.ENEMY_INACCURACY_SPREAD_MAX)
	if randf() < 0.5:
		h_spread = -h_spread
	var v_max := PrototypeEnemy.ENEMY_INACCURACY_SPREAD_MAX * PrototypeEnemy.ENEMY_VERTICAL_SPREAD_RATIO
	var v_spread := randf_range(-v_max, v_max)
	yaw += h_spread
	pitch += v_spread
	pitch = clampf(pitch, -PI * 0.5, PI * 0.5)
	var cos_p := cos(pitch)
	return Vector3(sin(yaw) * cos_p, sin(pitch), cos(yaw) * cos_p)


# ── Skill variants ─────────────────────────────────────────────────────────

func _cast_skill_cone(target: Node3D, aim: Vector3, skill: EnemySkill) -> void:
	_host._change_state(PrototypeEnemy.State.CASTING)
	_host._attack_cd = attack_cooldown()
	_host.velocity.x = 0.0
	_host.velocity.z = 0.0
	_host._face_direction(aim)
	# Speed-scaled swing — same rationale as cast_melee_attack.
	_host._play_swing_to_impact(XBotAnimations.random_enemy_melee_swing(), skill.wind_up)
	CombatVisuals.spawn_cone(_host, aim, skill.skill_range, skill.cone_deg, skill.wind_up)
	var gen := _host._generation
	await _host.get_tree().create_timer(skill.wind_up).timeout
	if not _host.is_inside_tree() or _host._generation != gen or _host._state != PrototypeEnemy.State.CASTING:
		return
	var wid: StringName = _host.enemy_class.weapon_id if _host.enemy_class != null else &""
	if wid == &"blade":
		CombatVisuals.spawn_blade_slash(_host, aim, skill.skill_range, skill.cone_deg)
	elif wid == &"sledgehammer":
		CombatVisuals.spawn_hit_cone(_host, aim, skill.skill_range, skill.cone_deg)
		CombatVisuals.spawn_hammer_impact(_host, skill.skill_range)
	else:
		CombatVisuals.spawn_hit_cone(_host, aim, skill.skill_range, skill.cone_deg)
	WeaponSounds.play_fire(wid, _host.global_position)
	_host._change_state(PrototypeEnemy.State.CHASING)
	if not is_instance_valid(target):
		return
	var to_p: Vector3 = target.global_position - _host.global_position
	to_p.y = 0.0
	var dist := to_p.length()
	if dist > skill.skill_range or dist < 0.001:
		return
	var half_cos := cos(deg_to_rad(skill.cone_deg * 0.5))
	if aim.dot(to_p / dist) < half_cos:
		return
	if target is PrototypePlayer and not LosCuller.has_los_to_player(_host):
		return
	if target.has_method(&"take_damage"):
		var dmg := int(round(float(_host._attack_damage) * skill.damage_mult * outgoing_damage_mult()))
		dmg = maxi(1, int(round(float(dmg) * PlayerCombat.range_falloff(dist, skill.skill_range))))
		target.take_damage(dmg, _host.global_position, skill.knockback)


func _cast_skill_radial(target: Node3D, skill: EnemySkill) -> void:
	_host._change_state(PrototypeEnemy.State.CASTING)
	_host._attack_cd = attack_cooldown()
	_host.velocity.x = 0.0
	_host.velocity.z = 0.0
	# Radial skill swing — anim peaks at the damage moment. Wider clamp
	# range than melee since AoE windups can run longer / shorter than
	# blade/sledge windups.
	_host._play_swing_to_impact(XBotAnimations.random_enemy_melee_swing(), skill.wind_up)
	CombatVisuals.spawn_radial(_host, skill.aoe_radius, skill.wind_up)
	var gen := _host._generation
	await _host.get_tree().create_timer(skill.wind_up).timeout
	if not _host.is_inside_tree() or _host._generation != gen or _host._state != PrototypeEnemy.State.CASTING:
		return
	_host._change_state(PrototypeEnemy.State.CHASING)
	var target_group: StringName = &"enemies" if _host._afflictions._charmed else &"player"
	var aoe_r := skill.aoe_radius
	for n: Node in SpatialGrid.query_radius(_host.global_position, aoe_r, target_group):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if not n.has_method(&"take_damage"):
			continue
		if n == _host:
			continue
		if _host._afflictions._charmed and n is PrototypeEnemy and (n as PrototypeEnemy).is_player_friendly():
			continue
		var dmg := int(round(float(_host._attack_damage) * skill.damage_mult * outgoing_damage_mult()))
		var dist_to_n := _host.global_position.distance_to((n as Node3D).global_position)
		dmg = maxi(1, int(round(float(dmg) * PlayerCombat.range_falloff(dist_to_n, aoe_r))))
		n.take_damage(dmg, _host.global_position, skill.knockback)


func _cast_skill_projectile(target: Node3D, aim: Vector3, skill: EnemySkill) -> void:
	_host._change_state(PrototypeEnemy.State.CASTING)
	_host._attack_cd = attack_cooldown()
	_host.velocity.x = 0.0
	_host.velocity.z = 0.0
	_host._face_direction(aim)
	# Projectile skills come from ranged casters — match cast_ranged_attack
	# and play the firing-rifle pose during windup.
	_host._play_fire_pose(true)
	var gen := _host._generation
	await _host.get_tree().create_timer(skill.wind_up).timeout
	if not _host.is_inside_tree() or _host._generation != gen or _host._state != PrototypeEnemy.State.CASTING:
		return
	_host._change_state(PrototypeEnemy.State.CHASING)
	if not is_instance_valid(target):
		return
	if not LosCuller.has_los_to_player(_host):
		return
	var burst: int = skill.burst_count if skill.burst_count > 1 else 1
	var burst_delay_val: float = skill.burst_delay if skill.burst_delay > 0.0 else 0.1
	# One fire SFX per skill cast — covers burst + multi-projectile spreads.
	# Same rationale as cast_ranged_attack above: per-burst-tick stacking
	# turned LMG-style bursts into phaser. _spawn_skill_projectile doesn't
	# play its own sound, so this single call covers every projectile in
	# the cast.
	var skill_wid: StringName = _host.enemy_class.weapon_id if _host.enemy_class != null else &""
	if skill_wid != &"":
		WeaponSounds.play_fire(skill_wid, _host.global_position)
	for burst_i in burst:
		if burst_i > 0:
			await _host.get_tree().create_timer(burst_delay_val).timeout
			if not _host.is_inside_tree() or _host._generation != gen or not _host._is_alive():
				return
			if not is_instance_valid(target):
				return
		var origin := _host.global_position + Vector3(0.0, 1.4, 0.0)
		var to_p: Vector3 = (target.global_position + Vector3(0.0, 1.0, 0.0)) - origin
		var dist := to_p.length()
		if dist < 0.001:
			return
		var center_aim := to_p / dist
		_host._face_direction(Vector3(center_aim.x, 0.0, center_aim.z).normalized())
		if skill.projectile_count <= 1:
			_spawn_skill_projectile(center_aim, skill)
		else:
			var spread_rad := deg_to_rad(skill.projectile_spread_deg)
			var count := skill.projectile_count
			var half := (count - 1) * 0.5
			for i in count:
				var offset_angle := (float(i) - half) * spread_rad
				var rotated_aim := center_aim.rotated(Vector3.UP, offset_angle)
				_spawn_skill_projectile(rotated_aim, skill)


func _spawn_skill_projectile(aim: Vector3, skill: EnemySkill) -> void:
	if skill.projectile_scene == null:
		if _host.enemy_class != null and _host.enemy_class.projectile_scene != null:
			_spawn_enemy_projectile(aim)
		return
	var proj: PrototypeProjectile = EntityPool.acquire(skill.projectile_scene)
	if proj == null:
		return
	proj.target_group = &"player"
	proj.direction = apply_enemy_aim_spread(aim)
	proj.speed = skill.projectile_speed
	proj.max_range = skill.projectile_max_range
	proj.knockback_strength = skill.knockback
	proj.source_position = _host.global_position
	var dmg := int(round(float(_host._attack_damage) * skill.damage_mult * outgoing_damage_mult()))
	proj.damage_min = dmg
	proj.damage_max = dmg
	proj.damage_mult = 1.0
	proj.accuracy = 1.0
	proj.crit_chance = 0.0
	_host.get_parent().add_child(proj)
	# Barrel offset — same as _spawn_enemy_projectile.
	var aim_norm := proj.direction.normalized()
	proj.global_position = _safe_enemy_spawn_position(aim_norm)
	proj.monitoring = true
	proj.reset()


# Mirror of PlayerCombat._safe_projectile_spawn_position. Prefers the
# weapon model's per-weapon muzzle override (read via
# WeaponAttachment.get_muzzle_position — the same API the player uses,
# so projectile spawns sit at the actual barrel tip of the equipped
# weapon mesh and respect per-gender grip-table overrides). Falls back
# to the legacy chest+forward approximation when no weapon model is
# mounted (bare-hand attackers, missing skeleton, etc.). Then ray-checks
# chest → barrel for walls / pillars / player body; obstruction → spawn
# at chest so the projectile doesn't self-collide.
func _safe_enemy_spawn_position(aim_norm: Vector3) -> Vector3:
	var chest: Vector3 = _host.global_position + Vector3(0.0, 1.4, 0.0)
	var barrel_pos: Vector3
	var skel := _host._find_skeleton(_host.visual) if _host.visual != null else null
	var weapon_muzzle := Vector3.ZERO
	if skel != null:
		weapon_muzzle = WeaponAttachment.get_muzzle_position(skel, aim_norm)
	if weapon_muzzle != Vector3.ZERO:
		barrel_pos = weapon_muzzle
	else:
		# Legacy approximation — chest + forward + right.
		var aim_right := Vector3.UP.cross(aim_norm).normalized()
		var barrel := aim_norm * 0.7 + aim_right * 0.25
		barrel_pos = chest + barrel
	if not _host.is_inside_tree():
		return barrel_pos
	# Physics state is only readable inside the physics frame. Calling
	# space.intersect_ray() from input handlers / animation callbacks
	# / _process logs `Space state is inaccessible right now, wait for
	# iteration or physics process notification` per call. Enemy fire
	# fires from a wind-up timer that resolves outside the physics
	# frame, so every shot hit this trap (484 errors in one playtest +
	# the synchronous stderr writes dominated proc time). Bail to the
	# raw barrel position when we can't safely raycast — the projectile
	# loses its safety clamp but the alternative (spamming + crashing
	# perf) is worse. Same guard pattern proximity_lighting uses.
	if not Engine.is_in_physics_frame():
		return barrel_pos
	var world := _host.get_world_3d()
	if world == null:
		return barrel_pos
	var space := world.direct_space_state
	if space == null:
		return barrel_pos
	var query := PhysicsRayQueryParameters3D.create(chest, barrel_pos)
	# Walls + pillars + player. Use the player mask since enemy
	# projectiles target the player; charmed-pet enemies don't fire
	# (they melee), so we don't need CHARMED_ALLY_LAYER_MASK here.
	query.collision_mask = PrototypeProjectile.PROJECTILE_WORLD_MASK | PrototypeProjectile.PLAYER_LAYER_MASK
	if _host is CollisionObject3D:
		query.exclude = [(_host as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return chest
	return barrel_pos


func _cast_skill_self_buff(skill: EnemySkill) -> void:
	_host._change_state(PrototypeEnemy.State.CASTING)
	_host.velocity.x = 0.0
	_host.velocity.z = 0.0
	_host._play_anim(XBotAnimations.random_enemy_melee_swing(), 1.4)
	var gen := _host._generation
	await _host.get_tree().create_timer(skill.wind_up).timeout
	if not _host.is_inside_tree() or _host._generation != gen or _host._state != PrototypeEnemy.State.CASTING:
		return
	_host._change_state(PrototypeEnemy.State.CHASING)
	_self_buff_remain = skill.buff_duration
	_self_buff_damage_mult = skill.buff_damage_mult
	_self_buff_speed_mult = skill.buff_speed_mult
