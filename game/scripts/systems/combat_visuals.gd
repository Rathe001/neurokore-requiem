extends Node
## Autoload that broadcasts combat visual effects to all MP peers.
## In SP, calls pass straight through to PrototypeAttackIndicator.
## In MP, the caller's client spawns the visual locally AND sends an
## RPC so every other client sees it too. All visuals are cosmetic
## and fire-and-forget, so unreliable transport is fine (a dropped
## beam or shockwave has zero gameplay impact).
##
## Call sites use CombatVisuals.spawn_beam(...) etc. instead of
## PrototypeAttackIndicator.spawn_beam(...) for any visual that
## should be visible to all players.
##
## Public API is static so callers can use CombatVisuals.spawn_*()
## without class_name (Godot 4.6 forbids class_name on autoloads).
## RPCs route through the autoload instance via host.get_node().

const _AUTOLOAD_PATH := ^"/root/CombatVisuals"


# ── Beam (hitscan) ──────────────────────────────────────────────

static func spawn_beam(host: Node3D, aim: Vector3, length: float, source_offset: Vector3 = Vector3.ZERO, tint_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	PrototypeAttackIndicator.spawn_beam(host, aim, length, source_offset, tint_override)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_beam.rpc(host.global_position, aim, length, source_offset, host.is_in_group(&"player"), tint_override)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_beam(origin: Vector3, aim: Vector3, length: float, source_offset: Vector3, is_player: bool, tint_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_beam(anchor, aim, length, source_offset, tint_override)
	_release_anchor(anchor)


# ── Lightning arc (chain lightning) ─────────────────────────────

static func spawn_lightning_arc(host: Node3D, from_pos: Vector3, to_pos: Vector3, duration: float = PrototypeAttackIndicator.LIGHTNING_ARC_DURATION, tint_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	PrototypeAttackIndicator.spawn_lightning_arc(host, from_pos, to_pos, duration, tint_override)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_lightning_arc.rpc(from_pos, to_pos, duration, host.is_in_group(&"player"), tint_override)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_lightning_arc(from_pos: Vector3, to_pos: Vector3, duration: float, is_player: bool, tint_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	var anchor := _acquire_anchor((from_pos + to_pos) * 0.5, is_player)
	PrototypeAttackIndicator.spawn_lightning_arc(anchor, from_pos, to_pos, duration, tint_override)
	_release_anchor(anchor)


# ── Hit cone (melee shockwave) ──────────────────────────────────

static func spawn_hit_cone(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float) -> void:
	PrototypeAttackIndicator.spawn_hit_cone(host, aim, attack_range, cone_deg)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_hit_cone.rpc(host.global_position, aim, attack_range, cone_deg, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_hit_cone(origin: Vector3, aim: Vector3, attack_range: float, cone_deg: float, is_player: bool) -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_hit_cone(anchor, aim, attack_range, cone_deg)
	_release_anchor(anchor)


# ── Hammer ground impact (2H hammer step-2 finisher visual) ─────

static func spawn_hammer_impact(host: Node3D) -> void:
	PrototypeAttackIndicator.spawn_hammer_impact(host)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_hammer_impact.rpc(host.global_position, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_hammer_impact(origin: Vector3, is_player: bool) -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_hammer_impact(anchor)
	_release_anchor(anchor)


# ── Blade slash (1H knife hit visual) ───────────────────────────

static func spawn_blade_slash(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float) -> void:
	PrototypeAttackIndicator.spawn_blade_slash(host, aim, attack_range, cone_deg)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_blade_slash.rpc(host.global_position, aim, attack_range, cone_deg, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_blade_slash(origin: Vector3, aim: Vector3, attack_range: float, cone_deg: float, is_player: bool) -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_blade_slash(anchor, aim, attack_range, cone_deg)
	_release_anchor(anchor)


# ── Hit radial (AoE shockwave) ──────────────────────────────────

static func spawn_hit_radial(host: Node3D, radius: float) -> void:
	PrototypeAttackIndicator.spawn_hit_radial(host, radius)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_hit_radial.rpc(host.global_position, radius, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_hit_radial(origin: Vector3, radius: float, is_player: bool) -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_hit_radial(anchor, radius)
	_release_anchor(anchor)


# ── Impact burst ────────────────────────────────────────────────

static func spawn_impact_burst(host: Node3D, world_pos: Vector3, color_override: Color = Color(0, 0, 0, 0)) -> void:
	PrototypeAttackIndicator.spawn_impact_burst(host, world_pos, color_override)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_impact_burst.rpc(host.global_position, world_pos, color_override, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_impact_burst(origin: Vector3, world_pos: Vector3, color_override: Color, is_player: bool) -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_impact_burst(anchor, world_pos, color_override)
	_release_anchor(anchor)


# ── Explosion ───────────────────────────────────────────────────

static func spawn_explosion(host: Node3D, world_pos: Vector3, blast_radius: float, color_override: Color = Color(0, 0, 0, 0), damage_type: StringName = &"") -> void:
	PrototypeAttackIndicator.spawn_explosion(host, world_pos, blast_radius, color_override, damage_type)
	WeaponSounds.play_generic(&"explosion", world_pos)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_explosion.rpc(host.global_position, world_pos, blast_radius, color_override, host.is_in_group(&"player"), damage_type)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_explosion(origin: Vector3, world_pos: Vector3, blast_radius: float, color_override: Color, is_player: bool, damage_type: StringName = &"") -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_explosion(anchor, world_pos, blast_radius, color_override, damage_type)
	_release_anchor(anchor)


# ── Telegraph: cone (enemy attack warning) ──────────────────────

static func spawn_cone(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float, wind_up: float = 0.0) -> void:
	PrototypeAttackIndicator.spawn_cone(host, aim, attack_range, cone_deg, wind_up)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_cone.rpc(host.global_position, aim, attack_range, cone_deg, wind_up, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_cone(origin: Vector3, aim: Vector3, attack_range: float, cone_deg: float, wind_up: float, is_player: bool) -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_cone(anchor, aim, attack_range, cone_deg, wind_up)
	# Telegraphs attach to host — anchor must outlive the fade. wind_up
	# is the pre-fade hold; FADE_DURATION (0.15s) is the fade itself.
	_release_anchor_delayed(anchor, wind_up + 0.2)


# ── Telegraph: radial (enemy AoE warning) ───────────────────────

static func spawn_radial(host: Node3D, radius: float, wind_up: float = 0.0) -> void:
	PrototypeAttackIndicator.spawn_radial(host, radius, wind_up)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_radial.rpc(host.global_position, radius, wind_up, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_radial(origin: Vector3, radius: float, wind_up: float, is_player: bool) -> void:
	var anchor := _acquire_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_radial(anchor, radius, wind_up)
	_release_anchor_delayed(anchor, wind_up + 0.2)


# ── Projectile (player-fired) ───────────────────────────────────
# Replicates a projectile's spawn so every peer sees it travel through
# the world. Damage stays host-authoritative on the firing peer; the
# remote echoes are GHOSTS — they render the mesh + trail + glow and
# travel along the same arc but apply no damage and don't double up on
# impact bursts / explosions (those replicate via their own RPCs).
#
# Caller spawns the live projectile locally as before, then calls
# this with the projectile's configured params. Skip the broadcast
# for non-player-fired bolts (enemy fire — damage is host-side, and
# host already replicates enemies via the enemy sync layer).

const _PROJECTILE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_projectile.tscn")


static func broadcast_projectile(spawn_pos: Vector3, direction: Vector3, speed: float, max_range: float,
		blast_radius: float, visual_scale: float, is_bullet: bool, damage_type: StringName,
		target_group: StringName) -> void:
	if not NetState.is_in_lobby():
		return
	var cv: Node = Engine.get_main_loop().root.get_node(_AUTOLOAD_PATH)
	# Encode target_group as a single bool over the wire — the value only
	# ever takes two states (&"enemies" / &"player"), so a 1-byte bool
	# replaces a length-prefixed StringName. Trims ~9 bytes per RPC.
	cv._rpc_projectile.rpc(spawn_pos, direction, speed, max_range, blast_radius,
		visual_scale, is_bullet, damage_type, target_group == &"enemies")


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_projectile(spawn_pos: Vector3, direction: Vector3, speed: float, max_range: float,
		blast_radius: float, visual_scale: float, is_bullet: bool, damage_type: StringName,
		is_player_fire: bool) -> void:
	var target_group: StringName = &"enemies" if is_player_fire else &"player"
	_spawn_ghost_projectile(spawn_pos, direction, speed, max_range, blast_radius,
		visual_scale, is_bullet, damage_type, target_group)


# Shared internal helper — both _rpc_projectile (single bolt) and
# _rpc_shotgun_burst (N-pellet batch) build identical ghost projectiles
# from per-pellet params. Damage fields stay zero so even if the ghost
# somehow reached _on_body_entered (it can't — collision_mask is forced
# to world-only on reset for ghosts) the damage roll would land at 0.
func _spawn_ghost_projectile(spawn_pos: Vector3, direction: Vector3, speed: float,
		max_range: float, blast_radius: float, visual_scale: float, is_bullet: bool,
		damage_type: StringName, target_group: StringName) -> void:
	var proj: PrototypeProjectile = EntityPool.acquire(_PROJECTILE_SCENE)
	if proj == null:
		return
	proj.is_ghost = true
	proj.target_group = target_group
	proj.direction = direction
	proj.speed = speed
	proj.max_range = max_range
	proj.blast_radius = blast_radius
	proj.visual_scale = visual_scale
	proj.is_bullet = is_bullet
	proj.damage_type = damage_type
	proj.damage_min = 0
	proj.damage_max = 0
	proj.damage_mult = 1.0
	proj.crit_chance = 0.0
	proj.knockback_strength = 0.0
	# Match the local-spawn target. PlayerCombat parents real projectiles
	# to _host.get_parent() (the level subtree). On level transitions
	# that subtree is freed wholesale; current_scene is one level up and
	# may persist across resets — ghosts parented there would leak.
	# Falls back to current_scene if no player exists yet (e.g. mid-load).
	var ghost_parent: Node = null
	var local_player := get_tree().get_first_node_in_group(&"player")
	if local_player != null:
		ghost_parent = local_player.get_parent()
	if ghost_parent == null:
		ghost_parent = get_tree().current_scene
	ghost_parent.add_child(proj)
	proj.global_position = spawn_pos
	proj.monitoring = false
	proj.reset()


# ── Shotgun burst (N pellets in one RPC) ────────────────────────
# Shotgun casts fire 9 (LMB) or 18 (RMB) pellets per trigger pull. Each
# pellet is a single-target bullet projectile with shared speed / range /
# damage_type / target_group; only direction varies. broadcast_projectile
# would send N separate RPCs, so a 4-player coop with shotgun spam was
# pushing ~144 RPCs/sec just on buckshot. broadcast_shotgun_burst sends
# ONE RPC carrying a PackedVector3Array of directions + the common
# params; the receiving peer iterates and spawns N ghost projectiles.

static func broadcast_shotgun_burst(origin: Vector3, dirs: PackedVector3Array,
		speed: float, max_range: float, visual_scale: float,
		damage_type: StringName, target_group: StringName) -> void:
	if not NetState.is_in_lobby():
		return
	if dirs.is_empty():
		return
	var cv: Node = Engine.get_main_loop().root.get_node(_AUTOLOAD_PATH)
	cv._rpc_shotgun_burst.rpc(origin, dirs, speed, max_range, visual_scale,
		damage_type, target_group == &"enemies")


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_shotgun_burst(origin: Vector3, dirs: PackedVector3Array,
		speed: float, max_range: float, visual_scale: float,
		damage_type: StringName, is_player_fire: bool) -> void:
	# Shotgun pellets are always bullets with no AoE — those are baked
	# into the per-pellet params here rather than transmitted, since
	# they're invariant across every shotgun cast.
	var target_group: StringName = &"enemies" if is_player_fire else &"player"
	for direction in dirs:
		_spawn_ghost_projectile(origin, direction, speed, max_range,
			0.0, visual_scale, true, damage_type, target_group)


# ── Internals ───────────────────────────────────────────────────

## Anchor pool — every replicated visual RPC (beam, cone, impact, etc)
## needs a transient Node3D positioned at the visual's origin so the
## existing PrototypeAttackIndicator API has a "host" to read parent /
## position / group from. Pre-pool refactor allocated and queue_freed
## one anchor per RPC; at horde-fight scale that was constant GC churn.
##
## The pool stores detached Node3Ds (not in the scene tree). Acquire
## adds to current_scene; release removes from tree and pushes back.
const _ANCHOR_POOL_MAX: int = 16
var _anchor_pool: Array[Node3D] = []


## Acquire a pooled anchor (or create one if the pool is empty),
## position it at `origin`, and put it under `current_scene`. The
## is_player flag controls the indicator's color choice via
## `_color_for_host` reading the &"player" group membership.
func _acquire_anchor(origin: Vector3, is_player: bool) -> Node3D:
	var anchor: Node3D
	if _anchor_pool.is_empty():
		anchor = Node3D.new()
	else:
		anchor = _anchor_pool.pop_back()
	get_tree().current_scene.add_child(anchor)
	anchor.global_position = origin
	# Keep group membership in sync with the requested side. Pooled
	# anchors may have either state from a prior use.
	if is_player and not anchor.is_in_group(&"player"):
		anchor.add_to_group(&"player")
	elif not is_player and anchor.is_in_group(&"player"):
		anchor.remove_from_group(&"player")
	return anchor


## Release a world-space anchor immediately after the indicator has
## finished its synchronous spawn setup. The visual is already parented
## to current_scene (via host.get_parent() inside the indicator), so
## the anchor itself is no longer needed.
func _release_anchor(anchor: Node3D) -> void:
	if not is_instance_valid(anchor):
		return
	# An anchor with surviving children means the indicator attached the
	# visual to the anchor itself (telegraph pattern) and the visual
	# hasn't fully freed yet. Don't pool — queue_free so the visual's
	# in-flight tween can complete naturally before everything tears
	# down. Pool reuse would yank the visual out from under it.
	if anchor.get_child_count() > 0:
		anchor.queue_free()
		return
	var parent := anchor.get_parent()
	if parent != null:
		parent.remove_child(anchor)
	if _anchor_pool.size() < _ANCHOR_POOL_MAX:
		_anchor_pool.append(anchor)
	else:
		anchor.queue_free()


## Release an anchor used by a telegraph (visual attached as child of
## anchor itself). Waits `delay` seconds so the visual's fade-out tween
## can finish before the anchor is recycled. Same fallback as
## `_release_anchor` — if anything's still hanging on the anchor when
## the timer fires, it gets queue_freed instead of pooled.
func _release_anchor_delayed(anchor: Node3D, delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		_release_anchor(anchor)
	)
