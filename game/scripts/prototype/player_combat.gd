class_name PlayerCombat
extends Node

## Handles skill resolution, damage rolling, cooldown tracking, and projectile
## spawning for the player. Extracted from PrototypePlayer to keep that file
## focused on movement, input, and state management.

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_projectile.tscn")

const PROTO_BASE_CRIT_CHANCE: float = 0.15
const PROTO_BASE_CRIT_MULT: float = 1.5

# Count Exile constants. EXILE_CURSE_DURATION is the medium-long window
# the curse persists after each hit (refreshed by subsequent hits, so a
# pressured enemy stays tagged). EXILE_AUTO_SHOT_BASE_DAMAGE is the
# unmultiplied damage of the auto-shot fired on curse expire — scaled
# at fire time by AttributeState.get_player_damage_mult so investing
# Orthodoxy makes the expire shot heavier as well as the curse heavier.
const EXILE_CURSE_DURATION: float = 4.0
const EXILE_AUTO_SHOT_BASE_DAMAGE: int = 60
const EXILE_AUTO_SHOT_RANGE: float = 30.0

var _host: PrototypePlayer
var _cooldowns: Dictionary = {}
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
	_cooldowns[skill] = skill.cooldown / atk_speed

func get_cooldown_ratio(skill: Skill) -> float:
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	var remaining: float = _cooldowns.get(skill, 0.0)
	return clampf(remaining / skill.cooldown, 0.0, 1.0)

func is_slot_on_cooldown(slot: StringName) -> bool:
	return _slot_cooldowns.get(slot, 0.0) > 0.0

func start_slot_cooldown(slot: StringName, skill: Skill, atk_speed: float) -> void:
	if skill == null or skill.cooldown <= 0.0:
		return
	_slot_cooldowns[slot] = skill.cooldown / atk_speed

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

func resolve_skill_hit(skill: Skill, aim: Vector3, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	var eff_range := effective_range(skill, weapon)
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			PrototypeAttackIndicator.spawn_hit_cone(_host, aim, eff_range, skill.cone_deg)
			_resolve_cone(skill, aim, eff_range, weapon)
		Skill.TargetingMode.AOE_RADIAL:
			PrototypeAttackIndicator.spawn_hit_radial(_host, eff_range)
			_resolve_aoe(skill, eff_range, weapon)
		Skill.TargetingMode.PROJECTILE:
			_spawn_projectile(skill, aim, eff_range, weapon, source_offset)
		Skill.TargetingMode.HITSCAN:
			_resolve_hitscan(skill, aim, eff_range, weapon, source_offset)

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
		_apply_exile_curse_if_active(enode)

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
		_apply_exile_curse_if_active(enode)

func _spawn_projectile(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
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
	# Spawn at the player's position (slightly elevated), plus the per-arm
	# offset for Forged Amalgamation extras (right / left / above). Spawning
	# ahead of the player would skip enemies standing right next to us;
	# player collision_layer doesn't match the projectile mask so no self-
	# hit; the projectile sweeps forward and catches close-range targets
	# via PrototypeProjectile._check_initial_overlaps().
	var spawn_pos := _host.global_position + Vector3(0.0, 1.0, 0.0) + source_offset
	_host.get_parent().add_child(proj)
	proj.global_position = spawn_pos
	proj.monitoring = true
	proj.reset()

func _resolve_hitscan(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	var hits := PerkState.roll_multistrike()
	# Same per-arm offset as projectiles so the beam visibly emanates from
	# the right / left / above point on Forged Amalgamation extras.
	var origin := _host.global_position + Vector3(0.0, 1.0, 0.0) + source_offset
	var aim_norm := aim.normalized()
	var wall_dist := eff_range
	var hit_target: Node3D = null
	var space := _host.get_world_3d().direct_space_state
	var ray_end := origin + aim_norm * eff_range
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, 1)
	var result := space.intersect_ray(query)
	if not result.is_empty():
		wall_dist = origin.distance_to(result["position"])
	var half_cos := cos(deg_to_rad(2.5))
	var closest_dist := INF
	# Cone query origin matches the visual beam origin so the damage
	# pattern shifts with the per-arm offset — Forged Amalgamation extras
	# act as independent firing points, not just visual flair.
	for enode: Node3D in SpatialGrid.query_cone(origin, aim_norm, wall_dist, half_cos, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		var dist := origin.distance_squared_to(enode.global_position)
		if dist < closest_dist:
			closest_dist = dist
			hit_target = enode
	var beam_end := wall_dist
	if hit_target != null:
		beam_end = minf(beam_end, origin.distance_to(hit_target.global_position))
	PrototypeAttackIndicator.spawn_beam(_host, aim, beam_end, source_offset)
	if hit_target == null:
		return
	for _i in hits:
		if not _roll_hit(weapon):
			continue
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		hit_target.take_damage(dmg, _host.global_position, skill.knockback, hits, is_crit)
	_apply_exile_curse_if_active(hit_target)

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

# ---------------------------------------------------------------------------
# Count Exile — apply curse on hit + auto-fire massive shot on expire
# ---------------------------------------------------------------------------

# Apply (or refresh) the Exile curse on a freshly-hit enemy. Called by every
# damage path (cone / aoe / projectile / hitscan) right after take_damage so
# the perk works regardless of weapon shape. No-op when the perk isn't
# active or the target was killed by the same hit.
func _apply_exile_curse_if_active(enemy: Node) -> void:
	var pct: float = PerkState.get_aggregate(&"exile_curse_damage_pct")
	if pct <= 0.0:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method(&"apply_curse"):
		enemy.apply_curse(pct, EXILE_CURSE_DURATION)


# Called by PrototypeEnemy when a curse expires. Fires a hitscan from the
# player toward the (possibly still-alive) target. If the target is dead /
# freed, the shot fizzles silently — no fallback target. Damage scales
# with main stat so investing Orthodoxy heavies up both the curse AND the
# expire shot.
func fire_exile_shot(target: Node3D) -> void:
	if _host == null or target == null or not is_instance_valid(target):
		return
	if not target.has_method(&"take_damage"):
		return
	var origin := _host.global_position + Vector3(0.0, 1.0, 0.0)
	var to_target := target.global_position + Vector3(0.0, 0.9, 0.0) - origin
	var dist := to_target.length()
	if dist > EXILE_AUTO_SHOT_RANGE:
		return
	var aim := to_target.normalized()
	# LoS check — wall in the way kills the auto-shot before it lands
	# (matches the "if it hits" wording in the perk description).
	var space := _host.get_world_3d().direct_space_state
	var ray_end := origin + aim * dist
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, 1)
	var result := space.intersect_ray(query)
	if not result.is_empty():
		# Show the beam to the wall hit so the player sees the failed shot,
		# then bail without damage.
		var wall_dist: float = origin.distance_to(result["position"])
		PrototypeAttackIndicator.spawn_beam(_host, aim, wall_dist)
		return
	PrototypeAttackIndicator.spawn_beam(_host, aim, dist)
	var dmg := int(round(float(EXILE_AUTO_SHOT_BASE_DAMAGE) * AttributeState.get_player_damage_mult(PlayerState.class_id, PlayerState.spec_id)))
	target.take_damage(dmg, _host.global_position, 0.0, 1, false)
