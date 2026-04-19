extends Node

signal changed

const SAVE_PATH := "user://accessibility.tres"

var config: AccessibilityConfig

func _ready() -> void:
	config = _load_config()

func save() -> void:
	if config == null:
		return
	var err := ResourceSaver.save(config, SAVE_PATH)
	if err != OK:
		push_warning("[AccessibilityState] failed to save: %d" % err)
	changed.emit()

func _load_config() -> AccessibilityConfig:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded := load(SAVE_PATH) as AccessibilityConfig
		if loaded != null:
			return loaded
	return AccessibilityConfig.new()
