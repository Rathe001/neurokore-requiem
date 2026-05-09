extends Node3D
class_name EnemiesContainer

## Container for all spawned enemies. In multiplayer, the MultiplayerSpawner
## child (baked into level_shell.tscn) replicates add_child / remove_child
## to all peers so clients see the same enemies the host spawned.
##
## The spawner MUST exist before LevelBuilder runs its first build pass —
## a runtime _ready() creation would miss the initial wave of enemies
## because LevelBuilder is a sibling whose _ready fires before this one,
## and the spawner only replicates events that happen after it enters
## the tree. That's why the spawner lives in the .tscn instead of being
## created here.
##
## In single-player, enemies are added here the same way but without any
## network replication — the spawner is inert when there's no peer.

const ENEMY_SCENE: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")


# ── Drop-in snapshot (Phase 7) ───────────────────────────────────────

## Host-side: serialize every live enemy for a late-joining peer.
func serialize_all() -> Array:
	var result: Array = []
	for child in get_children():
		if not child is PrototypeEnemy:
			continue
		var e: PrototypeEnemy = child
		var visual_rot: float = e.visual.rotation.y if e.visual != null else 0.0
		result.append({
			&"name": e.name,
			&"px": e.global_position.x,
			&"py": e.global_position.y,
			&"pz": e.global_position.z,
			&"ry": visual_rot,
			&"health": e.net_health,
			&"max_health": e.net_max_health,
			&"state": e.net_state,
			&"level": e.level,
			&"is_boss": e.is_boss,
			&"display_name": e.display_name,
		})
	return result


## Client-side: recreate enemies from a snapshot so node paths match
## the host's tree and MultiplayerSynchronizer updates flow correctly.
func apply_snapshot(data: Array) -> void:
	for entry in data:
		var d: Dictionary = entry as Dictionary
		if d == null:
			continue
		var state_val: int = int(d.get(&"state", 0))
		# Skip dead enemies — no need to spawn corpses for the joiner.
		if state_val == PrototypeEnemy.State.DEAD:
			continue
		var enemy: PrototypeEnemy = EntityPool.acquire(ENEMY_SCENE) as PrototypeEnemy
		if enemy == null:
			continue
		# Name MUST match the host's node name so the synchronizer routes
		# updates to this node. Set before add_child.
		enemy.name = String(d.get(&"name", ""))
		var lvl: int = int(d.get(&"level", 1))
		if lvl > 0:
			enemy.level = lvl
		enemy.is_boss = bool(d.get(&"is_boss", false))
		var dname: String = d.get(&"display_name", "")
		if dname != "":
			enemy.display_name = dname
		add_child(enemy)
		enemy.global_position = Vector3(
			float(d.get(&"px", 0.0)),
			float(d.get(&"py", 0.0)),
			float(d.get(&"pz", 0.0)),
		)
		if enemy.has_method(&"reset"):
			enemy.reset()
		# Override health / state from snapshot AFTER reset (which sets
		# health to max_health). The synchronizer will correct these on
		# the next tick, but seeding them avoids a 1-frame pop.
		enemy.net_health = int(d.get(&"health", enemy.net_health))
		enemy.net_max_health = int(d.get(&"max_health", enemy.net_max_health))
		enemy.net_state = state_val
		if enemy.visual != null:
			enemy.visual.rotation.y = float(d.get(&"ry", 0.0))
