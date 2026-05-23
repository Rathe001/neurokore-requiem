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
# Decorative pillars sit on Layer 8 — physical obstacles that block
# bullets the same as walls but stay transparent to LoS culling and
# proximity lighting (which still raycast Layer 1 only).
const PILLAR_LAYER_MASK := 128
# Combined "blocks projectiles" world mask — walls/floors/ceilings on
# Layer 1, decorative pillars on Layer 8. Used both for the per-frame
# sweep raycast and for the active collision_mask alongside the target's
# own layer.
const PROJECTILE_WORLD_MASK := WORLD_LAYER_MASK | PILLAR_LAYER_MASK

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
## True when the projectile represents a physical bullet (LMG, SMG, sniper,
## RPG fire). Swaps the visual to a thin gray streak with a low-emissive
## warble — reads as a heat-distortion trail rather than the energy bolts
## of plasma/laser weapons. Set by the spawner before reset().
var is_bullet: bool = false
## Multiplayer replication flag. When true, this projectile is a visual
## echo of another peer's shot — it travels and renders, but never applies
## damage and never spawns its own impact_burst / explosion (the firing
## peer's RPCs handle those). collision_mask is forced to world-only on
## reset() so the sweep still stops at walls but Area3D body_entered
## won't fire on enemies. Cleared by _pool_release().
var is_ghost: bool = false
## Plasma rifle "Pierce" — extra enemies the projectile passes through
## before stopping. Each pierce decrements; when 0, the next hit
## releases as normal. Bolts don't lose damage on pierce — every
## pierced target takes full damage.
var pierce_count: int = 0
## Weapon archetype identifier — set by PlayerCombat from the firing
## weapon's base id ("sniper_2h", "smg_1h", etc). Read by hit handlers
## so per-archetype quirks (Sniper First Mark, SMG Penetration counter)
## can fire from inside the projectile without a back-reference to
## the firing weapon Item.
var weapon_base_id: StringName = &""
## Shotgun "Point Blank" — pellets that hit within this many meters of
## their spawn point deal `point_blank_bonus_mult` × damage. Reinforces
## the close-range commitment design: Point Blank talent waives the
## accuracy penalty, this quirk REWARDS taking the risk. 0 = disabled.
var point_blank_bonus_distance: float = 0.0
var point_blank_bonus_mult: float = 1.0
# Elemental damage type carried over from the firing weapon. Used by
# AoE projectiles to spawn explosions in the matching element color
# (cryo RPG → cyan blast, electric → violet, default → orange
# fireball). Empty StringName for kinetic / neutral.
var damage_type: StringName = &""
## Sniper headshot bonus — percentage bonus applied on first-mark hits.
## Stacks additively with the base first-mark multiplier.
var headshot_bonus_pct: int = 0
## SMG ricochet — percentage chance on hit to deal instant damage to the
## nearest other enemy with a visible arc. Single-bounce only.
var ricochet_chance_pct: int = 0
## Laser overcharge — percentage chance for any shot to deal 2× damage.
var overcharge_chance_pct: int = 0

var _traveled: float = 0.0
var _hit: bool = false
var _connected: bool = false
var _released: bool = false

