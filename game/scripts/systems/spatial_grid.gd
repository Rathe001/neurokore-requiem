extends Node

## Spatial hash grid for efficient proximity queries at horde scale.
##
## Entities register/unregister themselves. The grid is updated each physics
## frame so position lookups are always current. Query methods return entities
## within a radius without iterating the entire population.

const DEFAULT_CELL_SIZE := 4.0
const MOVE_THRESHOLD_SQ := 0.25

var _inv_cell_size: float = 1.0 / DEFAULT_CELL_SIZE

# category -> { cell_key: Vector2i -> { Node3D -> true } }
# Buckets are dictionaries (used as sets) rather than arrays so unregister()
# and cell migration in _update_all_positions() remove in O(1) instead of doing
# a linear scan — at horde scale, every entity that crosses a cell boundary
# this frame triggers a remove, which adds up fast with array.erase().
var _grids: Dictionary = {}
# node -> { category: StringName, cell: Vector2i }
var _tracked: Dictionary = {}
# category -> { Node3D -> true }  — flat membership set per category so callers
# (e.g. LosCuller) can iterate all members without the per-frame allocation of
# get_nodes_in_group().  Updated on register/unregister.
var _members: Dictionary = {}

func _ready() -> void:
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	_update_all_positions()

# ── Registration ──────────────────────────────────────────────────────────

func register(node: Node3D, category: StringName) -> void:
	if _tracked.has(node):
		return
	if not _grids.has(category):
		_grids[category] = {}
	if not _members.has(category):
		_members[category] = {}
	var cell := _cell_for(node.global_position)
	_insert(node, category, cell)
	_tracked[node] = { "category": category, "cell": cell, "last_pos": node.global_position }
	_members[category][node] = true

func unregister(node: Node3D) -> void:
	if not _tracked.has(node):
		return
	var info: Dictionary = _tracked[node]
	_remove(node, info["category"], info["cell"])
	var cat: StringName = info["category"]
	if _members.has(cat):
		_members[cat].erase(node)
	_tracked.erase(node)

# ── Queries ───────────────────────────────────────────────────────────────

## Returns all nodes of [category] within [radius] of [origin].
func query_radius(origin: Vector3, radius: float, category: StringName) -> Array[Node3D]:
	var results: Array[Node3D] = []
	if not _grids.has(category):
		return results
	var grid: Dictionary = _grids[category]
	var r_sq := radius * radius
	var min_cell := _cell_for(origin - Vector3(radius, 0.0, radius))
	var max_cell := _cell_for(origin + Vector3(radius, 0.0, radius))
	for cx in range(min_cell.x, max_cell.x + 1):
		for cz in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(cx, cz)
			if not grid.has(key):
				continue
			var bucket: Dictionary = grid[key]
			for node: Node3D in bucket:
				if not is_instance_valid(node):
					continue
				var diff := node.global_position - origin
				diff.y = 0.0
				if diff.length_squared() <= r_sq:
					results.append(node)
	return results

## Returns all nodes of [category] within a cone defined by origin, aim direction,
## radius, and half-angle cosine (precomputed by caller).
func query_cone(origin: Vector3, aim: Vector3, radius: float, half_cos: float, category: StringName) -> Array[Node3D]:
	var results: Array[Node3D] = []
	if not _grids.has(category):
		return results
	var grid: Dictionary = _grids[category]
	var r_sq := radius * radius
	var min_cell := _cell_for(origin - Vector3(radius, 0.0, radius))
	var max_cell := _cell_for(origin + Vector3(radius, 0.0, radius))
	for cx in range(min_cell.x, max_cell.x + 1):
		for cz in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(cx, cz)
			if not grid.has(key):
				continue
			var bucket: Dictionary = grid[key]
			for node: Node3D in bucket:
				if not is_instance_valid(node):
					continue
				var diff := node.global_position - origin
				diff.y = 0.0
				var dist_sq := diff.length_squared()
				if dist_sq > r_sq or dist_sq < 0.000001:
					continue
				var dist := sqrt(dist_sq)
				if aim.dot(diff / dist) < half_cos:
					continue
				results.append(node)
	return results

