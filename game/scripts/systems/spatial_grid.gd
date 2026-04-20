extends Node

## Spatial hash grid for efficient proximity queries at horde scale.
##
## Entities register/unregister themselves. The grid is updated each physics
## frame so position lookups are always current. Query methods return entities
## within a radius without iterating the entire population.

const DEFAULT_CELL_SIZE := 4.0

var _cell_size: float = DEFAULT_CELL_SIZE
var _inv_cell_size: float = 1.0 / DEFAULT_CELL_SIZE

# category -> { cell_key: Vector2i -> Array[Node3D] }
var _grids: Dictionary = {}
# node -> { category: StringName, cell: Vector2i }
var _tracked: Dictionary = {}

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
	var cell := _cell_for(node.global_position)
	_insert(node, category, cell)
	_tracked[node] = { "category": category, "cell": cell }

func unregister(node: Node3D) -> void:
	if not _tracked.has(node):
		return
	var info: Dictionary = _tracked[node]
	_remove(node, info["category"], info["cell"])
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
			var bucket: Array = grid[key]
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
			var bucket: Array = grid[key]
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
			var bucket: Array = grid[key]
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

## Returns the count of tracked nodes in a category.
func count(category: StringName) -> int:
	if not _grids.has(category):
		return 0
	var total := 0
	var grid: Dictionary = _grids[category]
	for bucket: Array in grid.values():
		total += bucket.size()
	return total

# ── Internal ──────────────────────────────────────────────────────────────

func _update_all_positions() -> void:
	for node: Node3D in _tracked.keys():
		if not is_instance_valid(node):
			_tracked.erase(node)
			continue
		var info: Dictionary = _tracked[node]
		var new_cell := _cell_for(node.global_position)
		if new_cell != info["cell"]:
			var cat: StringName = info["category"]
			_remove(node, cat, info["cell"])
			_insert(node, cat, new_cell)
			info["cell"] = new_cell

func _cell_for(pos: Vector3) -> Vector2i:
	return Vector2i(
		int(floor(pos.x * _inv_cell_size)),
		int(floor(pos.z * _inv_cell_size)),
	)

func _insert(node: Node3D, category: StringName, cell: Vector2i) -> void:
	var grid: Dictionary = _grids[category]
	if not grid.has(cell):
		grid[cell] = []
	grid[cell].append(node)

func _remove(node: Node3D, category: StringName, cell: Vector2i) -> void:
	if not _grids.has(category):
		return
	var grid: Dictionary = _grids[category]
	if not grid.has(cell):
		return
	var bucket: Array = grid[cell]
	bucket.erase(node)
	if bucket.is_empty():
		grid.erase(cell)