# Visual presets. Bullets (laser bolts — small, fast, no AoE) render as a
# thin elongated BoxMesh that streaks along travel direction. AoE shots
# (charged plasma, anything with blast_radius > 0) keep the original
# SphereMesh from the .tscn so the heavier hit reads as a glowing orb.
# The discriminator is `blast_radius > 0` set by the spawner before reset().
# Sizes halved from the original cartoonish-bullet pass: head is a
# small dot and the trail tapers to a short streak instead of a
# meter-long rod. Bullets still register at a glance against dark
# corridors thanks to the wake-refraction shader on the trail and
# the muzzle flash at fire — but they no longer dominate the frame.
# Previous values, kept for reference:
#   LASER_BOX_SIZE   = Vector3(0.03, 0.03, 0.55)
#   BULLET_HEAD_SIZE = Vector3(0.05, 0.05, 0.16)
#   BULLET_TRAIL_SIZE= Vector3(0.07, 0.07, 1.4)
const LASER_BOX_SIZE: Vector3 = Vector3(0.018, 0.018, 0.38)
# Bullet visual is split into two pieces:
#   • Visual (existing MeshInstance3D, used as the "head"): a small flat
#     rectangle leading the projectile so the player sees a discrete
#     round, not a glowing rod.
#   • Trail (created at runtime, child of the projectile): a short thin
#     box BEHIND the head running the shockwave shader, so the round
#     leaves a wake of refracted screen pixels rather than a
#     symmetrical bubble around itself. Bubble→trail collapses the
#     screen footprint per bullet, which fixes the texture-flicker /
#     vibration when many SMG rounds are in flight overlapping the
#     world.
const BULLET_HEAD_SIZE: Vector3 = Vector3(0.022, 0.022, 0.09)
const BULLET_TRAIL_SIZE: Vector3 = Vector3(0.035, 0.035, 0.7)
# Distortion / chroma values tuned smaller than the melee shockwave —
# a per-bullet wake has to read at a glance from a single moving
# round, so we trade intensity for clarity.
const BULLET_DISTORTION := 0.045
const BULLET_CHROMA := 0.008
const BULLET_RIM_STRENGTH := 0.18
const BULLET_BODY_ALPHA := 0.05
const BULLET_RIM_ALPHA := 0.45
const BULLET_SHADER: Shader = preload("res://scripts/prototype/shockwave_bubble.gdshader")
static var _laser_mesh: BoxMesh = null
static var _bullet_head_mesh: BoxMesh = null
static var _bullet_trail_mesh: BoxMesh = null
static var _bullet_head_material: StandardMaterial3D = null
# Rocket mesh — capsule shape used by AoE bullet projectiles (RPG).
# Distinguishes the rocket visually from the sphere meshes that
# energy AoE shots (charged plasma) use, so the player reads
# "incoming rocket" at a glance from the projectile silhouette.
static var _rocket_mesh: CapsuleMesh = null
static var _rocket_material: StandardMaterial3D = null
var _trail_node: MeshInstance3D = null
# Smoke trail — only created on demand for AoE bullet projectiles.
# GPUParticles3D in world-space (not local) so emitted puffs stay
# where the rocket WAS while the rocket itself flies forward,
# producing the visible drag-trail.
var _smoke_trail: GPUParticles3D = null
# Cached on first reset so we can swap back to the authored sphere when an
# AoE shot is acquired from the same pool slot that previously held a bullet.
var _sphere_mesh_cache: Mesh = null

# Side-tinted material variants. Player fire keeps the authored cyan plasma
# look; enemy fire (target_group == &"player") swaps to a red variant so the
# player can read incoming bolts at a glance. Both are static caches built
# off the .tscn-defined material the first time a projectile resets.
const PLAYER_PROJECTILE_COLOR: Color = Color(0.4, 0.85, 1.0, 1.0)
const ENEMY_PROJECTILE_COLOR: Color = Color(1.0, 0.88, 0.15, 1.0)
# Physical bullets — desaturated near-white tracer, very low emission so
# the streak reads as motion blur / heat distortion rather than an energy
# bolt. Same mesh footprint as the laser variant, just retinted.
const BULLET_PROJECTILE_COLOR: Color = Color(0.92, 0.92, 0.88, 0.65)

# Linear-impulse force applied to ragdoll corpses caught in an AoE shot's
# blast. Same scale as grenade explosions (CORPSE_IMPULSE_MAX/MIN in
# prototype_grenade.gd) so a charged plasma shot and a frag grenade feel
# similar at the corpse-physics level. See the comment block in
# prototype_grenade.gd for the math behind 1.5/0.4 (RPG corpse-shove was
# previously netting ~96 m/s on the hip — across the room in a heartbeat).
const CORPSE_IMPULSE_MAX: float = 1.5
const CORPSE_IMPULSE_MIN: float = 0.4

static var _player_material: StandardMaterial3D = null
static var _enemy_material: StandardMaterial3D = null
static var _bullet_material: ShaderMaterial = null

static func _get_laser_mesh() -> BoxMesh:
	if _laser_mesh == null:
		_laser_mesh = BoxMesh.new()
		_laser_mesh.size = LASER_BOX_SIZE
	return _laser_mesh


static func _get_bullet_head_mesh() -> BoxMesh:
	if _bullet_head_mesh == null:
		_bullet_head_mesh = BoxMesh.new()
		_bullet_head_mesh.size = BULLET_HEAD_SIZE
	return _bullet_head_mesh


