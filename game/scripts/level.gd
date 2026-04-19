extends Node2D
class_name Level

# Root script for a level scene. Walks its own subtree at startup to
# count enemies, then emits `cleared` when the last one dies. Detection
# is signal-driven (tree_exited) so there is no per-frame scanning.

signal cleared

var _remaining := 0
var _is_cleared := false

func _ready() -> void:
	add_to_group(&"level")
	for enemy in _collect_enemies(self):
		enemy.died.connect(_on_enemy_died)
		_remaining += 1
	if _remaining == 0:
		_mark_cleared()

func _collect_enemies(node: Node) -> Array:
	var result: Array = []
	if node.is_in_group(&"enemies"):
		result.append(node)
	for child in node.get_children():
		result.append_array(_collect_enemies(child))
	return result

func _on_enemy_died() -> void:
	_remaining -= 1
	if _remaining <= 0 and not _is_cleared:
		_mark_cleared()

func _mark_cleared() -> void:
	_is_cleared = true
	cleared.emit()
