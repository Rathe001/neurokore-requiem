extends StaticBody3D
class_name DestructibleProp
## A breakable world object built from primitive meshes. Player attacks
## damage it via the standard take_damage() interface; on death it plays
## a break effect and optionally drops loot / credits. Piggybacks on the
## &"enemies" group + SpatialGrid category so all three attack paths
## (hitscan, projectile, AoE) work with zero changes to PlayerCombat.

const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_item_pickup.tscn")
const CREDIT_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_credit_pickup.tscn")

const BREAK_DURATION := 0.15
const PARTICLE_LIFETIME := 0.4

@export var max_health: int = 10
@export var drops_loot: bool = false
@export var drops_credits: bool = true
@export var credit_range: Vector2i = Vector2i(1, 3)
## Base color for the mesh material. Set by ClutterBuilder on creation.
@export var prop_color: Color = Color(0.5, 0.5, 0.5)
## When true, this prop also sits on the PILLAR layer (128) so it blocks
## enemy projectiles and LOS rays — acting as cover when the player crouches.
@export var provides_cover: bool = false

var _health: int
var _alive: bool = true
var _hit_flash_tween: Tween
var _visual: MeshInstance3D


func _ready() -> void:
	collision_layer = (2 | 128) if provides_cover else 2  # ENEMY + PILLAR for cover props
	collision_mask = 0
	add_to_group(&"enemies")
	add_to_group(&"structures")
	_health = max_health
	# Find child mesh for hit flash.
	for child in get_children():
		if child is MeshInstance3D:
			_visual = child
			break
	# Defer SpatialGrid registration so global_position reflects the
	# final scene-tree transform — programmatically-created nodes added
	# during level build may not have their global transform resolved
	# until after the current tree-change batch completes.
	_register_spatial.call_deferred()


func _register_spatial() -> void:
	if not is_inside_tree():
		return
	SpatialGrid.register(self, &"enemies")


func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0, multistrike: int = 1, is_crit: bool = false, _weapon_base_id: StringName = &"") -> void:
	if not _alive:
		return
	# In MP only the host applies damage; clients route hits via the
	# request_damage RPC and receive visuals via _client_show_hit /
	# _client_break. Mirrors PrototypeEnemy._is_remote_enemy gating.
	if NetState.is_in_lobby() and not multiplayer.is_server():
		return
	_health -= amount
	_play_hit_local(amount, multistrike, is_crit)
	# Broadcast hit visuals to remote peers so every player sees the
	# damage number / flash, not just the attacker.
	if NetState.is_in_lobby():
		_client_show_hit.rpc(amount, multistrike, is_crit)
	if _health <= 0:
		_break()


@rpc("any_peer", "call_remote", "reliable")
func request_damage(amount: int, knockback_from: Vector3, knockback_strength: float, multistrike: int, is_crit: bool) -> void:
	if not multiplayer.is_server():
		return
	if not is_inside_tree():
		return
	take_damage(amount, knockback_from, knockback_strength, multistrike, is_crit)


## Host → all clients: play hit feedback locally. Unreliable because a
## dropped damage number is purely cosmetic.
@rpc("authority", "call_remote", "unreliable")
func _client_show_hit(amount: int, multistrike: int, is_crit: bool) -> void:
	if not _alive or not is_inside_tree():
		return
	_play_hit_local(amount, multistrike, is_crit)


## Host → all clients: mirror the break locally (particles, scale-to-zero
## tween, queue_free). Loot/credit drops are NOT broadcast — those are
## host-authoritative and the host's PickupsContainer replicates pickups
## to clients separately.
@rpc("authority", "call_remote", "reliable")
func _client_break() -> void:
	if not _alive or not is_inside_tree():
		return
	_play_break_local()


func _play_hit_local(amount: int, multistrike: int, is_crit: bool) -> void:
	var head := global_position + Vector3(0.0, 0.8, 0.0)
	DamageNumber.spawn(get_parent(), head, amount, multistrike, is_crit)
	if _visual != null:
		_hit_flash_tween = HitFlash.play(self, _visual, _hit_flash_tween)


func _break() -> void:
	_play_break_local()
	# Host-only side effects: loot + credits drop through the pickups
	# container (which itself replicates to clients), and a broadcast
	# tells remote peers to mirror the visual break.
	if NetState.is_in_lobby() and not multiplayer.is_server():
		return
	_drop_credits_on_break()
	_drop_loot_on_break()
	for p in get_tree().get_nodes_in_group(&"player"):
		if p is PrototypePlayer and p.is_alive():
			p.on_enemy_killed()
	if NetState.is_in_lobby():
		_client_break.rpc()


func _play_break_local() -> void:
	if not _alive:
		return
	_alive = false
	SpatialGrid.unregister(self)
	remove_from_group(&"enemies")
	# Disable collision shapes so the scale-to-zero tween doesn't produce
	# degenerate transforms (det == 0 physics errors). Deferred because
	# _play_break_local commonly runs from a physics callback (projectile
	# _on_body_entered → take_damage → _break) — Godot refuses to mutate
	# physics state during a query flush, so direct assignment trips
	# "Can't change this state while flushing queries." queue_free() is
	# already deferred internally, so the shape lingers one frame either
	# way — the disabled flag is what stops collision in that window.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
			child.queue_free()

	_spawn_break_particles()

	# Scale-to-zero break tween.
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.001, BREAK_DURATION).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)


func _spawn_break_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 8
	particles.lifetime = PARTICLE_LIFETIME
	particles.explosiveness = 1.0

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.06
	mat.scale_max = 0.12
	mat.color = prop_color.lightened(0.2)
	particles.process_material = mat

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	particles.draw_pass_1 = mesh

	particles.position = global_position + Vector3(0, 0.4, 0)
	# Parent to root so particles survive this node's queue_free.
	get_parent().add_child(particles)
	# Auto-cleanup after particles finish.
	get_tree().create_timer(PARTICLE_LIFETIME + 0.5).timeout.connect(particles.queue_free)


func _drop_credits_on_break() -> void:
	if not drops_credits:
		return
	var drop_pos := global_position + Vector3(0.0, 0.8, 0.0)
	var amt := randi_range(credit_range.x, credit_range.y)
	var container := _find_pickups_container()
	if container != null and NetState.is_in_lobby():
		container.spawn_credit(amt, drop_pos)
		return
	# SP: EntityPool for perf.
	var parent := get_parent()
	if parent == null:
		return
	var pickup := EntityPool.acquire(CREDIT_PICKUP_SCENE)
	pickup.amount = amt
	(container if container != null else parent).add_child(pickup)
	pickup.global_position = drop_pos
	pickup.reset()


func _drop_loot_on_break() -> void:
	if not drops_loot:
		return
	# Stochastic — 15% base chance, roughly 1 in 7 lootable props.
	if randf() >= 0.15:
		return
	var drop_pos := global_position + Vector3(0.0, 0.8, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ilvl := maxi(1, PlayerState.zone_level_offset() + 1)
	var item := ItemRoller.roll_random(ilvl, rng)
	var container := _find_pickups_container()
	if container != null:
		container.spawn_item(item, drop_pos)
	else:
		var pickup := ITEM_PICKUP_SCENE.instantiate()
		pickup.configure(item)
		var parent := get_parent()
		if parent != null:
			parent.add_child(pickup)
			pickup.global_position = drop_pos


func _find_pickups_container() -> PickupsContainer:
	var pc := get_tree().get_first_node_in_group(&"pickups_container")
	if pc is PickupsContainer:
		return pc as PickupsContainer
	return null
