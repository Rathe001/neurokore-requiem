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
# Projectile "barrel" offset — projectiles emerge from approximately
# where a held weapon's muzzle would be, not the character's chest
# center. FORWARD pushes the spawn out along aim (so the projectile
# clears the body); RIGHT shifts it to the typical right-handed grip
# position. Picked to read as "shot from a weapon" without the spawn
# pos clipping into walls when the player is close to one.
const BARREL_FORWARD_OFFSET: float = 0.7
const BARREL_RIGHT_OFFSET: float = 0.25

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

const EXILE_AUTO_SHOT_BASE_DAMAGE: int = 60
const EXILE_AUTO_SHOT_KNOCKBACK: float = 4.0

# Overclock — Survivalist talent. When the roll succeeds, the attack deals
# +25% damage but loses 25% range. Visuals scale up 25% to sell the hit.
const OVERCLOCK_DAMAGE_MULT: float = 1.25
const OVERCLOCK_RANGE_MULT: float = 0.75
const OVERCLOCK_VISUAL_SCALE: float = 1.25

# Damage falloff beyond effective range. Applies only to hitscan and
# projectile resolution — the bullet/beam keeps travelling past the
# weapon's stated range but does progressively less damage. Cone and
# AoE attacks ignore this multiplier entirely: their hit region matches
# the visual cone / shockwave, so a melee swing or ground-slam never
# reaches past what the player sees.
const FALLOFF_RANGE_MULT: float = 1.25
const FALLOFF_MAX_REDUCTION: float = 0.75

# Quadratic falloff: 100% within eff_range, drops to 25% at the
# extended-range edge (eff_range × FALLOFF_RANGE_MULT). The denominator
# is the *extension* distance — using eff_range alone made the curve's
# floor unreachable whenever FALLOFF_RANGE_MULT was anything other than 2.
static func range_falloff(distance: float, eff_range: float) -> float:
	if distance <= eff_range or eff_range <= 0.0:
		return 1.0
	var extension := eff_range * (FALLOFF_RANGE_MULT - 1.0)
	if extension <= 0.0:
		return 1.0
	var t := clampf((distance - eff_range) / extension, 0.0, 1.0)
	return 1.0 - FALLOFF_MAX_REDUCTION * t * t


var _host: PrototypePlayer
var _cooldowns: Dictionary = {}
# Resolved aim direction from the most recent hitscan / projectile fire.
# Used by Double Tap to copy the exact same trajectory for the follow-up.
var _last_resolved_aim: Vector3 = Vector3.FORWARD
# Per-attack overclock state — set at the top of resolve_skill_hit, read
# by damage rolling and visual spawn functions during that same call.
var _overclock_active: bool = false
# Per-equipment-slot cooldowns for the multi-weapon LMB path. Two identical
# weapons in different slots (Forged Amalgamation) have independent timers
# because the key is the slot StringName, not the Skill resource. Non-LMB
# skills still use _cooldowns (keyed by Skill).
var _slot_cooldowns: Dictionary = {}

func setup(host: PrototypePlayer) -> void:
	_host = host


# Schedule a shell casing ejection from the equipped weapon's mounted
# model. WeaponAttachment applies the per-weapon delay (shotgun=0.5s
# for pump action, rifles / SMG = instant). No-op for weapons that
# don't eject (energy guns, melee, RPG).
func _eject_casing(weapon: Item) -> void:
	if weapon == null or _host == null or _host.visual == null:
		return
	var skel := PrototypePlayer._find_skeleton_recursive(_host.visual)
	if skel == null:
		return
	WeaponAttachment.eject_casing(skel, weapon.weapon_base_id)


# World-space VISUAL muzzle position. Returns the actual barrel tip of
# the equipped weapon's visible glb (via the X Bot right-hand bone's
# BoneAttachment3D + per-weapon muzzle override), or the legacy "chest
# + BARREL_FORWARD/RIGHT_OFFSET" approximation when bare-handed / when
# an extra Amalgamation arm is firing (extras don't carry weapon models).
#
# Used for muzzle flashes + shell-casing ejection — anything that wants
# to anchor visually to the gun's barrel. NOT used directly for
# projectile spawn — that goes through _safe_projectile_spawn_position
# below, which clamps back to the chest when the visual muzzle has
# poked through a wall or past a close target.
func _muzzle_world_position(aim: Vector3, source_offset: Vector3 = Vector3.ZERO) -> Vector3:
	var aim_norm := aim.normalized() if aim.length_squared() > 0.0001 else Vector3.FORWARD
	if source_offset != Vector3.ZERO:
		var aim_right_ex := Vector3.UP.cross(aim_norm).normalized()
		var barrel_ex := aim_norm * BARREL_FORWARD_OFFSET + aim_right_ex * BARREL_RIGHT_OFFSET
		return _host.global_position + Vector3(0.0, 1.0, 0.0) + barrel_ex + source_offset
	if _host != null and _host.visual != null:
		var skel := PrototypePlayer._find_skeleton_recursive(_host.visual)
		if skel != null:
			var muzzle := WeaponAttachment.get_muzzle_position(skel, aim_norm)
			if muzzle != Vector3.ZERO:
				return muzzle
	# Fallback: bare hands or weapon model not yet mounted.
	var aim_right_fb := Vector3.UP.cross(aim_norm).normalized()
	var barrel_fb := aim_norm * BARREL_FORWARD_OFFSET + aim_right_fb * BARREL_RIGHT_OFFSET
	return _host.global_position + Vector3(0.0, 1.0, 0.0) + barrel_fb


