class_name PlayerDoomsayer
extends Node

## Enculted Doomsayer aura — every DOOMSAYER_TICK_INTERVAL seconds the
## aura runs two passes over enemies in radius: a CHARM pass (the perk
## itself, capped by doomsayer_max_charms) and an optional DAMAGE pass
## (gated by the "Aura of Dread" talent, magnitude in the
## doomsayer_dot_per_tick TalentState aggregate). Charm is persistent
## (held in _charmed_enemies, no timer); DoT applies per-tick scaled by
## linear distance falloff.

const DOOMSAYER_AURA_RADIUS_PER_TIER: Array[float] = [0.0, 5.0, 7.0, 9.0]
const DOOMSAYER_TICK_INTERVAL := 0.4
const DOOMSAYER_MAX_CHARMS_CAP := 8

var _host: PrototypePlayer
var _doomsayer_t: float = 0.0
var _doomsayer_aura: DoomsayerAura = null
var _charmed_enemies: Array[PrototypeEnemy] = []


func setup(host: PrototypePlayer) -> void:
	_host = host
	_doomsayer_aura = DoomsayerAura.new()
	# Parent the aura to the player (a Node3D) directly. PlayerDoomsayer is
	# a plain Node — a Node3D child of a non-Node3D parent doesn't inherit
	# its transform, so adding the aura here would leave it stuck at world
	# origin (visible as the aura locked to the spawn room).
	_host.add_child(_doomsayer_aura)
	reconcile()


func get_charm_count() -> int:
	return _charmed_enemies.size()


func get_charm_max() -> int:
	return mini(int(round(Effects.get_aggregate(&"doomsayer_max_charms"))), DOOMSAYER_MAX_CHARMS_CAP)


func tick(delta: float) -> void:
	if not _host.is_alive():
		return
	var max_charms_agg := Effects.get_aggregate(&"doomsayer_max_charms")
	if max_charms_agg <= 0.0:
		return
	_doomsayer_t -= delta
	if _doomsayer_t > 0.0:
		return
	_doomsayer_t = DOOMSAYER_TICK_INTERVAL
	# Use a fixed radius now that stat tiers don't drive it.
	var radius: float = DOOMSAYER_AURA_RADIUS_PER_TIER[clampi(1, 0, 3)]
	if radius <= 0.0:
		return
	var dot_per_tick: float = TalentState.get_aggregate(&"doomsayer_dot_per_tick")
	var dmg_mult := 1.0
	var max_charms := mini(int(round(Effects.get_aggregate(&"doomsayer_max_charms"))), DOOMSAYER_MAX_CHARMS_CAP)
	_prune_charm_list()
	var charm_capacity := max_charms - _charmed_enemies.size()
	var charm_candidate: PrototypeEnemy = null
	var charm_candidate_dist_sq := INF
	for n in SpatialGrid.query_radius(_host.global_position, radius, &"enemies"):
		if not (n is PrototypeEnemy) or not is_instance_valid(n):
			continue
		var enemy: PrototypeEnemy = n
		if enemy.is_player_friendly():
			continue
		if not LosCuller.has_los_to_player(enemy):
			continue
		var dist := _host.global_position.distance_to(enemy.global_position)
		var falloff := clampf(1.0 - dist / radius, 0.0, 1.0)
		if dot_per_tick > 0.0 and falloff > 0.0 and enemy.has_method(&"take_damage"):
			var dmg_f := dot_per_tick * falloff * dmg_mult
			var dmg := maxi(1, int(round(dmg_f)))
			# is_dot=true → take_damage skips the per-hit blood burst +
			# floor droplets. The aura ticks every 0.4s for every enemy
			# in range; without the gate, 10 enemies in range produced
			# 25 droplet stamps/sec that carpeted the floor.
			PrototypeEnemy.deal_damage(enemy, dmg, _host.global_position, 0.0, 1, false, &"", false, true)
		if charm_capacity > 0 and enemy.is_charmable():
			var d2 := _host.global_position.distance_squared_to(enemy.global_position)
			if d2 < charm_candidate_dist_sq:
				charm_candidate_dist_sq = d2
				charm_candidate = enemy
	if charm_candidate != null and charm_capacity > 0:
		if charm_candidate.apply_charm():
			_charmed_enemies.append(charm_candidate)
			_emit_charm_count_changed()


## Called on PerkState.perks_changed — reconciles both charms and aura.
func reconcile() -> void:
	_reconcile_charms()
	_reconcile_aura()


func cleanup() -> void:
	_clear_charms()
	_reconcile_aura()


func _emit_charm_count_changed() -> void:
	_host.charm_count_changed.emit(_charmed_enemies.size(), get_charm_max())


func _prune_charm_list() -> void:
	var prev_size := _charmed_enemies.size()
	var live: Array[PrototypeEnemy] = []
	for e in _charmed_enemies:
		if e != null and is_instance_valid(e) and e.is_in_group(&"enemies"):
			live.append(e)
		elif e != null and is_instance_valid(e):
			e.release_charm()
	_charmed_enemies = live
	if _charmed_enemies.size() != prev_size:
		_emit_charm_count_changed()


func _clear_charms() -> void:
	var had_any := not _charmed_enemies.is_empty()
	for e in _charmed_enemies:
		if e != null and is_instance_valid(e):
			e.release_charm()
	_charmed_enemies.clear()
	if had_any:
		_emit_charm_count_changed()


func _reconcile_charms() -> void:
	_prune_charm_list()
	var target := 0
	if _host.is_alive():
		target = mini(int(round(Effects.get_aggregate(&"doomsayer_max_charms"))), DOOMSAYER_MAX_CHARMS_CAP)
	while _charmed_enemies.size() > target:
		var oldest: PrototypeEnemy = _charmed_enemies.pop_front()
		if oldest != null and is_instance_valid(oldest):
			oldest.release_charm()
	_emit_charm_count_changed()


func _reconcile_aura() -> void:
	if _doomsayer_aura == null:
		return
	var tier := 0
	if _host.is_alive() and Effects.get_aggregate(&"doomsayer_max_charms") > 0.0:
		tier = 1
	_doomsayer_aura.set_tier(tier)
