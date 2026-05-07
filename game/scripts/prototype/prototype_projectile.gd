extends Area3D
class_name PrototypeProjectile

const PROTO_BASE_CRIT_CHANCE: float = 0.15
const PROTO_BASE_CRIT_MULT: float = 1.5

# Point-blank penalty mirrored from PlayerCombat — 25% accuracy reduction
# at short range. Both player- and enemy-fired projectiles obey this; if
# the player charges into a ranged enemy, that enemy's bolts also miss
# more often.
const MELEE_RANGE_THRESHOLD: float = 2.5
const MELEE_RANGE_ACCURACY_MULT: float = 0.75
# World-layer raycast mask for the per-frame sweep. Walls + structures live
# on layer 1; targets get handled by Area3D body_entered so we don't need
# to ray-test them.
const WORLD_LAYER_MASK := 1
const ENEMY_LAYER_MASK := 2
const PLAYER_LAYER_MASK := 4
# Charmed pets sit on this layer (PrototypeEnemy._LAYER_CHARMED_ALLY).
# Enemy-fired projectiles include this in their mask so they can hit
# pets the same way they can hit the player.
const CHARMED_ALLY_LAYER_MASK := 16

var direction: Vector3 = Vector3.FORWARD
var speed: float = 30.0
var max_range: float = 20.0
var damage_min: int = 0
var damage_max: int = 0
var damage_mult: float = 1.0
var accuracy: float = 1.0
var crit_chance: float = 0.0
var knockback_strength: float = 0.0
var source_position: Vector3 = Vector3.ZERO
## Skip the point-blank accuracy penalty. Set by drones and other sources
## that always fire at close range by design.
var ignore_melee_penalty: bool = false
## Group whose members the projectile damages. Anything else on the
## collision_mask (i.e. walls) just stops the bolt without damage. The
## spawner sets this to &"enemies" for player-fired bolts and &"player"
## for enemy-fired bolts; collision_mask is derived in reset() to match.
var target_group: StringName = &"enemies"
## AoE blast radius on impact. When > 0 the projectile explodes on hit,
## damaging all targets in range instead of just the one it struck.
var blast_radius: float = 0.0
## Visual scale multiplier for the mesh + glow. 1.0 = default bolt size.
var visual_scale: float = 1.0

var _traveled: float = 0.0
var _hit: bool = false
var _connected: bool = false
var _released: bool = false

func _ready() -> void:
	_connect_signal()

func _connect_signal() -> void:
	if not _connected:
		body_entered.connect(_on_body_entered)
		_connected = true

func reset() -> void:
	_traveled = 0.0
	_hit = false
	set_physics_process(true)
	_connect_signal()
	# Set collision_mask for the side this bolt is hitting. World always.
	# Targets per group: &"enemies" → enemy layer; &"player" → player
	# AND pet layers (so enemy projectiles can kill the player's pets,
	# not just whiff through them). Player projectiles continue to hit
	# only the enemy layer — pets are filtered by the script-level
	# is_player_friendly check in _on_body_entered.
	var target_mask := (PLAYER_LAYER_MASK | CHARMED_ALLY_LAYER_MASK) if target_group == &"player" else ENEMY_LAYER_MASK
	collision_mask = WORLD_LAYER_MASK | target_mask
	# Scale the visual mesh + glow to match the skill's visual weight.
	var vis := get_node_or_null(^"Visual") as MeshInstance3D
	if vis != null:
		vis.scale = Vector3.ONE * visual_scale
	var glow := get_node_or_null(^"Glow") as OmniLight3D
	if glow != null:
		glow.omni_range = 5.0 * visual_scale
		glow.light_energy = 3.0 * visual_scale
	# body_entered only fires when a body crosses INTO the area on a later
	# physics frame; if a target is already overlapping at spawn (close-
	# range fire), the signal never triggers. Defer a sweep over current
	# overlaps so we catch those.
	call_deferred(&"_check_initial_overlaps")


func _check_initial_overlaps() -> void:
	if _hit or not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		if body == null or not is_instance_valid(body):
			continue
		if body.is_in_group(target_group):
			_on_body_entered(body)
			return

func _pool_release() -> void:
	_traveled = 0.0
	_hit = false
	_released = false
	monitoring = false
	# Reset target_group so a re-acquired bolt doesn't inherit the prior
	# owner's friendly-fire side. Spawner is expected to set it before
	# reset(), but the default keeps existing player-fire callers working.
	target_group = &"enemies"
	ignore_melee_penalty = false
	blast_radius = 0.0
	visual_scale = 1.0

func _physics_process(delta: float) -> void:
	var step := speed * delta
	var from := global_position
	var to := from + direction * step
	# Sweep raycast against world geometry between this frame's start and
	# end positions. At speed=30 / 60Hz the bullet moves 0.5m per frame —
	# more than wall_thickness (0.4m) — so Area3D overlap detection alone
	# tunnels through thin walls. The ray catches the wall before we set
	# the new position.
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER_MASK)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit.position
			_traveled += from.distance_to(hit.position)
			_hit = true
			_release()
			return
	global_position = to
	_traveled += step
	if _traveled >= max_range:
		_release()

