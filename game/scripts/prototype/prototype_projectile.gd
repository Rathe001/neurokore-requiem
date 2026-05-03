extends Area3D
class_name PrototypeProjectile

const PROTO_BASE_CRIT_CHANCE: float = 0.15
const PROTO_BASE_CRIT_MULT: float = 1.5
# World-layer raycast mask for the per-frame sweep. Walls + structures live
# on layer 1; targets get handled by Area3D body_entered so we don't need
# to ray-test them.
const WORLD_LAYER_MASK := 1
const ENEMY_LAYER_MASK := 2
const PLAYER_LAYER_MASK := 4

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
## Group whose members the projectile damages. Anything else on the
## collision_mask (i.e. walls) just stops the bolt without damage. The
## spawner sets this to &"enemies" for player-fired bolts and &"player"
## for enemy-fired bolts; collision_mask is derived in reset() to match.
var target_group: StringName = &"enemies"

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
	# Targets per group: &"enemies" → enemy layer; &"player" → player layer.
	# Other targets fall back to enemies (current player-fire default).
	var target_mask := PLAYER_LAYER_MASK if target_group == &"player" else ENEMY_LAYER_MASK
	collision_mask = WORLD_LAYER_MASK | target_mask
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
	# In-target-group → roll damage. Anything else (walls, decorative bodies)
	# just stops the bolt without applying anything. The collision_mask set
	# in reset() already filters out non-target friendlies, so this branch
	# is mostly belt-and-braces against future layer changes.
	if body.is_in_group(target_group) and body.has_method(&"take_damage"):
		# Player-fired projectiles skip player-friendly (charmed) enemies —
		# no friendly fire from drones, telekinesis bolts, or ranged
		# weapons. The projectile passes through and continues to the
		# next valid target, but since we already set _hit=true above, we
		# just _release() instead.
		if target_group == &"enemies" and body.has_method(&"is_player_friendly") and body.is_player_friendly():
			_release()
			return
		if _roll_hit():
			var is_crit := _roll_crit()
			var dmg := _roll_damage(is_crit)
			# Player and enemy take_damage signatures both accept the same
			# leading args; player ignores the trailing (multistrike, is_crit)
			# extras since its signature stops earlier.
			if target_group == &"player":
				body.take_damage(dmg, source_position, knockback_strength)
			else:
				body.take_damage(dmg, source_position, knockback_strength, 1, is_crit)
				# Count Exile — apply curse on player-fired projectile hits
				# the same way PlayerCombat does for cone/aoe/hitscan paths.
				# Projectiles run async from PlayerCombat so the perk-aggregate
				# read happens here at impact.
				_apply_exile_curse_if_active(body)
	_release()


# Duplicates PlayerCombat.EXILE_CURSE_DURATION rather than reaching across
# class_names — the projectile doesn't otherwise depend on PlayerCombat
# and a literal here keeps the projectile self-contained. Keep these in
# sync if the curse window is ever retuned.
const EXILE_CURSE_DURATION: float = 4.0


func _apply_exile_curse_if_active(enemy: Node) -> void:
	var pct: float = PerkState.get_aggregate(&"exile_curse_damage_pct")
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

func _roll_hit() -> bool:
	if accuracy >= 1.0:
		return true
	return randf() < accuracy

func _roll_crit() -> bool:
	var base := crit_chance if crit_chance > 0.0 else PROTO_BASE_CRIT_CHANCE
	var chance := base + PerkState.get_aggregate(&"crit_chance_pct")
	return randf() < chance

func _roll_damage(is_crit: bool) -> int:
	var base := randi_range(damage_min, damage_max) if damage_max > 0 else 10
	var dmg := int(round(float(base) * damage_mult))
	if is_crit:
		var mult := PROTO_BASE_CRIT_MULT + PerkState.get_aggregate(&"crit_damage_pct")
		dmg = int(round(float(dmg) * mult))
	return dmg