## Returns the nearest node of [category] within [radius] of [origin], or null.
func query_nearest(origin: Vector3, radius: float, category: StringName) -> Node3D:
	var best: Node3D = null
	var best_d2: float = radius * radius
	if not _grids.has(category):
		return null
	var grid: Dictionary = _grids[category]
	var min_cell := _cell_for(origin - Vector3(radius, 0.0, radius))
	var max_cell := _cell_for(origin + Vector3(radius, 0.0, radius))
	for cx in range(min_cell.x, max_cell.x + 1):
		for cz in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(cx, cz)
			if not grid.has(key):
				continue
			var bucket: Dictionary = grid[key]
			for node: Node3D in bucket:
				if not is_instance_valid(node):
					continue
				var diff := node.global_position - origin
				diff.y = 0.0
				var d2 := diff.length_squared()
				if d2 < best_d2:
					best_d2 = d2
					best = node
	return best

## Returns the flat membership set (Dictionary: Node3D → true) for a category.
## Callers iterate the keys — no allocation. Do NOT mutate the returned dict.
func get_members(category: StringName) -> Dictionary:
	return _members.get(category, {})

## Returns the count of tracked nodes in a category.
func count(category: StringName) -> int:
	if not _grids.has(category):
		return 0
	var total := 0
	var grid: Dictionary = _grids[category]
	for bucket: Dictionary in grid.values():
		total += bucket.size()
	return total

# ── Internal ──────────────────────────────────────────────────────────────

func _update_all_positions() -> void:
	# Iterate _tracked directly (no .keys() snapshot allocation each frame).
	# We can read+mutate values in place but must defer key erases to after the
	# loop — both because Dictionary iteration doesn't tolerate concurrent
	# erase, and because freed-object keys require deferred cleanup.
	var dead: Array = []
	for node in _tracked:
		if not is_instance_valid(node):
			dead.append(node)
			continue
		var info: Dictionary = _tracked[node]
		var pos: Vector3 = node.global_position
		var last: Vector3 = info["last_pos"]
		if pos.distance_squared_to(last) < MOVE_THRESHOLD_SQ:
			continue
		info["last_pos"] = pos
		var new_cell := _cell_for(pos)
		if new_cell != info["cell"]:
			var cat: StringName = info["category"]
			_remove(node, cat, info["cell"])
			_insert(node, cat, new_cell)
			info["cell"] = new_cell
	for d in dead:
		var info2: Dictionary = _tracked[d]
		var cat2: StringName = info2["category"]
		_remove(d, cat2, info2["cell"])
		if _members.has(cat2):
			_members[cat2].erase(d)
		_tracked.erase(d)

func _cell_for(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x * _inv_cell_size)),
		int(floor(pos.z * _inv_cell_size)),
	)

func _insert(node: Node3D, category: StringName, cell: Vector2i) -> void:
	var grid: Dictionary = _grids[category]
	if not grid.has(cell):
		grid[cell] = {}
	grid[cell][node] = true

# `node` is intentionally untyped — it may be a freed object when called
# from the dead-cleanup path in _update_all_positions. A typed Node3D
# parameter triggers Godot's strict type check on freed instances and
# crashes with "Object-derived class (previously freed) is not a subclass
# of the expected argument class". The freed reference is still a valid
# Dictionary key for erase(), which is all we need.
func _remove(node, category: StringName, cell: Vector2i) -> void:
	if not _grids.has(category):
		return
	var grid: Dictionary = _grids[category]
	if not grid.has(cell):
		return
	var bucket: Dictionary = grid[cell]
	bucket.erase(node)
	if bucket.is_empty():
		grid.erase(cell)