func _on_body_entered(body: Node3D) -> void:
	if _hit:
		return
	_hit = true
	# Enemy-fired projectiles target the player AND any charmed pets (which
	# are in the &"enemies" group but flagged player-friendly). Player-fired
	# projectiles only damage enemies and skip player-friendly ones below.
	var is_valid_target := body.is_in_group(target_group)
	if not is_valid_target and target_group == &"player":
		if body.has_method(&"is_player_friendly") and body.is_player_friendly():
			is_valid_target = true
	if is_valid_target and body.has_method(&"take_damage"):
		# Player-fired projectiles skip player-friendly (charmed) enemies —
		# no friendly fire from drones, telekinesis bolts, or ranged
		# weapons. The projectile passes through and continues to the
		# next valid target, but since we already set _hit=true above, we
		# just _release() instead.
		if target_group == &"enemies" and body.has_method(&"is_player_friendly") and body.is_player_friendly():
			_release()
			return
		var impact_pos := body.global_position + Vector3(0.0, 0.9, 0.0)
		if blast_radius > 0.0:
			_explode(impact_pos)
		else:
			_hit_single(body, impact_pos)
	_release()


func _hit_single(body: Node3D, impact_pos: Vector3) -> void:
	PrototypeAttackIndicator.spawn_impact_burst(self, impact_pos, _projectile_color())
	if _roll_hit(body.global_position):
		var is_crit := _roll_crit()
		var dmg := _roll_damage(is_crit)
		if target_group == &"player":
			body.take_damage(dmg, source_position, knockback_strength)
		else:
			body.take_damage(dmg, source_position, knockback_strength, 1, is_crit)
			_apply_exile_curse_if_active(body)
	elif target_group == &"enemies":
		DamageNumber.spawn_miss(body.get_parent(), body.global_position + Vector3(0.0, 1.8, 0.0))


func _explode(impact_pos: Vector3) -> void:
	# Larger impact burst scaled to the blast radius.
	PrototypeAttackIndicator.spawn_explosion(self, impact_pos, blast_radius, _projectile_color())
	# Damage every target inside the blast radius.
	var targets: Array[Node3D] = SpatialGrid.query_radius(
		global_position, blast_radius, target_group)
	for target: Node3D in targets:
		if not target.has_method(&"take_damage"):
			continue
		if target_group == &"enemies" and target.has_method(&"is_player_friendly") and target.is_player_friendly():
			continue
		if _roll_hit(target.global_position):
			var is_crit := _roll_crit()
			var dmg := _roll_damage(is_crit)
			if target_group == &"player":
				target.take_damage(dmg, source_position, knockback_strength)
			else:
				target.take_damage(dmg, source_position, knockback_strength, 1, is_crit)
				_apply_exile_curse_if_active(target)
		elif target_group == &"enemies":
			DamageNumber.spawn_miss(target.get_parent(), target.global_position + Vector3(0.0, 1.8, 0.0))


# Duplicates PlayerCombat.EXILE_CURSE_DURATION rather than reaching across
# class_names — the projectile doesn't otherwise depend on PlayerCombat
# and a literal here keeps the projectile self-contained. Keep these in
# sync if the curse window is ever retuned.
const EXILE_CURSE_DURATION: float = 4.0


func _apply_exile_curse_if_active(enemy: Node) -> void:
	var pct: float = Effects.get_aggregate(&"exile_curse_damage_pct")
	if pct <= 0.0:
		return
	if enemy.has_method(&"apply_curse"):
		enemy.apply_curse(pct, EXILE_CURSE_DURATION)

func _release() -> void:
	# Called from physics callback contexts (body_entered, _physics_process), so
	# defer the pool return — EntityPool.release synchronously toggles `monitoring`
	# and removes this Area3D from the tree, both forbidden during physics.
	if _released:
		return
	_released = true
	EntityPool.release.call_deferred(self)


func _projectile_color() -> Color:
	var glow := get_node_or_null(^"Glow") as OmniLight3D
	if glow != null:
		return glow.light_color
	return Color(0.4, 0.85, 1.0)


func _roll_hit(target_pos: Vector3) -> bool:
	# Point-blank penalty: if the projectile traveled less than the melee
	# threshold from its fire origin to where it hit, halve accuracy. Same
	# rule PlayerCombat applies to hitscan; mirrored here so both firing
	# modes behave identically and the player can't game one over the other.
	#
	# The Count "Point Blank" talent waives the penalty for player-fired
	# projectiles (target_group == &"enemies"). Enemy-fired bolts always
	# obey the rule — the player still benefits from charging into a
	# ranged enemy regardless of which class they're playing.
	var eff_acc := accuracy
	if not ignore_melee_penalty and source_position.distance_to(target_pos) < MELEE_RANGE_THRESHOLD:
		var player_fired := target_group == &"enemies"
		var ignore_penalty := player_fired and Effects.get_aggregate(&"ignore_point_blank_penalty") > 0.0
		if not ignore_penalty:
			eff_acc *= MELEE_RANGE_ACCURACY_MULT
	if eff_acc >= 1.0:
		return true
	return randf() < eff_acc

func _roll_crit() -> bool:
	var base := crit_chance if crit_chance > 0.0 else PROTO_BASE_CRIT_CHANCE
	var chance := base + Effects.get_aggregate(&"crit_chance_pct")
	return randf() < chance

func _roll_damage(is_crit: bool) -> int:
	var base := randi_range(damage_min, damage_max) if damage_max > 0 else 10
	var dmg := int(round(float(base) * damage_mult))
	if is_crit:
		var mult := PROTO_BASE_CRIT_MULT + Effects.get_aggregate(&"crit_damage_pct")
		dmg = int(round(float(dmg) * mult))
	return dmg
