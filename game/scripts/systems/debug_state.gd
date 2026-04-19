extends Node

# Autoload. Resolves the active DebugConfig at startup: if the gitignored
# `debug_local.tres` exists it wins; otherwise we fall back to the committed
# defaults. To override, copy defaults.tres to local.tres and edit there.

const DEFAULTS_PATH := "res://resources/debug/debug_defaults.tres"
const LOCAL_PATH := "res://resources/debug/debug_local.tres"

var config: DebugConfig

func _ready() -> void:
	config = _load_config()
	if config == null:
		push_warning("[DebugState] no debug config found; using in-memory defaults")
		config = DebugConfig.new()

func _load_config() -> DebugConfig:
	if ResourceLoader.exists(LOCAL_PATH):
		var local := load(LOCAL_PATH) as DebugConfig
		if local != null:
			print("[DebugState] loaded local override: ", LOCAL_PATH)
			return local
	if ResourceLoader.exists(DEFAULTS_PATH):
		return load(DEFAULTS_PATH) as DebugConfig
	return null
