extends Area2D
class_name ZoneExit

signal used(target_scene: PackedScene)

@export_file("*.tscn") var target_scene_path: String

var _used := false

func _ready() -> void:
	add_to_group(&"zone_exit")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _used:
		return
	if not body.is_in_group(&"player"):
		return
	if not _can_use():
		return
	var scene := _load_target()
	if scene == null:
		return
	_used = true
	used.emit(scene)

func _can_use() -> bool:
	return true

func _load_target() -> PackedScene:
	if target_scene_path == "":
		return null
	return load(target_scene_path) as PackedScene