# Projectile / hitscan spawn point. Starts at the visual muzzle, then
# safety-checks the chest→muzzle segment for occluders. If anything is
# in the way (wall, pillar, enemy body), spawns at the chest instead.
#
# Solves two related symptoms that both come from the gun barrel
# extending past the player's collision capsule:
#
#   1. Standing flush against a wall: the visual muzzle pokes through
#      the wall, projectile spawns INSIDE the wall, sweep-raycast on
#      tick 1 immediately hits the wall from the wrong side, projectile
#      released without ever traveling. Symptom: "I'm clicking and
#      nothing happens" against walls.
#
#   2. Enemy closer than the muzzle's forward offset (a sniper-class
#      muzzle is ~0.6m forward; an enemy at melee range is ~0.5m away):
#      muzzle is PAST the enemy when the projectile spawns, projectile
#      travels FORWARD from past-them, never collides. Symptom: "point-
#      blank shots whiff."
#
# Chest is the player's collision-capsule center — projectile spawned
# there is guaranteed to be inside the player's own body, so when it
# starts moving on tick 1 it sweeps through whatever's between player
# and target on its way out.
func _safe_projectile_spawn_position(aim: Vector3, source_offset: Vector3 = Vector3.ZERO) -> Vector3:
	var muzzle := _muzzle_world_position(aim, source_offset)
	if _host == null:
		return muzzle
	# Physics state is only readable inside the physics frame. Calling
	# intersect_ray from the LMB wind-up timer (which fires from a
	# SceneTreeTimer that doesn't sync to physics) logs `Space state is
	# inaccessible right now` per shot. Bail to the raw muzzle when we
	# can't safely raycast; the projectile loses its safety clamp but
	# the alternative (per-shot stderr spam that tanks proc) is worse.
	# Same guard pattern proximity_lighting uses.
	if not Engine.is_in_physics_frame():
		return muzzle
	var world := _host.get_world_3d()
	if world == null:
		return muzzle
	var space := world.direct_space_state
	if space == null:
		return muzzle
	var chest: Vector3 = _host.global_position + Vector3(0.0, 1.0, 0.0)
	# If muzzle ≈ chest (bare hands, very short barrel) skip the check —
	# nothing to clamp to.
	if chest.distance_squared_to(muzzle) < 0.04:  # < 0.2m
		return muzzle
	var query := PhysicsRayQueryParameters3D.create(chest, muzzle)
	# Walls + pillars + enemies. The world mask catches the wall-clip
	# case; ENEMY_LAYER_MASK catches the point-blank case (target body
	# inside the muzzle reach). Player's own capsule is excluded so the
	# ray doesn't self-hit on the way out from chest.
	query.collision_mask = PrototypeProjectile.PROJECTILE_WORLD_MASK | PrototypeProjectile.ENEMY_LAYER_MASK
	if _host is CollisionObject3D:
		query.exclude = [(_host as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return chest
	return muzzle

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
	# Kinetic-weapon recoil shake. Fires once per fire press (multistrike /
	# shotgun spreads / double-tap follow-ups don't restack). Energy weapons
	# (laser pistol, plasma rifle, accelerator) and melee skip — the hammer
	# finisher has its own dedicated shake further down. RPG launches a
	# heavy explosive shell and gets a much bigger jolt than the small-arms.
	_apply_kinetic_recoil_shake(weapon)
	# Energy-weapon push. Distinct visual from kinetic recoil — instead of
	# random jitter the camera drifts away from aim direction, simulating
	# the beam's pressure pushing the wielder back. Channel beams (Energy
	# Accelerator) tick-call this repeatedly so the push accumulates while
	# the player holds fire, springs back when they release.
	_apply_energy_push(weapon, aim)
	var hits := PerkState.roll_multistrike()
	# Fire SFX is NOT triggered here — it moved to fire-press time
	# (PrototypePlayer's main fire path + multi-arm timer callback) so
	# weapons with wind-up audio (RPG) have their sound start at LMB
	# press, not at projectile-spawn. The launch-impact moment of the
	# baked-in sound lines up with the actual projectile spawn that
	# way. Channel weapons handle their own SFX via play_channel_*.
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			# CHANNEL_BEAM cones (Energy Accelerator stream) draw a
			# persistent flame visual via the player's flame node — the
			# per-tick shockwave-bubble cone would double up and read as
			# a melee swing. Skip the cone visual for those; damage
			# resolution still runs.
			var skip_cone_visual := skill.active_kind == Skill.ActiveKind.CHANNEL_BEAM
			# Advance the melee combo at the top of the cast for melee
			# weapons. Multistrike repeats below all share the resulting
			# step (read via _host.melee_combo_step in _resolve_cone), so
			# damage / cone width / status all stay consistent across
			# the multistrike loop within a single click. Non-melee
			# SINGLE_CONE casts (Accelerator stream, etc.) advance the
			# helper too — it returns 0 and is harmless because the
			# weapon isn't in MELEE_BASE_IDS.
			_host.advance_melee_combo(weapon)
			var combo_step := _host.melee_combo_step()
			var visual_cone_deg := _melee_cone_deg_for_step(skill, combo_step)
			# Per-archetype melee visual:
			#   • 1H knife → spawn_blade_slash (thin streak, reads as "cut")
			#   • 2H hammer → spawn_hit_cone (shockwave dome) + radial on
			#     the step-2 finisher ("ground slam")
			#   • non-melee SINGLE_CONE (Accelerator stream skipped above
			#     via skip_cone_visual) → no visual here
			var is_knife: bool = weapon != null and weapon.weapon_base_id == &"melee_1h"
			var is_hammer: bool = weapon != null and weapon.weapon_base_id == &"melee_2h"
			var is_hammer_finisher: bool = is_hammer and combo_step == 2
			if not skip_cone_visual:
				if is_knife:
					CombatVisuals.spawn_blade_slash(_host, aim, eff_range, visual_cone_deg)
				elif is_hammer:
					# 2H hammer LMB.
					#
					# Steps 0 / 1 (build-up swings) → small front-impact
					# crater ahead of the player. Crater radius scales
					# with eff_range so the visible damage zone tracks
					# the actual cone reach instead of staying frozen at
					# 1.2m. Position stays at 65% along the cone axis.
					#
					# Step 2 (finisher / "ground slam") → big AoE-radial
					# crater centred on the player, sized to the full
					# eff_range. Reads as a ground slam landing under
					# the swinger, mirroring the RMB AoE pattern. The
					# shockwave-ring impact is intentionally NOT
					# spawned here — it overlaid the crater with a
					# second orange ring that read as a duplicate VFX.
					# The crater's own sculpted bump is the visual.
					if is_hammer_finisher:
						PrototypeAttackIndicator.spawn_hammer_crater(_host, _host.global_position, eff_range)
					else:
						var aim_flat := Vector3(aim.x, 0.0, aim.z)
						if aim_flat.length_squared() > 0.0001:
							aim_flat = aim_flat.normalized()
						else:
							aim_flat = -_host.global_transform.basis.z
						var impact_pos: Vector3 = _host.global_position + aim_flat * eff_range * 0.65
						PrototypeAttackIndicator.spawn_hammer_crater(_host, impact_pos, eff_range * 0.5)
				else:
					CombatVisuals.spawn_hit_cone(_host, aim, eff_range, visual_cone_deg)
			# Per-archetype melee combo shake — escalates with each step
			# of the 3-hit chain. 2H hits harder than 1H at every step,
			# step 2 is a finisher punch (1H bleed flick / 2H ground
			# slam). The shake() envelope's "stronger wins" overlap means
			# rapid combo swings build cleanly without cutting each
			# other short.
			_apply_melee_combo_shake(weapon, combo_step)
			_resolve_cone(skill, aim, eff_range, weapon)
			# Resolve self through instance_from_id at fire time — see the
			# fire timer in PrototypePlayer for the lambda-capture
			# rationale. PlayerCombat is a Node (player child) so the
			# implicit self capture would be invalidated by a level
			# reload during the multistrike stagger.
			var self_id := get_instance_id()
			for extra in hits - 1:
				var delay := MULTISTRIKE_STAGGER * float(extra + 1)
				_host.get_tree().create_timer(delay).timeout.connect(func() -> void:
					var c := instance_from_id(self_id) as PlayerCombat
					if c == null or c._host == null or not c._host._alive:
						return
					if not skip_cone_visual:
						if is_knife:
							CombatVisuals.spawn_blade_slash(c._host, aim, eff_range, visual_cone_deg)
						elif is_hammer:
							PrototypeAttackIndicator.spawn_hammer_dust_cone(c._host, aim, eff_range, visual_cone_deg)
						else:
							CombatVisuals.spawn_hit_cone(c._host, aim, eff_range, visual_cone_deg)
					c._resolve_cone(skill, aim, eff_range, weapon)
				, CONNECT_ONE_SHOT)
		Skill.TargetingMode.AOE_RADIAL:
			# 2H hammer RMB (AoE Burst) — large crater at the player's
			# feet, radius matched to the skill's eff_range. Other
			# weapons that fire AoE skills (currently rare; mostly
			# energy effects via channel paths) keep the shockwave.
			var aoe_is_hammer: bool = weapon != null and weapon.weapon_base_id == &"melee_2h"
			if aoe_is_hammer:
				PrototypeAttackIndicator.spawn_hammer_crater(_host, _host.global_position, eff_range)
			else:
				CombatVisuals.spawn_hit_radial(_host, eff_range)
			_resolve_aoe(skill, eff_range, weapon)
			var self_id := get_instance_id()
			for extra in hits - 1:
				var delay := MULTISTRIKE_STAGGER * float(extra + 1)
				_host.get_tree().create_timer(delay).timeout.connect(func() -> void:
					var c := instance_from_id(self_id) as PlayerCombat
					if c == null or c._host == null or not c._host._alive:
						return
					if aoe_is_hammer:
						PrototypeAttackIndicator.spawn_hammer_crater(c._host, c._host.global_position, eff_range)
					else:
						CombatVisuals.spawn_hit_radial(c._host, eff_range)
					c._resolve_aoe(skill, eff_range, weapon)
				, CONNECT_ONE_SHOT)
		Skill.TargetingMode.PROJECTILE:
			for i in hits:
				_spawn_projectile(skill, aim, eff_range, weapon, source_offset)
			_try_double_tap(skill, aim, eff_range, weapon, source_offset)
		Skill.TargetingMode.HITSCAN:
			for i in hits:
				_resolve_hitscan(skill, aim, eff_range, weapon, source_offset)
			_try_double_tap(skill, aim, eff_range, weapon, source_offset)
		Skill.TargetingMode.SHOTGUN_SPREAD:
			for i in hits:
				_resolve_shotgun(skill, aim, eff_range, weapon, source_offset)
		Skill.TargetingMode.CHAIN_LIGHTNING:
			for i in hits:
				_resolve_chain_lightning(skill, aim, eff_range, weapon, source_offset)
	_overclock_active = false


# ---------------------------------------------------------------------------
# Kinetic recoil — local camera shake on bullet-weapon fire, tuned per
# archetype. Per-camera so MP-safe (every player's iso shakes only on
# their own shots). RPG is intentionally NOT here — its big shake fires
# at impact time, not on launch, since the shell's boom comes when it
# lands. Grenades are the same story: the shake happens in _detonate.
# Energy and melee weapons skip entirely (the hammer finisher carries
# its own dedicated shake further down the SINGLE_CONE branch).
# ---------------------------------------------------------------------------

# (intensity, duration) per kinetic archetype. Tuned against the
# hammer-finisher reference (0.10, 0.25) — SMG sits well below that
# so rapid-fire bursts don't dominate; sniper/shotgun sit clearly
# above so the single big shot feels meaningful.
const RECOIL_SHAKE_BY_BASE_ID: Dictionary = {
	# Durations are deliberately long relative to each weapon's fire
	# cadence so the camera's hold-phase keeps refreshing during a
	# burst — without enough headroom, decay kicks in between shots
	# and the shake pulses visibly. SMG fires ~8/sec; 0.40s window
	# means each shot lands well inside the next shot's hold.
	&"smg_1h":     Vector2(0.14, 0.40),   # tiny — sustained across full-auto
	&"lmg_2h":     Vector2(0.30, 0.40),   # larger — sustained chatter
	&"sniper_2h":  Vector2(0.65, 0.50),   # large — heavy bolt-action recoil
	&"shotgun_2h": Vector2(0.60, 0.45),   # large — pump-action kick
	# rpg_2h: deliberately absent — impact shake (in prototype_projectile
	# ._explode) handles it instead. Adding fire-time recoil here would
	# stack with the impact shake and feel like double-firing.
}


func _apply_kinetic_recoil_shake(weapon: Item) -> void:
	if weapon == null:
		return
	if not RECOIL_SHAKE_BY_BASE_ID.has(weapon.weapon_base_id):
		return
	var cam := _host.get_viewport().get_camera_3d() as PrototypeCamera
	if cam == null:
		return
	var params: Vector2 = RECOIL_SHAKE_BY_BASE_ID[weapon.weapon_base_id]
	cam.shake(params.x, params.y)


# Energy-weapon impulse table — per-archetype velocity kick fed to
# PrototypeCamera.push_at. Tuned for the firing cadence of each:
# accelerator is small per-tick because it channel-fires continuously
# and the spring would otherwise drift to the clamp ceiling; plasma
# rifle is heavy per-shot since each bolt is a discrete release;
# laser pistol and taser sit in between.
const ENERGY_PUSH_BY_BASE_ID: Dictionary = {
	&"ranged_1h":      1.4,   # laser pistol — fast cadence, light pressure
	&"ranged_2h":      3.0,   # plasma rifle — slow heavy bolts
	&"accelerator_2h": 1.6,   # accelerator stream — tick-fires, push accumulates fast
	&"taser_2h":       4.0,   # taser — single zap, strong kick
}


func _apply_energy_push(weapon: Item, aim: Vector3) -> void:
	if weapon == null:
		return
	if not ENERGY_PUSH_BY_BASE_ID.has(weapon.weapon_base_id):
		return
	var impulse: float = ENERGY_PUSH_BY_BASE_ID[weapon.weapon_base_id]
	PrototypeCamera.push_at(_host, aim, impulse)


# Melee combo shake — per-step intensity/duration for 1H knife and 2H
# hammer. Each combo step ramps the shake; 2H hits noticeably harder
# than 1H at every step (heavier weapon, slower swing). Step 2 is the
# finisher (knife bleed flick / hammer ground slam) and carries the
# heaviest jolt. The shake envelope's stronger-wins overlap means
# back-to-back combo hits build cleanly instead of cutting each other.
const MELEE_SHAKE_BY_STEP_1H: Array[Vector2] = [
	Vector2(0.10, 0.22),  # step 0 — light flick
	Vector2(0.22, 0.28),  # step 1 — bigger swing
	Vector2(0.45, 0.38),  # step 2 — bleed-finisher punch
]
const MELEE_SHAKE_BY_STEP_2H: Array[Vector2] = [
	Vector2(0.28, 0.28),  # step 0 — heavy swing baseline
	Vector2(0.55, 0.38),  # step 1 — wider hammer arc
	Vector2(0.95, 0.55),  # step 2 — ground slam finisher
]


func _apply_melee_combo_shake(weapon: Item, step: int) -> void:
	if weapon == null:
		return
	var table: Array
	if weapon.weapon_base_id == &"melee_1h":
		table = MELEE_SHAKE_BY_STEP_1H
	elif weapon.weapon_base_id == &"melee_2h":
		table = MELEE_SHAKE_BY_STEP_2H
	else:
		return
	var idx: int = clampi(step, 0, table.size() - 1)
	var params: Vector2 = table[idx]
	var cam := _host.get_viewport().get_camera_3d() as PrototypeCamera
	if cam == null:
		return
	cam.shake(params.x, params.y)


# ---------------------------------------------------------------------------
# Double Tap — Count talent: chance to fire a consecutive follow-up shot
# with the same aim as the primary. Only projectile / hitscan; melee
# patterns (cone, AoE) don't double-tap.
# ---------------------------------------------------------------------------

## Delay before the follow-up shot fires — short enough to read as a rapid
## double-shot, long enough that both beams / bolts are visually distinct.
const DOUBLE_TAP_DELAY: float = 0.10

func _try_double_tap(skill: Skill, _aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3) -> void:
	var chance := Effects.get_aggregate(&"double_tap_chance")
	if chance <= 0.0 or randf() >= chance:
		return
	var tap_aim := _last_resolved_aim
	var self_id := get_instance_id()
	_host.get_tree().create_timer(DOUBLE_TAP_DELAY).timeout.connect(func() -> void:
		var c := instance_from_id(self_id) as PlayerCombat
		if c == null or c._host == null or not c._host._alive:
			return
		match skill.targeting_mode:
			Skill.TargetingMode.PROJECTILE:
				c._spawn_projectile_exact(skill, tap_aim, eff_range, weapon, source_offset)
			Skill.TargetingMode.HITSCAN:
				c._resolve_hitscan_exact(skill, tap_aim, eff_range, weapon, source_offset)
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
##
## Behavior-mod damage multipliers (Pain Compiler buff, Reflex Loader empty
## penalty) are applied here so every player attack path inherits them
## without per-call-site patching. amount must be > 0 to scale; zero-damage
## knockback pulses (Shock Discharge, etc.) are passed through untouched.
func _deal_damage(target: Node3D, amount: int, knockback_from: Vector3, knockback_strength: float, multistrike: int, is_crit: bool, weapon_base_id: StringName = &"") -> void:
	if amount > 0 and _host != null:
		var mod_mult := _host.behavior_mod_damage_mult()
		if mod_mult != 1.0:
			amount = maxi(1, int(round(float(amount) * mod_mult)))
	PrototypeEnemy.deal_damage(target, amount, knockback_from, knockback_strength, multistrike, is_crit, weapon_base_id)


## Combo step → cone-width override. Step 0 uses the authored cone_deg,
## step 1 widens to ~1.5×, step 2 sweeps almost full circle so the
## finisher reads as "spin-strike all directions" without going to a
## separate AOE_RADIAL targeting mode.
func _melee_cone_deg_for_step(skill: Skill, step: int) -> float:
	if not _is_melee_weapon_step(step):
		return skill.cone_deg
	match step:
		1: return minf(180.0, skill.cone_deg * 1.5)
		2: return 350.0
	return skill.cone_deg


# Damage / knockback multipliers applied per combo step. Step 0 is the
# baseline (1.0 / 1.0); each subsequent step ramps the swing harder.
const MELEE_COMBO_DAMAGE_MULTS: Array[float] = [1.0, 1.25, 1.6]
const MELEE_COMBO_KNOCKBACK_MULTS: Array[float] = [1.0, 1.5, 2.5]


# Returns true when the player is actively in a melee combo — i.e. the
# combo step is meaningful for the current cast. Used to gate the
# step-based modulation so non-melee SINGLE_CONE casts (Accelerator
# stream) don't read step 0 and start applying combo math to themselves.
func _is_melee_weapon_step(_step: int) -> bool:
	var weapon: Item = _host._attack_weapon
	if weapon == null:
		weapon = InventoryState.get_equipped(&"weapon")
	if weapon == null:
		return false
	return weapon.weapon_base_id in PrototypePlayer.MELEE_BASE_IDS


func _resolve_cone(skill: Skill, aim: Vector3, eff_range: float, weapon: Item) -> void:
	var combo_step: int = _host.melee_combo_step()
	var is_melee := _is_melee_weapon_step(combo_step)
	# Combo widens the cone on hits 2/3 (step 1/2). Damage and knockback
	# scale up too — a step-2 hammer swing hits 1.6× damage with 2.5×
	# knockback, which sells the "wind-up finisher" feel.
	var cone_deg: float = _melee_cone_deg_for_step(skill, combo_step) if is_melee else skill.cone_deg
	var dmg_mult: float = MELEE_COMBO_DAMAGE_MULTS[combo_step] if is_melee else 1.0
	var kb_mult: float = MELEE_COMBO_KNOCKBACK_MULTS[combo_step] if is_melee else 1.0
	# Hammer "Wind-Up" — first hammer hit after 1s of standing still
	# deals +75%. Drains the bonus on hit (one-shot, not per-target),
	# so a wind-up finisher hits ONE enemy harder, not the whole cone.
	# Reset by movement (handled in _physics_process via the player's
	# stillness timer).
	var wind_up_active: bool = (
		is_melee
		and weapon != null
		and weapon.weapon_base_id == &"melee_2h"
		and _host.consume_hammer_wind_up()
	)
	if wind_up_active:
		dmg_mult *= 1.75
	# Accelerator "Resonance" — time-based damage ramp while the stream
	# is sustained. Multiplier lerps from 1.0× to ACCEL_RAMP_MAX_MULT
	# over ACCEL_RAMP_DURATION seconds (advanced per-frame from
	# _tick_channel). Reset on channel stop in _stop_channel.
	if weapon != null and weapon.weapon_base_id == &"accelerator_2h" and skill.active_kind == Skill.ActiveKind.CHANNEL_BEAM:
		dmg_mult *= _host.accel_resonance_mult()
	var half_cos := cos(deg_to_rad(cone_deg * 0.5))
	var kb: float = _knockback_for(skill, weapon) * kb_mult
	var apply_status: bool = skill.overcharge_status != &""
	# Step-2 finisher applies a per-archetype status:
	#   melee_1h → bleed (stacking %HP DoT)
	#   melee_2h → stun (CC)
	# Status durations baked here rather than on the skill since they're
	# combo-driven, not authored-per-skill.
	var apply_combo_status := is_melee and combo_step == 2
	var any_hit := false
	for enode: Node3D in SpatialGrid.query_cone(_host.global_position, aim, eff_range, half_cos, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		if is_player_friendly(enode):
			continue
		var is_crit := _roll_crit(weapon)
		var raw_dmg := _roll_skill_damage(skill, weapon)
		if dmg_mult != 1.0:
			raw_dmg = int(round(float(raw_dmg) * dmg_mult))
		var dist_to_target := _host.global_position.distance_to(enode.global_position)
		raw_dmg = maxi(1, int(round(float(raw_dmg) * range_falloff(dist_to_target, eff_range))))
		# Knife "Backstab" — 1H melee hits from behind the enemy deal
		# +50%. Compares the player→enemy direction to the enemy's
		# facing: a high positive dot means the enemy is facing AWAY
		# from where the hit came in (player is behind them).
		if is_melee and weapon != null and weapon.weapon_base_id == &"melee_1h":
			var enemy_facing: Vector3 = -enode.global_transform.basis.z
			var hit_dir: Vector3 = enode.global_position - _host.global_position
			hit_dir.y = 0.0
			enemy_facing.y = 0.0
			if hit_dir.length_squared() > 0.0001 and enemy_facing.length_squared() > 0.0001:
				var alignment: float = hit_dir.normalized().dot(enemy_facing.normalized())
				if alignment > 0.5:  # ~60° cone behind the enemy
					raw_dmg = int(round(float(raw_dmg) * 1.5))
		var dmg := _crit_damage(raw_dmg, is_crit)
		var wbid: StringName = weapon.weapon_base_id if weapon != null else &""
		_deal_damage(enode, dmg, _host.global_position, kb, 1, is_crit, wbid)
		_apply_exile_curse_if_active(enode)
		_apply_mindlink(enode, dmg, is_crit)
		_try_spawn_isr_drone(enode)
		# Energy Accelerator Overcharge — applies ignite / freeze / stun
		# to every enemy in the cone based on the weapon's rolled
		# damage_type. Skipped when overcharge_status is empty (every
		# non-Overcharge cone skill).
		if apply_status:
			_apply_overcharge_status(enode, skill, weapon)
		if apply_combo_status:
			_apply_melee_combo_status(enode, weapon)
		any_hit = true
	# Unarmed glove modifiers — stun chance and AoE splash on hit.
	if any_hit and weapon == null and skill == PrototypePlayer.UNARMED_SKILL:
		_apply_unarmed_glove_effects(skill, eff_range)
	# Hitstop on connect — only fires if at least one enemy actually
	# took damage. Sells the "weight" of the swing without freezing the
	# player on whiffs.
	var is_unarmed := weapon == null and skill == PrototypePlayer.UNARMED_SKILL
	if any_hit and (is_melee or is_unarmed):
		_host.trigger_melee_hitstop()


# Per-archetype 3rd-hit status:
#   • melee_1h (knives) → bleed: 1 stack per crit-or-not, 6s duration.
#     Stacks across successive 3rd-hit finishers chained on the same
#     target — pressure builds the longer the player stays engaged.
#   • melee_2h (hammers) → stun: brief 0.6s, no stacking semantics.
#     Long enough for one or two follow-up swings before the target
#     re-aggros, short enough that horde fights don't lock targets out.
const MELEE_COMBO_BLEED_DURATION: float = 6.0
const MELEE_COMBO_STUN_DURATION: float = 0.6


const UNARMED_STUN_DURATION: float = 0.4

func _apply_unarmed_glove_effects(skill: Skill, eff_range: float) -> void:
	# AoE splash — if gloves grant unarmed_aoe_radius, deal skill.damage
	# in a radius around the player (supplemental to the cone hits).
	var aoe_radius: float = _host.get_unarmed_aoe_radius()
	if aoe_radius > 0.0:
		_resolve_aoe(skill, aoe_radius, null)
	# Stun chance — each enemy in the cone can be stunned independently.
	var stun_chance: float = _host.get_unarmed_stun_chance()
	if stun_chance > 0.0:
		for enode: Node3D in SpatialGrid.query_radius(_host.global_position, eff_range, &"enemies"):
			if not enode.has_method(&"apply_stun"):
				continue
			if is_player_friendly(enode):
				continue
			if randf() < stun_chance:
				enode.apply_stun(UNARMED_STUN_DURATION)


func _apply_melee_combo_status(enemy: Node, weapon: Item) -> void:
	if weapon == null:
		return
	if weapon.weapon_base_id == &"melee_1h" and enemy.has_method(&"apply_bleed"):
		var bleed_dps: int = maxi(1, weapon.get_effective_modifier(&"bleed_damage"))
		enemy.apply_bleed(MELEE_COMBO_BLEED_DURATION, bleed_dps)
	elif weapon.weapon_base_id == &"melee_2h" and enemy.has_method(&"apply_stun"):
		enemy.apply_stun(MELEE_COMBO_STUN_DURATION)

func _resolve_aoe(skill: Skill, eff_range: float, weapon: Item) -> void:
	var aoe_range := eff_range
	if weapon != null:
		aoe_range += float(weapon.get_modifier(&"impact_radius"))
	var kb := _knockback_for(skill, weapon)
	for enode: Node3D in SpatialGrid.query_radius(_host.global_position, aoe_range, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		if is_player_friendly(enode):
			continue
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		var dist_to_target := _host.global_position.distance_to(enode.global_position)
		dmg = maxi(1, int(round(float(dmg) * range_falloff(dist_to_target, aoe_range))))
		var wbid: StringName = weapon.weapon_base_id if weapon != null else &""
		_deal_damage(enode, dmg, _host.global_position, kb, 1, is_crit, wbid)
		_apply_exile_curse_if_active(enode)
		_apply_mindlink(enode, dmg, is_crit)
		_try_spawn_isr_drone(enode)


func is_player_friendly(target: Node) -> bool:
	return CombatEffects.is_player_friendly(target)

## Random spread (radians) applied to extra-arm projectiles so they
## converge toward the main-hand target without looking perfectly identical.
const EXTRA_ARM_SPREAD_RAD := 0.04

func _spawn_projectile(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	# Airstrike skills paint an X at the cursor and rain the projectile
	# straight down — a different spawn flow that reuses everything below
	# from `proj.knockback_strength` onward. Routed here (rather than as
	# a new TargetingMode) so source_offset / extras / multistrike all
	# still apply: each "hit" of the cast plants its own X.
	if skill.is_airstrike:
		_spawn_airstrike(skill, eff_range, weapon)
		return
	var proj: PrototypeProjectile = EntityPool.acquire(PROJECTILE_SCENE)
	if proj == null:
		return
	var aim_norm := aim.normalized()
	# Extra arms spawn offset from the player. To hit the same target as
	# the main hand, re-aim from the offset spawn position toward the
	# main-hand's target point (player + aim * range). Adds slight random
	# spread so the volley looks organic, not robotic.
	# Spawn at the visual muzzle when safe; clamp back to chest when the
	# muzzle is past a wall or a close target (see comment on
	# _safe_projectile_spawn_position). Muzzle flash below still uses the
	# visual muzzle so the flash visibly pops at the gun barrel even when
	# the projectile is spawning from chest center.
	var visual_muzzle := _muzzle_world_position(aim_norm, source_offset)
	var spawn_pos := _safe_projectile_spawn_position(aim_norm, source_offset)
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
	proj.damage_mult = skill.damage_multiplier * _archetype_quirk_damage_mult(weapon)
	if _overclock_active:
		proj.damage_mult *= OVERCLOCK_DAMAGE_MULT
	proj.blast_radius = skill.blast_radius
	if weapon != null:
		proj.blast_radius += weapon.get_modifier(&"blast_radius_bonus")
	var vis := skill.damage_multiplier if skill.damage_multiplier > 1.0 else 1.0
	if _overclock_active:
		vis *= OVERCLOCK_VISUAL_SCALE
	proj.visual_scale = vis
	# Bullet weapons (LMG/SMG/sniper/RPG) flag the projectile so it
	# renders as a tracer streak instead of an energy bolt.
	proj.is_bullet = weapon != null and weapon.is_bullet_weapon()
	proj.weapon_base_id = weapon.weapon_base_id if weapon != null else &""
	proj.damage_type = weapon.effective_damage_type() if weapon != null else &""
	if weapon != null:
		proj.headshot_bonus_pct = weapon.get_effective_modifier(&"headshot_bonus")
		proj.ricochet_chance_pct = weapon.get_effective_modifier(&"ricochet_chance")
		proj.overcharge_chance_pct = weapon.get_effective_modifier(&"overcharge_chance")
	# Plasma "Pierce" — plasma rifle bolts pass through 1 enemy before
	# stopping. Set on the projectile so the hit handler decrements
	# pierce_count and continues flight instead of releasing.
	proj.pierce_count = _archetype_pierce_count(weapon)
	_host.get_parent().add_child(proj)
	proj.global_position = spawn_pos
	proj.monitoring = true
	proj.reset()
	# Muzzle flash — anchored at the VISUAL muzzle so it pops at the gun
	# barrel even when the projectile is spawning from chest center
	# (wall-clamp / point-blank-clamp case in _safe_projectile_spawn_position).
	var _is_bullet := weapon != null and weapon.is_bullet_weapon()
	var _tint := _weapon_tint(weapon)
	CombatVisuals.spawn_muzzle_flash(_host, visual_muzzle, _is_bullet, _tint)
	_eject_casing(weapon)
	# MP: replicate the projectile spawn so other peers see it travel.
	# Damage stays host-authoritative; remote echoes are ghost projectiles.
	CombatVisuals.broadcast_projectile(spawn_pos, aim_norm, proj.speed, proj.max_range,
		proj.blast_radius, proj.visual_scale, proj.is_bullet, proj.damage_type, proj.target_group)


# Pierce count by weapon archetype. Currently only the plasma rifle
# (ranged_2h) pierces; everything else stops on first enemy. Returns
# 0 for non-piercing weapons so the projectile resets cleanly between
# pool reuses.
func _archetype_pierce_count(weapon: Item) -> int:
	if weapon == null:
		return 0
	if weapon.weapon_base_id == &"ranged_2h":
		return maxi(1, weapon.get_modifier(&"penetration"))
	return 0


# Per-archetype damage multiplier evaluated at projectile spawn time.
# Each branch consumes the relevant tracker on the player so the
# stack/timer state advances even if the shot misses (which keeps the
# decay timing correct). Multipliers compose with skill.damage_multiplier
# and overclock; the projectile's own roll then rolls flat damage_min/max.
#
#   • LMG_2h  → Heat: +10% per stack of sustained fire (max +50%)
#   • SMG_1h  → Penetration: every 5th shot is 2.0×
#   • Ranged_1h (laser) → Charged Shot: 1.5× after >=1s idle
#
# Sniper First Mark is per-target (consumed in projectile _hit_single
# against the enemy), not per-shot, so it's not in this helper.
func _archetype_quirk_damage_mult(weapon: Item) -> float:
	if weapon == null:
		return 1.0
	match weapon.weapon_base_id:
		&"lmg_2h":
			return _host.consume_lmg_heat()
		&"smg_1h":
			return _host.consume_smg_penetration()
		&"ranged_1h":
			return _host.consume_laser_charged_shot()
	return 1.0


# Extra travel budget beyond skill.airstrike_fall_height so the
# projectile's max_range doesn't expire mid-air if the ground sits
# slightly below the player's plane (e.g. pit edges, recessed rooms).
const AIRSTRIKE_RANGE_PADDING: float = 8.0


func _spawn_airstrike(skill: Skill, eff_range: float, weapon: Item) -> void:
	# Resolve the strike point on the player's ground plane. Cursor is
	# the source of truth; if it's not projectable (FPS / lock-target
	# without a cursor) we fall back to the player's facing.
	# NOTE: Airstrike intentionally skips _apply_aim_spread — Tactical
	# Strike is a paint-target weapon, not an aimed shot, so weapon
	# accuracy doesn't affect where the rocket lands. Don't "fix" the
	# missing accuracy spread call here vs the regular projectile path.
	var origin := _host.global_position
	var target_xz := _host.cursor_world_position()
	var ground: Vector3
	if target_xz == origin:
		var facing := -_host.global_transform.basis.z
		facing.y = 0.0
		if facing.length_squared() < 0.0001:
			facing = Vector3.FORWARD
		ground = origin + facing.normalized() * eff_range
	else:
		var to_target := target_xz - origin
		to_target.y = 0.0
		if to_target.length() > eff_range:
			to_target = to_target.normalized() * eff_range
		ground = origin + to_target
	ground.y = origin.y
	# Rocket — falls from the sky directly above the marker. The X
	# marker itself is painted by PrototypeAttackIndicator.spawn at click
	# time (before the wind_up await), so the player sees the target
	# paint immediately, not after the windup completes.
	var proj: PrototypeProjectile = EntityPool.acquire(PROJECTILE_SCENE)
	if proj == null:
		return
	var fall_height: float = skill.airstrike_fall_height
	var spawn_pos := ground + Vector3(0.0, fall_height, 0.0)
	proj.direction = Vector3.DOWN
	proj.speed = skill.projectile_speed
	proj.max_range = fall_height + AIRSTRIKE_RANGE_PADDING
	proj.knockback_strength = _knockback_for(skill, weapon)
	proj.source_position = ground  # blast pushes outward from impact, not from player
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
	if weapon != null:
		proj.blast_radius += weapon.get_modifier(&"blast_radius_bonus")
	var vis_scale := skill.damage_multiplier if skill.damage_multiplier > 1.0 else 1.0
	if _overclock_active:
		vis_scale *= OVERCLOCK_VISUAL_SCALE
	proj.visual_scale = vis_scale
	proj.is_bullet = weapon != null and weapon.is_bullet_weapon()
	proj.weapon_base_id = weapon.weapon_base_id if weapon != null else &""
	proj.damage_type = weapon.effective_damage_type() if weapon != null else &""
	_host.get_parent().add_child(proj)
	proj.global_position = spawn_pos
	proj.monitoring = true
	proj.reset()
	# MP: replicate the airstrike rocket so peers see it falling.
	CombatVisuals.broadcast_projectile(spawn_pos, Vector3.DOWN, proj.speed, proj.max_range,
		proj.blast_radius, proj.visual_scale, proj.is_bullet, proj.damage_type, proj.target_group)


func _resolve_hitscan(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	var aim_norm := aim.normalized()
	# Visual muzzle drives the muzzle flash; safe origin drives the
	# cone-scan + wall raycast. When the player is flush against a
	# wall or face-to-face with an enemy, the safe origin clamps back
	# to the chest so point-blank shots land on the target instead of
	# the cone starting past them.
	var visual_muzzle := _muzzle_world_position(aim_norm, source_offset)
	var origin := _safe_projectile_spawn_position(aim_norm, source_offset)
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
	var extended_range := eff_range * FALLOFF_RANGE_MULT
	var wall_dist := extended_range
	var hit_target: Node3D = null
	# Physics queries (intersect_ray) error out with "Space state is
	# inaccessible right now" when called outside the physics frame.
	# Hitscan is triggered from input handling (idle frame), so we wait
	# one physics tick before raycasting. Maximum delay = 1/60s = 16ms,
	# imperceptible.
	if not Engine.is_in_physics_frame():
		await _host.get_tree().physics_frame
	var space := _world_space()
	var wall_hit_pos: Vector3 = Vector3.ZERO
	var wall_hit_normal: Vector3 = Vector3.ZERO
	if space != null:
		var ray_end := origin + aim_norm * extended_range
		var query := PhysicsRayQueryParameters3D.create(origin, ray_end, 1)
		var result := space.intersect_ray(query)
		if not result.is_empty():
			wall_dist = origin.distance_to(result["position"])
			wall_hit_pos = result["position"]
			wall_hit_normal = result.get("normal", -aim_norm)
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
	# Visual beam length is capped at `eff_range` (NOT extended_range).
	# The damage-falloff zone past eff_range is still used by the cone
	# query above (so enemies in that zone get hit with reduced damage)
	# but the visible beam should terminate at the weapon's stated
	# range — drawing it out to extended_range made laser pistols
	# (eff_range 11m, extended 14m) look like sniper rifles streaking
	# across the room.
	var beam_end := minf(wall_dist, eff_range)
	if hit_target != null:
		beam_end = minf(beam_end, origin.distance_to(hit_target.global_position))
	var hitscan_tint := _weapon_tint(weapon)
	var _is_bullet := weapon != null and weapon.is_bullet_weapon()
	# Entire fire-VFX stack spawns OUTSIDE the awaited physics frame —
	# see _spawn_hitscan_vfx_deferred. Damage below stays synchronous.
	var spawn_decal: bool = hit_target == null and wall_hit_normal != Vector3.ZERO and wall_dist < extended_range
	var burst_pos: Vector3 = hit_target.global_position + Vector3(0.0, 0.9, 0.0) if hit_target != null else Vector3.ZERO
	_spawn_hitscan_vfx_deferred(weapon, visual_muzzle, aim_norm, beam_end, _is_bullet,
		hitscan_tint, spawn_decal, wall_hit_pos, wall_hit_normal, burst_pos)
	if hit_target != null:
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		dmg = maxi(1, int(round(float(dmg) * range_falloff(beam_end, eff_range))))
		var wbid: StringName = weapon.weapon_base_id if weapon != null else &""
		_deal_damage(hit_target, dmg, _host.global_position, _knockback_for(skill, weapon), 1, is_crit, wbid)
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
	# Same safety wrapper as _spawn_projectile — flash at the visual
	# muzzle, projectile at the safe spawn (chest when muzzle is past
	# a wall or close target).
	var visual_muzzle := _muzzle_world_position(aim_norm, source_offset)
	var spawn_pos := _safe_projectile_spawn_position(aim_norm, source_offset)
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
	proj.weapon_base_id = weapon.weapon_base_id if weapon != null else &""
	proj.damage_type = weapon.effective_damage_type() if weapon != null else &""
	_host.get_parent().add_child(proj)
	proj.global_position = spawn_pos
	proj.monitoring = true
	proj.reset()
	CombatVisuals.spawn_muzzle_flash(_host, visual_muzzle, proj.is_bullet, _weapon_tint(weapon))
	_eject_casing(weapon)
	# MP: replicate the Double Tap follow-up shot.
	CombatVisuals.broadcast_projectile(spawn_pos, aim_norm, proj.speed, proj.max_range,
		proj.blast_radius, proj.visual_scale, proj.is_bullet, proj.damage_type, proj.target_group)


## Shotgun spread — fires N independent hitscan pellets within a cone.
## Each pellet rolls its own random angular offset, casts a hitscan ray,
## and rolls damage + crit independently. Same enemy can eat multiple
## pellets at close range; pellets can land on different enemies at
## mid-range; some pellets miss entirely. Knockback is divided evenly
## across pellets so all-hits-on-one-target sums to roughly the skill's
## nominal knockback.
##
## Pellets fire as PrototypeProjectile instances (`is_bullet = true`) so
## they reuse the SMG/LMG kinetic-bullet visual — head + distortion trail
## per pellet. The previous hitscan + single-cone visual read as a wave
## front; physical projectiles read as buckshot. Each pellet rolls
## damage / crit / exile-curse / mindlink / ISR via the projectile's own
## `_hit_single` path, identical to a single-pellet hitscan.
func _resolve_shotgun(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	var aim_norm := aim.normalized()
	# Visual muzzle drives the flash; safe origin drives pellet spawns
	# so a shotgun blast at point-blank range actually lands.
	var visual_muzzle := _muzzle_world_position(aim_norm, source_offset)
	var origin := _safe_projectile_spawn_position(aim_norm, source_offset)
	if source_offset != Vector3.ZERO:
		var target_point := _host.global_position + Vector3(0.0, 1.0, 0.0) + aim_norm * eff_range
		aim_norm = (target_point - origin).normalized()
	# Point-blank penalty applies once for the whole blast — pellets
	# fanning into close-range targets still inherit the wider spread.
	var acc_mult := 1.0
	var ignore_penalty := Effects.get_aggregate(&"ignore_point_blank_penalty") > 0.0
	if not ignore_penalty:
		for enode: Node3D in SpatialGrid.query_radius(origin, MELEE_RANGE_THRESHOLD, &"enemies"):
			if enode.has_method(&"take_damage") and not is_player_friendly(enode):
				acc_mult = MELEE_RANGE_ACCURACY_MULT
				break
	# One muzzle flash for the whole burst — all pellets leave the barrel together.
	CombatVisuals.spawn_muzzle_flash(_host, visual_muzzle, true, _weapon_tint(weapon))
	_eject_casing(weapon)
	var pellets: int = maxi(1, skill.pellet_count)
	if weapon != null:
		pellets += weapon.get_modifier(&"pellet_count")
	var cone_half_rad := deg_to_rad(maxf(skill.cone_deg, 1.0) * 0.5)
	if weapon != null:
		var wep_spread: int = weapon.get_modifier(&"spread_angle")
		if wep_spread > 0:
			cone_half_rad = deg_to_rad(float(wep_spread) * 0.5)
	var per_pellet_kb := _knockback_for(skill, weapon) / float(pellets)
	# Collect pellet directions so we can broadcast a SINGLE RPC after the
	# local spawn loop — broadcasting per pellet was sending 9-18 separate
	# _rpc_projectile calls per cast. The MP wire saves N-1 round trips.
	var pellet_dirs := PackedVector3Array()
	pellet_dirs.resize(pellets)
	for p in pellets:
		var yaw_offset := randf_range(-cone_half_rad, cone_half_rad)
		var pellet_dir := aim_norm.rotated(Vector3.UP, yaw_offset)
		# Apply per-pellet aim spread so accuracy still matters — each
		# pellet rolls its own hit/spread independently of the others.
		pellet_dir = _apply_aim_spread(pellet_dir, weapon, acc_mult)
		pellet_dirs[p] = pellet_dir
		_spawn_shotgun_pellet(skill, pellet_dir, eff_range, weapon, origin, per_pellet_kb)
	# Single batched RPC for the whole burst. Common params (speed, range,
	# damage_type) are encoded once instead of per pellet.
	var damage_type := weapon.effective_damage_type() if weapon != null else &""
	var visual_scale := OVERCLOCK_VISUAL_SCALE if _overclock_active else 1.0
	CombatVisuals.broadcast_shotgun_burst(
		origin, pellet_dirs, SHOTGUN_PELLET_SPEED, eff_range,
		visual_scale, damage_type, &"enemies")


# Shotgun pellets fly as kinetic bullet projectiles (one per pellet).
# Speed is high enough that travel time at shotgun ranges (~6m) reads
# as instant to the player, but slow enough that the kinetic-bullet
# tracer + distortion trail are visible mid-flight. blast_radius=0
# keeps each pellet a single-target hit (no AoE per pellet).
const SHOTGUN_PELLET_SPEED: float = 38.0


func _spawn_shotgun_pellet(skill: Skill, dir: Vector3, eff_range: float, weapon: Item, origin: Vector3, per_pellet_kb: float) -> void:
	var proj: PrototypeProjectile = EntityPool.acquire(PROJECTILE_SCENE)
	if proj == null:
		return
	proj.direction = dir
	proj.speed = SHOTGUN_PELLET_SPEED
	proj.max_range = eff_range
	proj.knockback_strength = per_pellet_kb
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
	proj.blast_radius = 0.0
	proj.visual_scale = OVERCLOCK_VISUAL_SCALE if _overclock_active else 1.0
	proj.is_bullet = true
	proj.weapon_base_id = weapon.weapon_base_id if weapon != null else &""
	proj.damage_type = weapon.effective_damage_type() if weapon != null else &""
	# Shotgun "Point Blank" — pellets that land within 2m of the
	# muzzle deal +50% damage. Reinforces the close-range commitment
	# (the Point Blank talent waives accuracy penalty; this REWARDS
	# taking the risk).
	proj.point_blank_bonus_distance = 2.0
	proj.point_blank_bonus_mult = 1.5
	_host.get_parent().add_child(proj)
	proj.global_position = origin
	proj.monitoring = true
	proj.reset()
	# MP replication is handled by the caller via a single batched
	# broadcast_shotgun_burst RPC after the whole pellet loop completes.


## Chain lightning — pick a primary target, damage it, then bounce to the
## nearest unhit enemy within chain_jump_radius. Each bounce optionally
## reduces damage by chain_falloff_pct. Stops when chain_jumps cap is
## reached, or (when chain_jumps == 0) when running damage falls below
## chain_min_damage. Used by both Taser variants — RMB High Voltage
## sets chain_jumps=5, falloff=0; LMB Tase ticks repeatedly with
## chain_jumps=0, falloff=15.
func _resolve_chain_lightning(skill: Skill, aim: Vector3, eff_range: float, weapon: Item, source_offset: Vector3 = Vector3.ZERO) -> void:
	# Wait for physics frame before any _has_los / _clip_to_wall calls —
	# their underlying intersect_ray fails outside the physics step. Same
	# pattern as _resolve_hitscan.
	if not Engine.is_in_physics_frame():
		await _host.get_tree().physics_frame
	var aim_norm := aim.normalized()
	var origin := _muzzle_world_position(aim_norm, source_offset)
	# Electric muzzle pulse — taser had no muzzle visual before this,
	# leaving the arc disconnected from the gun. spawn_energy_pulse
	# spawns a visible emissive sphere (not just an invisible light
	# pop like spawn_muzzle_flash) so the discharge actually reads.
	CombatVisuals.spawn_energy_pulse(_host, origin, _weapon_tint(weapon))
	_eject_casing(weapon)
	# Acquire the primary target — closest enemy within range along aim,
	# inside a generous targeting cone (chain weapons aren't precision
	# tools). Falls back to the nearest enemy in skill_range if the cone
	# is empty. Walls block both the primary acquisition and the chain
	# jumps below — chain lightning isn't an x-ray weapon.
	var primary: Node3D = _pick_chain_primary(origin, aim_norm, eff_range)
	# LoS check: if a wall is between origin and the picked primary, the
	# arc shouldn't reach. Treat as a miss and clip the cosmetic arc
	# at the wall.
	if primary != null and not _has_los(origin, primary.global_position + Vector3(0.0, 0.9, 0.0)):
		primary = null
	var tint := _weapon_tint(weapon)
	if primary == null:
		# No enemy in range (or LoS-blocked) — fire a cosmetic arc to a
		# point along the aim ray at max range OR the wall hit, whichever
		# is closer. No damage, no chain. Held channels rely on this so
		# the bolt persists while sweeping the cursor.
		var miss_target := origin + aim_norm * eff_range
		miss_target = _clip_to_wall(origin, miss_target)
		CombatVisuals.spawn_lightning_arc(_host, origin, miss_target, PrototypeAttackIndicator.LIGHTNING_ARC_DURATION, tint)
		return
	# Lightning arc from origin to primary — uses the FBM lightning
	# shader on a thin stretched plane. Lightning_arc_duration matches
	# the chain skill's tick cadence so a held tase produces a near-
	# continuous arc with a tiny flicker between ticks (which actually
	# helps it read as electricity).
	var primary_chest := primary.global_position + Vector3(0.0, 0.9, 0.0)
	var origin_chest := origin
	CombatVisuals.spawn_lightning_arc(_host, origin_chest, primary_chest, PrototypeAttackIndicator.LIGHTNING_ARC_DURATION, tint)
	var hit_set: Dictionary = {}
	var current: Node3D = primary
	var damage: int = _roll_skill_damage(skill, weapon)
	var falloff_pct: float = skill.chain_falloff_pct
	if weapon != null:
		var retention: int = weapon.get_effective_modifier(&"chain_retention")
		if retention > 0:
			falloff_pct = clampf(100.0 - float(retention), 0.0, 100.0)
	var falloff: float = clampf(falloff_pct, 0.0, 100.0) / 100.0
	var max_jumps: int = skill.chain_jumps
	# Weapon-rolled chain_targets overrides the skill's built-in cap.
	if weapon != null:
		var wt: int = weapon.get_effective_modifier(&"chain_targets")
		if wt > 0:
			max_jumps = wt
	var min_damage: int = maxi(1, skill.chain_min_damage)
	var jumps_left: int = max_jumps if max_jumps > 0 else 32  # absolute cap when "until depleted"
	while current != null and damage >= min_damage:
		hit_set[current] = true
		var is_crit := _roll_crit(weapon)
		var per_enemy_dmg := damage
		# Taser "Static Build" — every 10th Taser hit on an enemy deals
		# 3× damage. Per-enemy counter so chain bounces and hold-tase
		# ticks compound separately on each target. The first 9 hits
		# build the static; the 10th releases.
		if weapon != null and weapon.weapon_base_id == &"taser_2h":
			var enemy := current as PrototypeEnemy
			if enemy != null:
				var static_mult := enemy.consume_taser_static_build()
				if static_mult != 1.0:
					per_enemy_dmg = int(round(float(per_enemy_dmg) * static_mult))
		var dmg := _crit_damage(per_enemy_dmg, is_crit)
		# No impact-burst on chain links — the lightning shader is the
		# visual contract; an additional energy-burst on top read as
		# noisy double-feedback. The arc itself terminating on each
		# enemy is the hit telegraph.
		var wbid: StringName = weapon.weapon_base_id if weapon != null else &""
		_deal_damage(current, dmg, _host.global_position, _knockback_for(skill, weapon) * 0.25, 1, is_crit, wbid)
		_apply_exile_curse_if_active(current)
		_apply_mindlink(current, dmg, is_crit)
		if max_jumps > 0:
			jumps_left -= 1
			if jumps_left <= 0:
				break
		else:
			jumps_left -= 1
			if jumps_left <= 0:
				break  # safety cap
		# Apply falloff for the next link.
		if falloff > 0.0:
			damage = int(round(float(damage) * (1.0 - falloff)))
			if damage < min_damage:
				break
		# Find the next bounce target — nearest unhit enemy within
		# chain_jump_radius of the current link, with line-of-sight from
		# the current link's chest. LoS gating prevents chain links from
		# tunneling through walls into adjacent rooms.
		var next: Node3D = null
		var best_d2 := skill.chain_jump_radius * skill.chain_jump_radius
		var current_chest_for_los := current.global_position + Vector3(0.0, 0.9, 0.0)
		for enode: Node3D in SpatialGrid.query_radius(current.global_position, skill.chain_jump_radius, &"enemies"):
			if hit_set.has(enode):
				continue
			if not enode.has_method(&"take_damage"):
				continue
			if is_player_friendly(enode):
				continue
			var d2 := current.global_position.distance_squared_to(enode.global_position)
			if d2 >= best_d2:
				continue
			if not _has_los(current_chest_for_los, enode.global_position + Vector3(0.0, 0.9, 0.0)):
				continue
			best_d2 = d2
			next = enode
		if next == null:
			break
		# Visual link from current to next — same lightning shader as
		# the primary arc so the entire chain reads as one connected
		# discharge pattern, not a sequence of separate hits.
		var current_chest := current.global_position + Vector3(0.0, 0.9, 0.0)
		var next_chest := next.global_position + Vector3(0.0, 0.9, 0.0)
		CombatVisuals.spawn_lightning_arc(current, current_chest, next_chest, PrototypeAttackIndicator.LIGHTNING_ARC_DURATION, tint)
		current = next


# Pick the primary chain target — magnet-snap to the enemy nearest the
# CURSOR position, gated on player range. Chain lightning is an arc
# weapon, not a precision aim — the player drags the cursor toward the
# rough area they want to fry and the bolt finds the closest enemy in
# that area. Distance is computed from the cursor's world point, not
# from the player; that's the difference between "snap to closest in
# aim cone" (the prior behaviour) and "magnet to closest under cursor".
# `aim_norm` is unused here but kept in the signature so the call sites
# don't have to branch.
func _pick_chain_primary(origin: Vector3, aim_norm: Vector3, eff_range: float) -> Node3D:
	# Cursor world position drives the snap target. Falls back to a
	# point along aim at half-range when the cursor isn't projectable
	# (FPS mode, lock-target without a cursor) so the picker still
	# works in those modes.
	var cursor_pos := _host.cursor_world_position()
	if cursor_pos == _host.global_position:
		cursor_pos = origin + aim_norm * (eff_range * 0.5)
	var best: Node3D = null
	var best_d2 := INF
	for enode: Node3D in SpatialGrid.query_radius(origin, eff_range, &"enemies"):
		if not enode.has_method(&"take_damage"):
			continue
		if is_player_friendly(enode):
			continue
		# Snap-distance is from CURSOR to enemy — not from player to
		# enemy. So an enemy directly under the cursor wins over a
		# closer-to-player enemy that's off to the side.
		var d2 := cursor_pos.distance_squared_to(enode.global_position)
		if d2 < best_d2:
			best_d2 = d2
			best = enode
	return best


## Elemental tint for weapon effects — returns the configured element
## color when the weapon has a damage_type set, or zero-alpha (which
## visual spawners interpret as "use class accent") when the weapon
## is neutral. Plumbed through every visual call in resolve so
## flame weapons paint red beams / red impact bursts / red lightning
## etc., regardless of which class the player is.
# Spawns the full hitscan fire-VFX stack (muzzle flash/pulse, casing,
# beam, wall decal, impact burst) one idle frame later. The hitscan
# resolver awaits a physics frame for intersect_ray; spawning the 6-10
# VFX nodes synchronously inside that window put 10-20ms into phys_ms
# every shot and read as a per-shot freeze (the laser-pistol hitch —
# CSV-traced 2026-05-25). The one-frame visual delay is imperceptible;
# damage stays synchronous in the caller.
func _spawn_hitscan_vfx_deferred(weapon: Item, visual_muzzle: Vector3, aim_norm: Vector3,
		beam_end: float, is_bullet: bool, tint: Color, spawn_decal: bool,
		wall_hit_pos: Vector3, wall_hit_normal: Vector3, burst_pos: Vector3) -> void:
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return
	_host.get_tree().process_frame.connect(func() -> void:
		if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
			return
		CombatVisuals.spawn_muzzle_flash(_host, visual_muzzle, is_bullet, tint)
		_eject_casing(weapon)
		CombatVisuals.spawn_beam(_host, aim_norm, beam_end, visual_muzzle, tint)
		# Wall decal for hitscan that terminates on geometry (no enemy in
		# the cone before the wall) — molten scorch for energy, bullet
		# hole for kinetic. Skipped when an enemy was hit (the impact
		# burst conveys it) or the beam ran out without hitting anything.
		if spawn_decal:
			var vfx_parent := _host.get_parent()
			if vfx_parent != null:
				PrototypeAttackIndicator.spawn_wall_projectile_impact(
					vfx_parent, wall_hit_pos, wall_hit_normal, is_bullet, tint)
		if burst_pos != Vector3.ZERO:
			CombatVisuals.spawn_impact_burst(_host, burst_pos, tint),
		CONNECT_ONE_SHOT)


func _weapon_tint(weapon: Item) -> Color:
	if weapon == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var elem := weapon.effective_damage_type()
	if elem == &"":
		return Color(0.0, 0.0, 0.0, 0.0)
	return Item.damage_type_color(elem)


## Returns the host's world-3D space state, or null if the host isn't
## inside a live scene tree. Every ray cast in this script goes through
## here so the four hitscan/LoS paths can guard uniformly. Hot paths
## (input → fire) can fire after the player has been freed / scene
## changed; without this guard, `space.intersect_ray()` crashed with
## "Cannot call method 'intersect_ray' on a null value" (and spammed the
## debug log — 500+ errors in one playtest).
##
## Falls back to PhysicsServer3D.space_get_direct_state(world.space) when
## World3D.direct_space_state is null. The convenience property comes
## back null in some frame phases (input handlers, deferred calls,
## between physics ticks) — the server lookup via RID works at any time
## as long as the world's space RID is still valid. Without this fallback,
## the wall-occlusion ray was getting skipped on normal fire and beams
## passed through walls (the convenience property's null state turned out
## to be common, not edge-case as I'd assumed).
func _world_space() -> PhysicsDirectSpaceState3D:
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return null
	var world := _host.get_world_3d()
	if world == null:
		return null
	return world.direct_space_state


## Line-of-sight check between two world points. Casts a ray over the
## world-collision layer (mask 1, same as hitscan). Returns true when
## the ray is unobstructed — used by chain lightning to prevent arcs
## tunneling through walls. Returns false when the host has no world.
##
## SYNC ONLY — physics queries are only valid during the physics frame.
## Callers in idle frames must do their own `await physics_frame` before
## invoking. Chain lightning's caller already does this (see
## _resolve_chain_lightning).
func _has_los(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space := _world_space()
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos, 1)
	var result := space.intersect_ray(query)
	return result.is_empty()


## Clip a target point to the first wall along the ray from origin.
## Returns the original target when nothing's in the way; otherwise the
## hit position. Used by the chain lightning miss-arc so the cosmetic
## bolt stops at a wall instead of passing through it. Returns the raw
## target when the host has no world.
##
## SYNC ONLY — see _has_los caveat.
func _clip_to_wall(origin: Vector3, target: Vector3) -> Vector3:
	var space := _world_space()
	if space == null:
		return target
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return target
	return result["position"]


## Apply Overcharge status effect to a target. Resolves the status name
## from the skill (or from weapon.damage_type when set to
## &"weapon_default") and routes to the matching enemy method. Used by
## Energy Accelerator's RMB to apply ignite/freeze/stun based on the
## weapon's rolled damage type.
func _apply_overcharge_status(target: Node, skill: Skill, weapon: Item) -> void:
	if target == null or not is_instance_valid(target):
		return
	var status_name: StringName = skill.overcharge_status
	if status_name == &"weapon_default" and weapon != null:
		match weapon.effective_damage_type():
			&"flame": status_name = &"ignite"
			&"cryo": status_name = &"freeze"
			&"electric": status_name = &"stun"
			_: status_name = &""
	match status_name:
		&"ignite":
			if target.has_method(&"apply_ignite"):
				target.apply_ignite(skill.overcharge_status_dps, skill.overcharge_status_duration)
		&"freeze", &"stun":
			# Freeze and stun share the engine path — both lock the
			# enemy in place via the existing apply_stun helper.
			if target.has_method(&"apply_stun"):
				target.apply_stun(skill.overcharge_status_duration)


func _resolve_hitscan_exact(skill: Skill, aim_norm: Vector3, eff_range: float, weapon: Item, source_offset: Vector3) -> void:
	# Same visual/safe split as _resolve_hitscan.
	var visual_muzzle := _muzzle_world_position(aim_norm, source_offset)
	var origin := _safe_projectile_spawn_position(aim_norm, source_offset)
	var extended_range := eff_range * FALLOFF_RANGE_MULT
	var wall_dist := extended_range
	var hit_target: Node3D = null
	# Wait for physics frame before raycasting — see _resolve_hitscan.
	if not Engine.is_in_physics_frame():
		await _host.get_tree().physics_frame
	var space := _world_space()
	var ray_end := origin + aim_norm * extended_range
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, 1)
	var result: Dictionary = {}
	if space != null:
		result = space.intersect_ray(query)
	var wall_hit_pos_exact: Vector3 = Vector3.ZERO
	var wall_hit_normal_exact: Vector3 = Vector3.ZERO
	if not result.is_empty():
		wall_dist = origin.distance_to(result["position"])
		wall_hit_pos_exact = result["position"]
		wall_hit_normal_exact = result.get("normal", -aim_norm)
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
	# See _resolve_hitscan for the eff_range visual cap rationale.
	var beam_end := minf(wall_dist, eff_range)
	if hit_target != null:
		beam_end = minf(beam_end, origin.distance_to(hit_target.global_position))
	var hitscan_exact_tint := _weapon_tint(weapon)
	var _is_bullet_exact := weapon != null and weapon.is_bullet_weapon()
	# Same deferred-VFX treatment as the primary hitscan path.
	var spawn_decal_exact: bool = hit_target == null and wall_hit_normal_exact != Vector3.ZERO and wall_dist < extended_range
	var burst_pos_exact: Vector3 = hit_target.global_position + Vector3(0.0, 0.9, 0.0) if hit_target != null else Vector3.ZERO
	_spawn_hitscan_vfx_deferred(weapon, visual_muzzle, aim_norm, beam_end, _is_bullet_exact,
		hitscan_exact_tint, spawn_decal_exact, wall_hit_pos_exact, wall_hit_normal_exact, burst_pos_exact)
	if hit_target != null:
		var is_crit := _roll_crit(weapon)
		var dmg := _crit_damage(_roll_skill_damage(skill, weapon), is_crit)
		dmg = maxi(1, int(round(float(dmg) * range_falloff(beam_end, eff_range))))
		var wbid: StringName = weapon.weapon_base_id if weapon != null else &""
		_deal_damage(hit_target, dmg, _host.global_position, _knockback_for(skill, weapon), 1, is_crit, wbid)
		_apply_exile_curse_if_active(hit_target)
		_apply_mindlink(hit_target, dmg, is_crit)
		_try_spawn_isr_drone(hit_target)


# ---------------------------------------------------------------------------
# Damage rolling
# ---------------------------------------------------------------------------

func _roll_crit(weapon: Item = null) -> bool:
	var base_crit := weapon.effective_crit_chance() if weapon != null and weapon.crit_chance > 0.0 else PROTO_BASE_CRIT_CHANCE
	var chance := base_crit + Effects.get_aggregate(&"crit_chance_pct") + _host._gear_crit_chance_bonus
	# AIM_HOLD (Aimed Shot) flat-adds to crit chance while RMB is held.
	chance += _host.aim_hold_crit_bonus()
	return randf() < chance

## Vertical spread is half horizontal — enough to see shots angle into
## the air or hit the floor, but left/right remains the dominant miss axis.
const VERTICAL_SPREAD_RATIO: float = 0.5
## Minimum horizontal spread on a miss (radians). Guarantees the shot
## visibly goes wide rather than grazing the target.
const MISS_MIN_SPREAD: float = 0.06

## Tiny natural-look jitter applied to ALL shots that pass the accuracy
## hit roll. Shots used to be perfectly straight on a hit, which read
## as robotic — every projectile flew the exact same line. 0.5° in
## radians (~0.0087) gives a barely-visible per-shot wobble that adds
## organic variance without losing accuracy at engagement range:
## sin(0.5°) × 30m = ~26cm deviation, well inside an enemy hitbox.
const NATURAL_JITTER_RAD: float = 0.0087

## Accuracy is a hit/miss roll: 75% accuracy = 75% of shots fly true,
## 25% get visible spread applied. accuracy_mult handles situational
## modifiers (e.g. point-blank penalty). Misses spread in both yaw and
## pitch so stray shots fly high / low as well as left / right.
func _apply_aim_spread(aim: Vector3, weapon: Item, accuracy_mult: float = 1.0) -> Vector3:
	var acc := weapon.effective_accuracy() if weapon != null else 1.0
	acc += _host._gear_hit_chance_bonus
	# AIM_HOLD (Tripod / Aimed Shot) layers a flat accuracy bonus while RMB is
	# held — the buff is intentional flat-add (not a multiplier) so the
	# Tripod's +0.3 reads as "30 more points of accuracy" regardless of
	# the rolled accuracy on the weapon.
	acc += _host.aim_hold_accuracy_bonus()
	acc *= accuracy_mult
	acc = clampf(acc, 0.0, 1.0)
	# Hit roll — accurate shots fly to the target with a small natural
	# jitter so consecutive shots don't all trace the same line. The
	# jitter is small enough that even at 30m the shot still hits an
	# enemy-sized hitbox; it's purely a "feels alive" cosmetic.
	if randf() < acc:
		var jitter := randf_range(-NATURAL_JITTER_RAD, NATURAL_JITTER_RAD)
		return aim.rotated(Vector3.UP, jitter)
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
	# Unarmed — glove modifiers add flat damage to bare-fist strikes.
	if weapon == null and skill == PrototypePlayer.UNARMED_SKILL:
		base += _host.get_unarmed_damage_bonus()
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
	CombatEffects.apply_exile_curse_if_active(enemy)


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
	# Two-pass muzzle resolution — muzzle position depends on aim
	# direction, but aim is computed from origin to target. Estimate aim
	# from chest first, derive the muzzle from that, then re-aim from
	# the muzzle to the target. Difference is sub-metre but the beam
	# now emerges from the weapon barrel like the regular shots.
	var aim_seed := (target.global_position + Vector3(0.0, 1.0, 0.0)) - (_host.global_position + Vector3(0.0, 1.0, 0.0))
	var origin := _muzzle_world_position(aim_seed)
	var aim := target.global_position + Vector3(0.0, 1.0, 0.0) - origin
	var dist := aim.length()
	if dist < 0.001:
		return
	var aim_norm := aim / dist
	CombatVisuals.spawn_beam(_host, aim_norm, dist, origin)
	CombatVisuals.spawn_impact_burst(_host, target.global_position + Vector3(0.0, 0.9, 0.0))
	var mult := 1.0
	var dmg := int(round(float(EXILE_AUTO_SHOT_BASE_DAMAGE) * mult))
	_deal_damage(target, dmg, _host.global_position, EXILE_AUTO_SHOT_KNOCKBACK, 1, false)


# ---------------------------------------------------------------------------
# Polymath Mindlink — echo damage to a nearby enemy
# ---------------------------------------------------------------------------

func _apply_mindlink(primary: Node3D, dmg: int, is_crit: bool) -> void:
	CombatEffects.apply_mindlink(primary, dmg, is_crit, _host.global_position,
		_deal_damage, true)


# ---------------------------------------------------------------------------
# Automaton ISR Drone — chance to spawn a surveillance drone on hit
# ---------------------------------------------------------------------------

func _try_spawn_isr_drone(enemy: Node3D) -> void:
	CombatEffects.try_spawn_isr_drone(enemy)
