extends Node

## Pre-allocates and recycles Node3D instances to avoid per-spawn allocation.
##
## Usage:
##   var enemy := EntityPool.acquire(ENEMY_SCENE) as CharacterBody3D
##   parent.add_child(enemy)
##   enemy.global_position = pos
##
##   # When done (instead of queue_free):
##   EntityPool.release(enemy)

const DEFAULT_WARMUP := 0
const MAX_POOL_SIZE := 256

# scene_path -> Array[Node3D]
var _pools: Dictionary = {}

## Get an instance from the pool, or instantiate a new one.
func acquire(scene: PackedScene) -> Node3D:
	var key := scene.resource_path
	if _pools.has(key):
		var pool: Array = _pools[key]
		while pool.size() > 0:
			var node: Node3D = pool.pop_back()
			if is_instance_valid(node):
				node.set_physics_process(true)
				node.set_process(true)
				node.visible = true
				return node
	return scene.instantiate() as Node3D

## Return an instance to the pool instead of freeing it.
## The node is removed from the scene tree and stored for reuse.
func release(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var scene := node.scene_file_path
	if scene.is_empty():
		node.queue_free()
		return
	node.set_physics_process(false)
	node.set_process(false)
	node.visible = false
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	if not _pools.has(scene):
		_pools[scene] = []
	var pool: Array = _pools[scene]
	if pool.size() < MAX_POOL_SIZE:
		pool.append(node)
	else:
		node.queue_free()

## Pre-warm the pool with N instances of a scene.
func warmup(scene: PackedScene, count: int) -> void:
	var key := scene.resource_path
	if not _pools.has(key):
		_pools[key] = []
	var pool: Array = _pools[key]
	for i in count:
		if pool.size() >= MAX_POOL_SIZE:
			break
		var node := scene.instantiate() as Node3D
		node.set_physics_process(false)
		node.set_process(false)
		node.visible = false
		pool.append(node)

## Free all pooled instances and clear the pools.
func clear() -> void:
	for pool: Array in _pools.values():
		for node: Node3D in pool:
			if is_instance_valid(node):
				node.queue_free()
	_pools.clear()