static func _get_bullet_trail_mesh() -> BoxMesh:
	if _bullet_trail_mesh == null:
		_bullet_trail_mesh = BoxMesh.new()
		_bullet_trail_mesh.size = BULLET_TRAIL_SIZE
	return _bullet_trail_mesh


static func _get_bullet_head_material() -> StandardMaterial3D:
	if _bullet_head_material == null:
		# Solid but dim — barely visible "round" leading the trail.
		# Unshaded so it reads the same in dark zones / under any
		# lighting profile, no emission glow that would betray the
		# physical-bullet identity.
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.85, 0.82, 0.74, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.emission_enabled = true
		m.emission = Color(0.95, 0.92, 0.85, 1.0)
		m.emission_energy_multiplier = 0.25
		_bullet_head_material = m
	return _bullet_head_material


static func _get_rocket_mesh() -> CapsuleMesh:
	if _rocket_mesh == null:
		_rocket_mesh = CapsuleMesh.new()
		_rocket_mesh.radius = 0.06
		_rocket_mesh.height = 0.36
		_rocket_mesh.radial_segments = 10
		_rocket_mesh.rings = 3
	return _rocket_mesh


static func _get_rocket_material() -> StandardMaterial3D:
	if _rocket_material == null:
		# Dark metallic body with a faint orange-red glow at the
		# bottom — matches the rear thruster of a fired rocket. Fully
		# shaded (not unshaded) so the pit / wall lights actually
		# illuminate the moving warhead instead of it reading flat.
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.22, 0.22, 0.24, 1.0)
		m.metallic = 0.6
		m.roughness = 0.35
		m.emission_enabled = true
		m.emission = Color(1.0, 0.5, 0.15, 1.0)
		m.emission_energy_multiplier = 0.4
		_rocket_material = m
	return _rocket_material

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
	_get_bullet_trail_material()


# Trail material — screen-space refraction shader (same shader the
# melee shockwaves use). Applied to the wake box behind the bullet
# head; the head itself uses the dim unshaded head material so the
# round reads as a discrete object instead of a refraction blob.
# Decoupled from _ensure_side_materials so callers (e.g. _ensure_trail_node)
# can pull the trail material without depending on the projectile's
# Visual having an authored StandardMaterial3D.
static func _get_bullet_trail_material() -> ShaderMaterial:
	if _bullet_material == null:
		var b := ShaderMaterial.new()
		b.shader = BULLET_SHADER
		b.set_shader_parameter(&"distortion", BULLET_DISTORTION)
		b.set_shader_parameter(&"chroma", BULLET_CHROMA)
		b.set_shader_parameter(&"rim_strength", BULLET_RIM_STRENGTH)
		b.set_shader_parameter(&"body_alpha", BULLET_BODY_ALPHA)
		b.set_shader_parameter(&"rim_alpha_max", BULLET_RIM_ALPHA)
		b.set_shader_parameter(&"intensity", 1.0)
		_bullet_material = b
	return _bullet_material


func _ensure_trail_node() -> void:
	if _trail_node != null:
		return
	var node := MeshInstance3D.new()
	node.name = "Trail"
	node.mesh = _get_bullet_trail_mesh()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _get_bullet_trail_material()
	# +Z is "behind" the projectile after look_at (which faces -Z toward
	# travel direction). Half the trail length back puts the front face
	# of the trail box flush with the projectile origin and extends the
	# wake away from the round's path of travel.
	node.position = Vector3(0.0, 0.0, BULLET_TRAIL_SIZE.z * 0.5)
	add_child(node)
	_trail_node = node


