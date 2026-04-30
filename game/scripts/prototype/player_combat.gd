class_name PlayerCombat
extends Node

## Handles skill resolution, damage rolling, cooldown tracking, and projectile
## spawning for the player. Extracted from PrototypePlayer to keep that file
## focused on movement, input, and state management.

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_projectile.tscn")

const PROTO_BASE_CRIT_CHANCE: float = 0.15
const PROTO_BASE_CRIT_MULT: float = 1.5

var _host: PrototypePlayer
var _cooldowns: Dictionary = {}

func setup(host: PrototypePlayer) -> void:
	_host = host

func tick_cooldowns(delta: float) -> void:
	for skill in _cooldowns.keys():
		_cooldowns[skill] = maxf(0.0, _cooldowns[skill] - delta)

func is_on_cooldown(skill: Skill) -> bool:
	return _cooldowns.get(skill, 0.0) > 0.0

func start_cooldown(skill: Skill, atk_speed: float) -> void:
	_cooldowns[skill] = skill.cooldown / atk_speed

func get_cooldown_ratio(skill: Skill) -> float:
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	var remaining: float = _cooldowns.get(skill, 0.0)
	return clampf(remaining / skill.cooldown, 0.0, 1.0)

func clear_cooldowns() -> void:
	_cooldowns.clear()

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

func resolve_skill_hit(skill: Skill, aim: Vector3, weapon: Item) -> void:
	var eff_range := effective_range(skill, weapon)
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			PrototypeAttackIndicator.spawn_hit_cone(_host, aim, eff_range, skill.cone_deg)
			_resolve_cone(skill, aim, eff_range, weapon)
		Skill.TargetingMode.AOE_RADIAL:
			PrototypeAttackIndicator.spawn_hit_radial(_host, eff_range)
			_resolve_aoe(skill, eff_range, weapon)
		Skill.TargetingMode.PROJECTILE:
			_spawn_projectile(skill, aim, eff_range, weapon)
		Skill.TargetingMode.HITSCAN:
			_resolve_hitscan(skill, aim, eff_range, weapon)

# ---------------------------------------------------------------------------
# Hit patterns
# ---------------------------------------------------------------------------

func _resolve_cone(skill: Skill, aim: Vector3, eff_range: float, weapon: Item) -> void:
	var half_cos := cos(deg_to_rad(skill.cone_deg * 0.5))
	var hits := PerkState.roll_multistrike()
	for enode: Node3D in SpatialGrid.query_cone(_host.global_position, aim, eff_range, half_cos, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		for _i in hits:
			if not _roll_hit(weapon):
				continue
			var is_crit := _roll_crit(weapon)
			var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
			enode.take_damage(dmg, _host.global_position, skill.knockback, hits, is_crit)

func _resolve_aoe(skill: Skill, eff_range: float, weapon: Item) -> void:
	var hits := PerkState.roll_multistrike()
	for enode: Node3D in SpatialGrid.query_radius(_host.global_position, eff_range, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		for _i in hits:
			if not _roll_hit(weapon):
				continue
			var is_crit := _roll_crit(weapon)
			var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
			enode.take_damage(dmg, _host.global_position, skill.knockback, hits, is_crit)

func _spawn_projectile(skill: Skill, aim: Vector3, eff_range: float, weapon: Item) -> void:
	var proj: PrototypeProjectile = EntityPool.acquire(PROJECTILE_SCENE)
	proj.direction = aim.normalized()
	proj.speed = skill.projectile_speed
	proj.max_range = eff_range
	proj.knockback_strength = skill.knockback
	proj.source_position = _host.global_position
	if weapon != null and weapon.damage_max > 0:
		proj.damage_min = weapon.damage_min
		proj.damage_max = weapon.damage_max
		proj.accuracy = weapon.accuracy
		proj.crit_chance = weapon.crit_chance
	else:
		proj.damage_min = skill.damage
		proj.damage_max = skill.damage
	proj.damage_mult = AttributeState.get_player_damage_mult(PlayerState.class_id, PlayerState.spec_id)
	var spawn_pos := _host.global_position + aim.normalized() * 0.5 + Vector3(0.0, 1.0, 0.0)
	_host.get_parent().add_child(proj)
	proj.global_position = spawn_pos
	proj.monitoring = true
	proj.reset()

func _resolve_hitscan(skill: Skill, aim: Vector3, eff_range: float, weapon: Item) -> void:
	var hits := PerkState.roll_multistrike()
	var origin := _host.global_position + Vector3(0.0, 1.0, 0.0)
	var aim_norm := aim.normalized()
	var wall_dist := eff_range
	var space := _host.get_world_3d().direct_space_state
	var ray_end := origin + aim_norm * eff_range
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, 1, [_host.get_rid()])
	var result := space.intersect_ray(query)
	if not result.is_empty():
		wall_dist = origin.distance_to(result["position"])
	var half_cos := cos(deg_to_rad(2.5))
	var hit_target: Node3D = null
	var closest_dist := INF
	for enode: Node3D in SpatialGrid.query_cone(_host.global_position, aim, wall_dist, half_cos, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		var dist := _host.global_position.distance_squared_to(enode.global_position)
		if dist < closest_dist:
			closest_dist = dist
			hit_target = enode
	var beam_end := wall_dist
	if hit_target != null:
		beam_end = minf(beam_end, _host.global_position.distance_to(hit_target.global_position))
	PrototypeAttackIndicator.spawn_beam(_host, aim, beam_end)
	if hit_target == null:
		return
	for _i in hits:
		if not _roll_hit(weapon):
			continue
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		hit_target.take_damage(dmg, _host.global_position, skill.knockback, hits, is_crit)

# ---------------------------------------------------------------------------
# Damage rolling
# ---------------------------------------------------------------------------

func _roll_crit(weapon: Item = null) -> bool:
	var base_crit := weapon.crit_chance if weapon != null and weapon.crit_chance > 0.0 else PROTO_BASE_CRIT_CHANCE
	var chance := base_crit + PerkState.get_aggregate(&"crit_chance_pct")
	return randf() < chance

func _roll_hit(weapon: Item) -> bool:
	if weapon == null or weapon.accuracy >= 1.0:
		return true
	return randf() < weapon.accuracy

func _roll_skill_damage(skill: Skill, weapon: Item) -> int:
	var base: int
	if weapon != null and weapon.damage_max > 0:
		base = randi_range(weapon.damage_min, weapon.damage_max)
	else:
		base = skill.damage
	var mult := AttributeState.get_player_damage_mult(PlayerState.class_id, PlayerState.spec_id)
	return int(round(float(base) * mult))

func _crit_damage(base: int, is_crit: bool) -> int:
	if not is_crit:
		return base
	var mult := PROTO_BASE_CRIT_MULT + PerkState.get_aggregate(&"crit_damage_pct")
	return int(round(float(base) * mult))
