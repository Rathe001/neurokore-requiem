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
# Charmed pets sit on this layer (PrototypeEnemy._LAYER_CHARMED_ALLY).
# Enemy-fired projectiles include this in their mask so they can hit
# pets the same way they can hit the player.
const CHARMED_ALLY_LAYER_MASK := 16

var direction: Vector3 = Vector3.FORWARD
var speed: float = 14.0
var max_range: float = 20.0
var damage_min: int = 0
var damage_max: int = 0
var damage_mult: float = 1.0
var crit_chance: float = 0.0
var knockback_strength: float = 0.0
var source_position: Vector3 = Vector3.ZERO
# Retained for compatibility with enemy/drone spawners that set these.
# Player accuracy is now handled by aim spread at spawn time; these
# fields are no-ops for player-fired projectiles.
var accuracy: float = 1.0
var ignore_melee_penalty: bool = false
var _ray_query := PhysicsRayQueryParameters3D.new()
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

# Visual presets. Bullets (laser bolts — small, fast, no AoE) render as a
# thin elongated BoxMesh that streaks along travel direction. AoE shots
# (charged plasma, anything with blast_radius > 0) keep the original
# SphereMesh from the .tscn so the heavier hit reads as a glowing orb.
# The discriminator is `blast_radius > 0` set by the spawner before reset().
const LASER_BOX_SIZE: Vector3 = Vector3(0.07, 0.07, 0.55)
static var _laser_mesh: BoxMesh = null
# Cached on first reset so we can swap back to the authored sphere when an
# AoE shot is acquired from the same pool slot that previously held a bullet.
var _sphere_mesh_cache: Mesh = null

# Side-tinted material variants. Player fire keeps the authored cyan plasma
# look; enemy fire (target_group == &"player") swaps to a red variant so the
# player can read incoming bolts at a glance. Both are static caches built
# off the .tscn-defined material the first time a projectile resets.
const PLAYER_PROJECTILE_COLOR: Color = Color(0.4, 0.85, 1.0, 1.0)
const ENEMY_PROJECTILE_COLOR: Color = Color(1.0, 0.88, 0.15, 1.0)
static var _player_material: StandardMaterial3D = null
static var _enemy_material: StandardMaterial3D = null

static func _get_laser_mesh() -> BoxMesh:
	if _laser_mesh == null:
		_laser_mesh = BoxMesh.new()
		_laser_mesh.size = LASER_BOX_SIZE
	return _laser_mesh

# First call captures the authored cyan material as the player variant, then
# clones+retints it for the enemy variant. Subsequent calls are free.
static func _ensure_side_materials(default_mat: StandardMaterial3D) -> void:
	if _player_material == null:
		_player_material = default_mat
	if _enemy_material == null and _player_material != null:
		var m: StandardMaterial3D = _player_material.duplicate()
		m.albedo_color = ENEMY_PROJECTILE_COLOR
		m.emission = ENEMY_PROJECTILE_COLOR
		_enemy_material = m

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
	# Swap visual based on shot type. AoE shots keep the authored sphere;
	# regular bullets get the elongated laser box, oriented along travel
	# (look_at on the projectile node so the box's Z axis aligns with
	# direction and the streak reads as motion blur).
	var enemy_fire := target_group == &"player"
	var tint: Color = ENEMY_PROJECTILE_COLOR if enemy_fire else PLAYER_PROJECTILE_COLOR
	var vis := get_node_or_null(^"Visual") as MeshInstance3D
	if vis != null:
		if _sphere_mesh_cache == null:
			_sphere_mesh_cache = vis.mesh
		if blast_radius > 0.0:
			vis.mesh = _sphere_mesh_cache
		else:
			vis.mesh = _get_laser_mesh()
		vis.scale = Vector3.ONE * visual_scale
		# Side-tint the material. The authored material on the .tscn becomes
		# the player variant; the enemy variant is cloned-and-retinted on
		# first need. Both are reused across pool acquires.
		var src := vis.material_override as StandardMaterial3D
		if src != null:
			_ensure_side_materials(src)
		if enemy_fire and _enemy_material != null:
			vis.material_override = _enemy_material
		elif _player_material != null:
			vis.material_override = _player_material
	if blast_radius <= 0.0 and direction.length_squared() > 0.0001:
		# look_at requires a target distinct from current position; offset
		# along direction (already-normalized at spawn). Up vector defaults
		# to world Y — fine since fire trajectories are near-horizontal.
		look_at(global_position + direction, Vector3.UP)
	else:
		# Reset rotation for sphere shots so a previous bullet's basis
		# doesn't leak through (visually irrelevant but keeps the node tidy).
		rotation = Vector3.ZERO
	var glow := get_node_or_null(^"Glow") as OmniLight3D
	if glow != null:
		glow.omni_range = 5.0 * visual_scale
		glow.light_energy = 3.0 * visual_scale
		# Drives _projectile_color() too — impact bursts and explosion VFX
		# pick up the side color automatically.
		glow.light_color = tint
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
	accuracy = 1.0
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
		_ray_query.from = from
		_ray_query.to = to
		_ray_query.collision_mask = WORLD_LAYER_MASK
		_ray_query.collide_with_areas = false
		_ray_query.collide_with_bodies = true
		var hit := space.intersect_ray(_ray_query)
		if not hit.is_empty():
			var impact_pos: Vector3 = hit.position
			global_position = impact_pos
			_traveled += from.distance_to(impact_pos)
			_hit = true
			# Spawn the impact visual on the wall surface so the bolt
			# doesn't just vanish. AoE shots detonate their full explosion
			# against the wall — query_radius from impact_pos still catches
			# any targets clustered near the impact point.
			if blast_radius > 0.0:
				_explode(impact_pos)
			else:
				CombatVisuals.spawn_impact_burst(self, impact_pos, _projectile_color())
			_release()
			return
	global_position = to
	_traveled += step
	if _traveled >= max_range:
		_release()