func _ensure_smoke_trail() -> void:
	if _smoke_trail != null:
		return
	var ps := GPUParticles3D.new()
	ps.name = "SmokeTrail"
	# Particles in WORLD space — emitted at the rocket's current
	# position but their motion is independent. As the rocket moves
	# forward, fresh puffs spawn ahead while older ones stay where
	# they were emitted, which IS the trail.
	ps.local_coords = false
	ps.amount = 28
	ps.lifetime = 0.6
	ps.fixed_fps = 30
	ps.emitting = false  # toggled on per-cast in reset() for RPG only
	# Process material — slow upward drift, mild outward spread, gray
	# smoke fading to transparent over particle lifetime.
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.5, 0.0)  # smoke rises slightly
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.0, 0.6, 0.0)  # additional upward float
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.25
	pm.scale_max = 0.45
	pm.color = Color(0.55, 0.55, 0.55, 0.7)
	# Color ramp: mid-gray on spawn → darker as smoke disperses,
	# alpha tweens to zero over lifetime so puffs fade out cleanly.
	var ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.65, 0.65, 0.65, 0.85),
		Color(0.4, 0.4, 0.4, 0.4),
		Color(0.2, 0.2, 0.2, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.gradient = grad
	pm.color_ramp = ramp
	ps.process_material = pm
	# Draw mesh — small sphere with unshaded material that uses
	# vertex color so the per-particle ramp drives the look.
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = draw_mat
	ps.draw_pass_1 = mesh
	add_child(ps)
	_smoke_trail = ps

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
	collision_mask = PROJECTILE_WORLD_MASK | target_mask
	# Ghost projectiles (MP visual echoes of another peer's shot) drop
	# their target mask so Area3D body_entered never fires for them —
	# the per-frame world raycast still stops them at walls, but they
	# can't trigger _on_body_entered on enemies / players. Damage is
	# host-authoritative; impact bursts + explosions arrive via the
	# firing peer's separate replicated calls, so the ghost just
	# travels and silently releases.
	if is_ghost:
		collision_mask = PROJECTILE_WORLD_MASK
	# Swap visual based on shot type. AoE shots keep the authored sphere;
	# regular bullets get the elongated laser box, oriented along travel
	# (look_at on the projectile node so the box's Z axis aligns with
	# direction and the streak reads as motion blur).
	var enemy_fire := target_group == &"player"
	# Tint priority: bullet visuals take precedence over the player/enemy
	# laser tints — physical bullets read the same regardless of who fired.
	var tint: Color
	if is_bullet:
		tint = BULLET_PROJECTILE_COLOR
	elif enemy_fire:
		tint = ENEMY_PROJECTILE_COLOR
	else:
		tint = PLAYER_PROJECTILE_COLOR
	# is_rocket: AoE bullet (RPG variants). Three-way mesh swap:
	#   • is_rocket → capsule mesh, oriented horizontally, smoke trail
	#   • bullet (kinetic, no AoE) → small head mesh + distortion trail
	#   • non-bullet AoE → authored sphere (charged plasma etc.)
	#   • non-bullet non-AoE → laser box (default energy bolt)
	var is_rocket := is_bullet and blast_radius > 0.0
	var vis := get_node_or_null(^"Visual") as MeshInstance3D
	if vis != null:
		if _sphere_mesh_cache == null:
			_sphere_mesh_cache = vis.mesh
		if is_rocket:
			# Rocket: capsule body. CapsuleMesh's height runs along
			# local Y by default — we rotate the visual mesh so its
			# Y aligns with the projectile's -Z (travel direction)
			# and the rocket's nose points forward. Rotation is set
			# below after the mesh swap so we don't fight the look_at.
			vis.mesh = _get_rocket_mesh()
			vis.position = Vector3.ZERO
			vis.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
		elif blast_radius > 0.0:
			vis.mesh = _sphere_mesh_cache
			vis.position = Vector3.ZERO
			vis.rotation = Vector3.ZERO
		elif is_bullet:
			# Bullets: visual mesh becomes a small rectangular HEAD placed
			# slightly ahead of the projectile origin (-Z is travel after
			# the look_at below). The distortion TRAIL is a separate child
			# (_trail_node) extending behind. This produces the
			# rectangle-leading-a-trail look instead of a symmetrical
			# bubble that overlaps walls and produces screen-shimmer.
			vis.mesh = _get_bullet_head_mesh()
			vis.position = Vector3(0.0, 0.0, -BULLET_HEAD_SIZE.z * 0.5)
			vis.rotation = Vector3.ZERO
		else:
			vis.mesh = _get_laser_mesh()
			vis.position = Vector3.ZERO
			vis.rotation = Vector3.ZERO
		vis.scale = Vector3.ONE * visual_scale
		# Side-tint the material. The authored material on the .tscn becomes
		# the player variant; the enemy variant is cloned-and-retinted on
		# first need. Bullet head uses a dim unshaded material; the
		# rocket gets its own metallic body material; the distortion lives
		# on the trail node, not the head.
		var src := vis.material_override as StandardMaterial3D
		if src != null:
			_ensure_side_materials(src)
		if is_rocket:
			vis.material_override = _get_rocket_material()
		elif is_bullet:
			vis.material_override = _get_bullet_head_material()
		elif enemy_fire and _enemy_material != null:
			vis.material_override = _enemy_material
		elif _player_material != null:
			vis.material_override = _player_material
		# Shadow casting: rockets are physical projectiles, not energy,
		# so they should drop a shadow on the floor as they fly. Authored
		# default on the .tscn is OFF (laser bolts wouldn't cast shadows
		# and updating shadow maps for many bolts a frame is expensive),
		# so toggle ON for rockets and back OFF for every other variant
		# in case a pool slot is reused.
		if is_rocket:
			vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else:
			vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Distortion trail — for KINETIC bullets only (not rockets, which
	# get the smoke trail instead). Created lazily so non-bullet
	# projectiles in the pool never carry the extra node.
	if is_bullet and not is_rocket:
		_ensure_trail_node()
		if _trail_node != null:
			_trail_node.visible = true
			_trail_node.scale = Vector3.ONE * visual_scale
	elif _trail_node != null:
		_trail_node.visible = false
	# Smoke trail — rockets only. World-space particle system that
	# emits gray puffs as the rocket flies; particles stay where they
	# were emitted while the rocket moves on, producing the visible
	# drag-trail. Toggled emission so non-rocket pool reuses don't
	# carry over puffing.
	if is_rocket:
		_ensure_smoke_trail()
		if _smoke_trail != null:
			_smoke_trail.emitting = true
			_smoke_trail.restart()
	elif _smoke_trail != null:
		_smoke_trail.emitting = false
	# Orient toward travel direction for everything except non-rocket AoE
	# (charged plasma spheres look the same from every angle, so the
	# look_at is skipped and rotation zeroed to keep the basis tidy).
	# Rockets are AoE *and* directional — the capsule has a clear nose/
	# tail, so they need look_at even though blast_radius > 0.
	if direction.length_squared() > 0.0001 and (blast_radius <= 0.0 or is_rocket):
		# Pick an up vector NOT parallel to direction. Airstrike rockets
		# travel along world Y (Vector3.DOWN), so the default Vector3.UP
		# is colinear with the target — Godot logs a warning and the
		# basis is undefined. Vector3.FORWARD (or any horizontal axis)
		# works for vertical travel; UP works for horizontal travel.
		var up := Vector3.UP
		if absf(direction.y) > 0.95:
			up = Vector3.FORWARD
		look_at(global_position + direction, up)
	else:
		rotation = Vector3.ZERO
	var glow := get_node_or_null(^"Glow") as OmniLight3D
	if glow != null:
		# Bullets are PHYSICAL — no glow halo at all. This also kills the
		# stale "fires-north" phantom seen in playtest where the laser
		# Glow's prior position lingered for a frame on a re-acquired pool
		# slot before reset overwrote it.
		if is_bullet:
			glow.visible = false
			glow.light_energy = 0.0
		else:
			glow.visible = true
			# Glow halo tightened to match the smaller energy-bolt mesh
			# — was 5.0 range / 3.0 energy which created a brighter
			# halo than the bolt itself and made every plasma round
			# look like a slow basketball-sized orb.
			glow.omni_range = 3.5 * visual_scale
			glow.light_energy = 2.0 * visual_scale
			glow.light_specular = 0.0
			# Drives _projectile_color() too — impact bursts and explosion
			# VFX pick up the side color automatically.
			glow.light_color = tint
	# body_entered only fires when a body crosses INTO the area on a later
	# physics frame; if a target is already overlapping at spawn (close-
	# range fire), the signal never triggers. Defer a sweep over current
	# overlaps so we catch those. Ghosts have monitoring=false so they
	# can never hit anything via Area3D — skip the deferred call to
	# save the per-shot dispatch cost at MP scale.
	if not is_ghost:
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
	damage_type = &""
	# Stop the smoke trail emitting on pool release — without this the
	# rocket's puffs continue spawning at the projectile's last
	# position (which moves to the pool holder) until the next
	# acquire. Looks like a frozen smoke trail in the void.
	if _smoke_trail != null:
		_smoke_trail.emitting = false
	is_bullet = false
	is_ghost = false
	pierce_count = 0
	point_blank_bonus_distance = 0.0
	point_blank_bonus_mult = 1.0
	weapon_base_id = &""
	headshot_bonus_pct = 0
	ricochet_chance_pct = 0
	overcharge_chance_pct = 0
	# Reset falloff visual fade so pooled projectiles start opaque.
	var vis := get_node_or_null(^"Visual") as MeshInstance3D
	if vis != null:
		vis.transparency = 0.0
	if _trail_node != null:
		_trail_node.transparency = 0.0

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
		_ray_query.collision_mask = PROJECTILE_WORLD_MASK
		_ray_query.collide_with_areas = false
		_ray_query.collide_with_bodies = true
		var hit := space.intersect_ray(_ray_query)
		if not hit.is_empty():
			var impact_pos: Vector3 = hit.position
			# Sweep mask includes PILLAR — which destructible props also sit
			# on (so their tall bullet-catch collision blocks cover-targeted
			# rays). Without this check the sweep would release the
			# projectile as a "wall hit" and Area3D.body_entered would never
			# fire, so damage never lands on the prop. Route PILLAR-layer
			# damage targets through _on_body_entered so they take damage
			# the same way a layer-2 hit would.
			var collider: Variant = hit.get("collider")
			if collider is Node3D and (collider as Node3D).is_in_group(target_group):
				global_position = impact_pos
				_traveled += from.distance_to(impact_pos)
				_on_body_entered(collider as Node3D)
				return
			global_position = impact_pos
			_traveled += from.distance_to(impact_pos)
			_hit = true
			# Ghost projectiles release silently — impact_burst and
			# explosion visuals come from the firing peer's separate
			# replicated calls; doubling them up here would show two
			# bursts per shot.
			if is_ghost:
				_release()
				return
			# Spawn the impact visual on the wall surface so the bolt
			# doesn't just vanish. AoE shots detonate their full explosion
			# against the wall — query_radius from impact_pos still catches
			# any targets clustered near the impact point.
			if blast_radius > 0.0:
				_explode(impact_pos)
			elif not is_bullet:
				# Bullets are physical rounds — they punch holes, they don't
				# detonate against walls. Skip the energy-burst flash that
				# laser/plasma shots use for their wall-impact tell.
				CombatVisuals.spawn_impact_burst(self, impact_pos, _projectile_color())
			_release()
			return
	global_position = to
	_traveled += step
	# Visual fade in falloff zone — projectile dims as damage drops.
	if _traveled > max_range:
		var t := clampf((_traveled - max_range) / max_range, 0.0, 1.0)
		var alpha := 1.0 - 0.75 * t
		var vis := get_node_or_null(^"Visual") as MeshInstance3D
		if vis != null:
			vis.transparency = 1.0 - alpha
		if _trail_node != null and _trail_node.visible:
			_trail_node.transparency = 1.0 - alpha
	if _traveled >= max_range * PlayerCombat.FALLOFF_RANGE_MULT:
		# AoE projectiles (RPG rockets, charged plasma) detonate at max
		# range instead of silently disappearing — the range limit should
		# feel like the shell ran out of fuel, not like it vanished.
		if blast_radius > 0.0 and not _hit:
			_hit = true
			_explode(global_position)
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
			# Pierce — pass through this enemy and keep flying. Reset _hit
			# so the next overlap fires body_entered again. AoE projectiles
			# don't pierce (they detonated).
			if pierce_count > 0:
				pierce_count -= 1
				_hit = false
				return
	elif blast_radius > 0.0 and not is_ghost:
		# AoE projectile (RPG, charged plasma) hit a non-target body — a
		# decorative pillar, a structure prop, or a non-damageable world
		# collider. The sweep raycast in _physics_process catches most
		# world hits first, but body_entered can fire on the same frame
		# (or earlier on the spawn frame if the muzzle clips geometry),
		# so we need this fallback. Without it, RPG rounds silently
		# passed through pillars without detonating. Ghosts (MP visual
		# echoes) suppress — the firing peer's _explode RPC replicates
		# the boom; doubling it would show two bursts.
		_explode(global_position)
	_release()


func _hit_single(body: Node3D, impact_pos: Vector3) -> void:
	# Bullets don't burst — they're kinetic rounds, not energy. Damage
	# numbers + the target's hit-flash are the feedback. Energy weapons
	# (laser pistol / plasma rifle / etc.) keep the bright impact flash
	# they've always had.
	if not is_bullet:
		CombatVisuals.spawn_impact_burst(self, impact_pos, _projectile_color())
	var is_crit := _roll_crit()
	var dmg := _roll_damage(is_crit)
	# Sniper "First Mark" — first sniper round to hit a target after
	# 5+ seconds of no sniper damage deals +50%. Per-target check via
	# consume_sniper_first_mark on the enemy. Multiplier applied AFTER
	# the standard damage roll so it stacks cleanly with crit.
	if weapon_base_id == &"sniper_2h" and target_group == &"enemies":
		var enemy := body as PrototypeEnemy
		if enemy != null:
			var first_mark_mult := enemy.consume_sniper_first_mark()
			if first_mark_mult != 1.0:
				first_mark_mult += float(headshot_bonus_pct) * 0.01
				dmg = int(round(float(dmg) * first_mark_mult))
	# Laser "Overcharge" — flat chance for any laser shot to deal 2× damage.
	if overcharge_chance_pct > 0 and randf() * 100.0 < float(overcharge_chance_pct):
		dmg *= 2
	if target_group == &"player":
		body.take_damage(dmg, source_position, knockback_strength)
	else:
		PrototypeEnemy.deal_damage(body, dmg, source_position, knockback_strength, 1, is_crit, weapon_base_id)
		_apply_exile_curse_if_active(body)
		_apply_mindlink(body, dmg, is_crit)
		_try_spawn_isr_drone(body)
		# SMG "Ricochet" — on hit, chance to spawn a secondary bullet at
		# the nearest other enemy. Ricochets don't chain further.
		if ricochet_chance_pct > 0 and randf() * 100.0 < float(ricochet_chance_pct):
			_try_ricochet(body)


const RICOCHET_SEARCH_RADIUS: float = 8.0
# Ricochet used to be 50% of the original hit — fine in theory, but on
# SMG base damage of 2-6 it rounded down to ~1 per ricochet, which read
# as a hit with no impact. Bumped to 80% so the bounce feels like a real
# secondary hit rather than a courtesy graze.
const RICOCHET_DAMAGE_MULT: float = 0.8
const RICOCHET_ARC_COLOR := Color(1.0, 0.75, 0.3, 1.0)  # warm yellow-orange
const RICOCHET_ARC_DURATION := 0.12  # short flash so it reads as a ricochet

func _try_ricochet(hit_body: Node3D) -> void:
	var origin := hit_body.global_position + Vector3(0.0, 0.9, 0.0)
	var best: Node3D = null
	var best_dist := RICOCHET_SEARCH_RADIUS + 1.0
	for enode: Node3D in SpatialGrid.query_radius(origin, RICOCHET_SEARCH_RADIUS, &"enemies"):
		if enode == hit_body or not enode.has_method(&"take_damage"):
			continue
		var d := origin.distance_to(enode.global_position)
		if d < best_dist:
			best_dist = d
			best = enode
	if best == null:
		return
	var target_pos := best.global_position + Vector3(0.0, 0.9, 0.0)
	# Visual: short arc from hit enemy to ricochet target + impact burst.
	CombatVisuals.spawn_lightning_arc(self, origin, target_pos, RICOCHET_ARC_DURATION, RICOCHET_ARC_COLOR)
	CombatVisuals.spawn_impact_burst(self, target_pos, RICOCHET_ARC_COLOR)
	# Deal damage directly — no secondary projectile needed for an instant
	# ricochet. This avoids pool churn and guarantees the hit lands.
	var is_crit := randf() < crit_chance
	var base_dmg := randi_range(damage_min, damage_max)
	var dmg := int(round(float(base_dmg) * RICOCHET_DAMAGE_MULT * damage_mult * (1.5 if is_crit else 1.0)))
	if dmg < 1:
		dmg = 1
	PrototypeEnemy.deal_damage(best, dmg, origin, 0.0, 1, is_crit, weapon_base_id)


func _explode(impact_pos: Vector3) -> void:
	# All AoE explosions use the flipbook fireball path — damage_type
	# picks the elemental palette (orange / cyan / violet) so both
	# kinetic (RPG) and energy (charged plasma) get the same VFX stack.
	CombatVisuals.spawn_explosion(self, impact_pos, blast_radius, Color(0.0, 0.0, 0.0, 0.0), damage_type)
	# Impact shake — distance-scaled jolt for the local camera. Fires
	# here (not at launch) so the boom hits when the shell lands. RPG
	# gets a heavy slam; plasma gets a lighter punch.
	if weapon_base_id == &"rpg_2h":
		PrototypeCamera.shake_at(self, impact_pos, 1.40, 0.65)
	elif blast_radius > 0.0:
		PrototypeCamera.shake_at(self, impact_pos, 0.70, 0.35)
	# Impact SFX — fires for any projectile that has an impact sound
	# registered. WeaponSounds.play_impact no-ops gracefully if nothing
	# is wired for this archetype, so the call is safe to make always.
	if weapon_base_id != &"":
		WeaponSounds.play_impact(weapon_base_id, impact_pos)
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
			# blast_radius > 0 means this is the AoE shockwave call —
			# flag is_explosion so the death code rolls the 25%
			# dismemberment chance on kills.
			PrototypeEnemy.deal_damage(target, dmg, source_position, knockback_strength, 1, is_crit, weapon_base_id, true)
			_apply_exile_curse_if_active(target)
			_apply_mindlink(target, dmg, is_crit)
			_try_spawn_isr_drone(target)
			# RPG "Concussive" — every enemy caught in an RPG blast is
			# briefly staggered (short stun). Reuses the stun status
			# already wired for hammer combo / overcharge electric, so
			# no new affliction plumbing is needed. 0.4s is enough for
			# a follow-up shot before the wave re-engages.
			if weapon_base_id == &"rpg_2h" and target.has_method(&"apply_stun"):
				target.apply_stun(0.4)
	# Ragdoll corpses caught in the blast tumble away from impact_pos.
	# Same falloff curve as the grenade's _detonate impulse so AoE shots
	# (charged plasma, future explosive projectiles) feel consistent with
	# thrown explosives.
	# Duck-type — see PrototypeGrenade._detonate. The X Bot skeletal-corpse
	# path uses PrototypeEnemy (not PrototypeRagdollCorpse) so the old cast
	# silently dropped them.
	for c in get_tree().get_nodes_in_group(&"ragdoll_corpses"):
		if c == null or not is_instance_valid(c) or not c.has_method(&"apply_explosion_impulse"):
			continue
		var corpse_pos: Vector3 = (c as Node3D).global_position
		var d := corpse_pos.distance_to(impact_pos)
		if d > blast_radius:
			continue
		var t := d / blast_radius
		var force: float = lerp(CORPSE_IMPULSE_MAX, CORPSE_IMPULSE_MIN, t)
		c.apply_explosion_impulse(impact_pos, force)


func _apply_exile_curse_if_active(enemy: Node) -> void:
	CombatEffects.apply_exile_curse_if_active(enemy)


func _apply_mindlink(primary: Node3D, dmg: int, is_crit: bool) -> void:
	CombatEffects.apply_mindlink(primary, dmg, is_crit, source_position,
		PrototypeEnemy.deal_damage, false)


func _try_spawn_isr_drone(enemy: Node3D) -> void:
	if target_group != &"enemies":
		return
	CombatEffects.try_spawn_isr_drone(enemy)


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
	# Shotgun Point Blank — pellets hitting within their bonus radius
	# get a flat damage multiplier on top of the base roll. Applied
	# pre-crit so a crit at point blank still scales correctly.
	if point_blank_bonus_distance > 0.0 and _traveled < point_blank_bonus_distance:
		dmg = int(round(float(dmg) * point_blank_bonus_mult))
	if is_crit:
		var mult := PROTO_BASE_CRIT_MULT + Effects.get_aggregate(&"crit_damage_pct")
		dmg = int(round(float(dmg) * mult))
	# Distance falloff — full damage within max_range, drops beyond.
	dmg = maxi(1, int(round(float(dmg) * PlayerCombat.range_falloff(_traveled, max_range))))
	return dmg
