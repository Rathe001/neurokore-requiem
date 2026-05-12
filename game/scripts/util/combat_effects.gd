class_name CombatEffects
extends RefCounted
## Shared on-hit effects used by both PlayerCombat (melee / hitscan) and
## PrototypeProjectile (projectile hits). Centralises Exile curse, Mindlink
## echo, and ISR drone spawn so the logic lives in one place.

const EXILE_CURSE_DURATION: float = 4.0
const MINDLINK_RADIUS: float = 6.0

static var _mindlink_echoing: bool = false


static func is_player_friendly(target: Node) -> bool:
	return target.has_method(&"is_player_friendly") and target.is_player_friendly()


static func apply_exile_curse_if_active(enemy: Node) -> void:
	var pct: float = Effects.get_aggregate(&"exile_curse_damage_pct")
	if pct <= 0.0:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method(&"apply_curse"):
		enemy.apply_curse(pct, EXILE_CURSE_DURATION)


## Echo damage to the nearest non-friendly enemy within MINDLINK_RADIUS of
## the primary target. `deal_damage_fn` is a Callable that applies damage
## so each caller can route through its own pipeline (PlayerCombat._deal_damage
## vs PrototypeEnemy.deal_damage).
static func apply_mindlink(
	primary: Node3D,
	dmg: int,
	is_crit: bool,
	source_pos: Vector3,
	deal_damage_fn: Callable,
	spawn_beam: bool = true,
) -> void:
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
	if spawn_beam:
		var link_dir := best.global_position - primary.global_position
		var link_dist := link_dir.length()
		if link_dist > 0.001:
			CombatVisuals.spawn_beam(primary, link_dir.normalized(), link_dist)
	CombatVisuals.spawn_impact_burst(primary, best.global_position + Vector3(0.0, 0.9, 0.0))
	_mindlink_echoing = true
	deal_damage_fn.call(best, dmg, source_pos, 0.0, 1, is_crit)
	_mindlink_echoing = false


static func try_spawn_isr_drone(enemy: Node3D) -> void:
	var chance := Effects.get_aggregate(&"isr_drone_chance")
	if chance <= 0.0 or randf() >= chance:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if is_player_friendly(enemy):
		return
	ISRDrone.spawn_on(enemy)
