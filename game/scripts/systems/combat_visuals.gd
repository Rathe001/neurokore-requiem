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

static func spawn_beam(host: Node3D, aim: Vector3, length: float, source_offset: Vector3 = Vector3.ZERO) -> void:
	PrototypeAttackIndicator.spawn_beam(host, aim, length, source_offset)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_beam.rpc(host.global_position, aim, length, source_offset, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_beam(origin: Vector3, aim: Vector3, length: float, source_offset: Vector3, is_player: bool) -> void:
	var anchor := _make_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_beam(anchor, aim, length, source_offset)
	_free_anchor_deferred(anchor)


# ── Hit cone (melee shockwave) ──────────────────────────────────

static func spawn_hit_cone(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float) -> void:
	PrototypeAttackIndicator.spawn_hit_cone(host, aim, attack_range, cone_deg)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_hit_cone.rpc(host.global_position, aim, attack_range, cone_deg, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_hit_cone(origin: Vector3, aim: Vector3, attack_range: float, cone_deg: float, is_player: bool) -> void:
	var anchor := _make_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_hit_cone(anchor, aim, attack_range, cone_deg)
	_free_anchor_deferred(anchor)


# ── Hit radial (AoE shockwave) ──────────────────────────────────

static func spawn_hit_radial(host: Node3D, radius: float) -> void:
	PrototypeAttackIndicator.spawn_hit_radial(host, radius)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_hit_radial.rpc(host.global_position, radius, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_hit_radial(origin: Vector3, radius: float, is_player: bool) -> void:
	var anchor := _make_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_hit_radial(anchor, radius)
	_free_anchor_deferred(anchor)


# ── Impact burst ────────────────────────────────────────────────

static func spawn_impact_burst(host: Node3D, world_pos: Vector3, color_override: Color = Color(0, 0, 0, 0)) -> void:
	PrototypeAttackIndicator.spawn_impact_burst(host, world_pos, color_override)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_impact_burst.rpc(host.global_position, world_pos, color_override, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_impact_burst(origin: Vector3, world_pos: Vector3, color_override: Color, is_player: bool) -> void:
	var anchor := _make_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_impact_burst(anchor, world_pos, color_override)
	_free_anchor_deferred(anchor)


# ── Explosion ───────────────────────────────────────────────────

static func spawn_explosion(host: Node3D, world_pos: Vector3, blast_radius: float, color_override: Color = Color(0, 0, 0, 0)) -> void:
	PrototypeAttackIndicator.spawn_explosion(host, world_pos, blast_radius, color_override)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_explosion.rpc(host.global_position, world_pos, blast_radius, color_override, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_explosion(origin: Vector3, world_pos: Vector3, blast_radius: float, color_override: Color, is_player: bool) -> void:
	var anchor := _make_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_explosion(anchor, world_pos, blast_radius, color_override)
	_free_anchor_deferred(anchor)


# ── Telegraph: cone (enemy attack warning) ──────────────────────

static func spawn_cone(host: Node3D, aim: Vector3, attack_range: float, cone_deg: float, wind_up: float = 0.0) -> void:
	PrototypeAttackIndicator.spawn_cone(host, aim, attack_range, cone_deg, wind_up)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_cone.rpc(host.global_position, aim, attack_range, cone_deg, wind_up, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_cone(origin: Vector3, aim: Vector3, attack_range: float, cone_deg: float, wind_up: float, is_player: bool) -> void:
	var anchor := _make_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_cone(anchor, aim, attack_range, cone_deg, wind_up)
	# Telegraphs attach to host — anchor must outlive the fade. wind_up
	# is the pre-fade hold; FADE_DURATION (0.15s) is the fade itself.
	_free_anchor_delayed(anchor, wind_up + 0.2)


# ── Telegraph: radial (enemy AoE warning) ───────────────────────

static func spawn_radial(host: Node3D, radius: float, wind_up: float = 0.0) -> void:
	PrototypeAttackIndicator.spawn_radial(host, radius, wind_up)
	if NetState.is_in_lobby():
		var cv: Node = host.get_node(_AUTOLOAD_PATH)
		cv._rpc_radial.rpc(host.global_position, radius, wind_up, host.is_in_group(&"player"))

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_radial(origin: Vector3, radius: float, wind_up: float, is_player: bool) -> void:
	var anchor := _make_anchor(origin, is_player)
	PrototypeAttackIndicator.spawn_radial(anchor, radius, wind_up)
	_free_anchor_delayed(anchor, wind_up + 0.2)


# ── Internals ───────────────────────────────────────────────────

## Create a temporary anchor Node3D at the given world position, parented
## to the scene root. The indicator attaches its mesh to anchor.get_parent(),
## so we need the anchor to be a child of a visible node. The is_player
## flag determines the color via PrototypeAttackIndicator._color_for_host().
func _make_anchor(origin: Vector3, is_player: bool) -> Node3D:
	var anchor := Node3D.new()
	get_tree().current_scene.add_child(anchor)
	anchor.global_position = origin
	if is_player:
		anchor.add_to_group(&"player")
	return anchor

## Free the anchor after the current frame so the indicator's setup code
## (which runs synchronously during the spawn call) has finished attaching
## its child nodes to anchor.get_parent().
func _free_anchor_deferred(anchor: Node3D) -> void:
	anchor.queue_free()

## Free the anchor after a delay. Used for telegraphs which attach their
## mesh as a child of the host — the anchor must outlive the visual.
func _free_anchor_delayed(anchor: Node3D, delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_instance_valid(anchor):
			anchor.queue_free()
	)
