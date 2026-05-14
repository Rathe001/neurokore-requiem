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
	if scene == null:
		push_error("[EntityPool] acquire() null scene — %s" % _get_caller_hint())
		return null
	var key := scene.resource_path
	if key.is_empty():
		push_error("[EntityPool] acquire() empty resource_path — %s" % _get_caller_hint())
		return null
	if scene.get_state().get_node_count() == 0:
		push_error("[EntityPool] acquire() scene '%s' has empty state (0 nodes) — %s" % [key, _get_caller_hint()])
		return null
	if _pools.has(key):
		var pool: Array = _pools[key]
		while pool.size() > 0:
			var raw = pool.pop_back()
			if not is_instance_valid(raw):
				continue
			var node: Node3D = raw as Node3D
			if node == null:
				continue
			node.set_physics_process(true)
			node.set_process(true)
			node.visible = true
			return node
	var inst := scene.instantiate()
	if inst == null:
		push_error("[EntityPool] acquire() instantiate() returned null for '%s' — %s" % [key, _get_caller_hint()])
		return null
	return inst as Node3D


static func _get_caller_hint() -> String:
	var stack := get_stack()
	if stack == null or stack.size() < 3:
		return "unknown"
	var frame: Dictionary = stack[2]  # 0=this func, 1=acquire, 2=caller
	return "%s:%d (%s)" % [frame.get("source", "?"), frame.get("line", 0), frame.get("function", "?")]

## Return an instance to the pool instead of freeing it.
## The node is removed from the scene tree and stored for reuse.
func release(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	# Pooled nodes leave the tree but the SpatialGrid keeps a reference until the
	# node is reused. Drop the registration so queries can't return parked nodes.
	SpatialGrid.unregister(node)
	var scene := node.scene_file_path
	if scene.is_empty():
		node.queue_free()
		return
	if node.has_method(&"_pool_release"):
		node._pool_release()
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