# True when `body` is a charmed enemy (player-friendly mind-controlled pet).
# Used by collision logic to decide whether a projectile should hit. The
# narrow PrototypeEnemy type-check is critical: PrototypePlayer also has an
# is_player_friendly method, but its signature takes a target argument and
# calling it without one crashes. Routing through this helper keeps the
# signature mismatch contained.
static func _is_charmed_pet(body: Node) -> bool:
	if not (body is PrototypeEnemy):
		return false
	return (body as PrototypeEnemy).is_player_friendly()


func _on_body_entered(body: Node3D) -> void:
	if _hit:
		return
	_hit = true
	# Enemy-fired projectiles target the player AND any charmed pets (which
	# are in the &"enemies" group but flagged player-friendly). Player-fired
	# projectiles only damage enemies and skip player-friendly ones below.
	#
	# is_player_friendly() exists on TWO classes with DIFFERENT signatures:
	#   PrototypeEnemy.is_player_friendly() -> bool          (no args)
	#   PrototypePlayer.is_player_friendly(target: Node) -> bool
	# Calling on a PrototypePlayer without args crashes. Use _is_charmed_pet
	# helper to keep the call constrained to enemies.
	var is_valid_target := body.is_in_group(target_group)
	if not is_valid_target and target_group == &"player":
		# Charmed pets are valid targets for enemy projectiles (the host's
		# own minions get hit by hostile fire).
		if _is_charmed_pet(body):
			is_valid_target = true
		# Remote-player avatars (other peers' characters on this client)
		# live in the &"remote_player" group, not &"player". They're still
		# valid targets for enemy projectiles — visual hit on the client,
		# damage applied authoritatively on host.
		elif body.is_in_group(&"remote_player"):
			is_valid_target = true
	if is_valid_target and body.has_method(&"take_damage"):
		# Player-fired projectiles skip player-friendly (charmed) enemies —
		# no friendly fire from drones, telekinesis bolts, or ranged
		# weapons. Same _is_charmed_pet helper to avoid the signature
		# mismatch on PrototypePlayer.
		if target_group == &"enemies" and _is_charmed_pet(body):
			_release()
			return
		var impact_pos := body.global_position + Vector3(0.0, 0.9, 0.0)
		if blast_radius > 0.0:
			_explode(impact_pos)
		else:
			_hit_single(body, impact_pos)
	_release()


func _hit_single(body: Node3D, impact_pos: Vector3) -> void:
	CombatVisuals.spawn_impact_burst(self, impact_pos, _projectile_color())
	var is_crit := _roll_crit()
	var dmg := _roll_damage(is_crit)
	if target_group == &"player":
		body.take_damage(dmg, source_position, knockback_strength)
	else:
		PrototypeEnemy.deal_damage(body, dmg, source_position, knockback_strength, 1, is_crit)
		_apply_exile_curse_if_active(body)
		_apply_mindlink(body, dmg, is_crit)
		_try_spawn_isr_drone(body)


func _explode(impact_pos: Vector3) -> void:
	CombatVisuals.spawn_explosion(self, impact_pos, blast_radius, _projectile_color())
	var targets: Array[Node3D] = SpatialGrid.query_radius(
		global_position, blast_radius, target_group)
	for target: Node3D in targets:
		if not target.has_method(&"take_damage"):
			continue
		if target_group == &"enemies" and target.has_method(&"is_player_friendly") and target.is_player_friendly():
			continue
		var is_crit := _roll_crit()
		var dmg := _roll_damage(is_crit)
		if target_group == &"player":
			target.take_damage(dmg, source_position, knockback_strength)
		else:
			PrototypeEnemy.deal_damage(target, dmg, source_position, knockback_strength, 1, is_crit)
			_apply_exile_curse_if_active(target)
			_apply_mindlink(target, dmg, is_crit)
			_try_spawn_isr_drone(target)


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


# Duplicates PlayerCombat.MINDLINK_RADIUS — same self-contained rationale
# as the exile curse above. Keep in sync.
const MINDLINK_RADIUS: float = 6.0
# Static guard so projectile mindlink echoes don't chain.
static var _mindlink_echoing: bool = false

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
		if n.has_method(&"is_player_friendly") and n.is_player_friendly():
			continue
		var d2 := primary.global_position.distance_squared_to(n.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = n
	if best == null:
		return
	CombatVisuals.spawn_impact_burst(primary, best.global_position + Vector3(0.0, 0.9, 0.0))
	_mindlink_echoing = true
	PrototypeEnemy.deal_damage(best, dmg, source_position, 0.0, 1, is_crit)
	_mindlink_echoing = false


func _try_spawn_isr_drone(enemy: Node3D) -> void:
	if target_group != &"enemies":
		return
	var chance := Effects.get_aggregate(&"isr_drone_chance")
	if chance <= 0.0 or randf() >= chance:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method(&"is_player_friendly") and enemy.is_player_friendly():
		return
	ISRDrone.spawn_on(enemy)


func _release() -> void:
	if _released:
		return
	_released = true
	EntityPool.release.call_deferred(self)


func _projectile_color() -> Color:
	var glow := get_node_or_null(^"Glow") as OmniLight3D
	if glow != null:
		return glow.light_color
	return Color(0.4, 0.85, 1.0)


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
