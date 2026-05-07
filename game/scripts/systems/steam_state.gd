extends Node

## Steam SDK lifecycle. Initializes the GodotSteam GDExtension on launch and
## ticks Steam callbacks every frame so events (lobby invites, achievement
## grants, P2P messages) are delivered.
##
## Treat this as the source of truth for "is Steam available and logged in?":
## anything that needs Steam (multiplayer, stats, friends list, cloud saves)
## should check `initialized` before proceeding and listen for the
## `initialized_changed` signal to react when it flips.
##
## Init failures are non-fatal — the game runs fine without Steam, just
## without the cloud / network / stats features. If the user launched the
## .exe directly without `steam_appid.txt` next to it (and isn't logged
## into the Steam client), init will fail; that's expected outside of a
## proper Steam launch.

signal initialized_changed(available: bool)

const APP_ID: int = 4689320

var initialized: bool = false
var steam_id: int = 0
var persona_name: String = ""

func _ready() -> void:
	# Ticking callbacks every frame is required even before init — once
	# init succeeds the same loop delivers Steam events. Cheap when not
	# initialized.
	process_priority = -100  # before gameplay autoloads
	_init_steam()


func _process(_delta: float) -> void:
	if initialized:
		Steam.run_callbacks()


# Wraps steamInitEx so we get the verbal failure reason on a bad init —
# the bare bool from steamInit() makes it hard to distinguish "Steam not
# running" from "wrong app id" from "library missing."
#
# Second arg `false` = don't embed callbacks. We tick run_callbacks() in
# _process instead so the callback dispatch is visible in code (easier to
# debug than an internal thread). Match this with `embed_callbacks=false`
# in [steam] project settings.
func _init_steam() -> void:
	if not _has_steam_singleton():
		push_warning("[SteamState] GodotSteam GDExtension not loaded; Steam features disabled.")
		return
	var result: Dictionary = Steam.steamInitEx(APP_ID, false)
	var status: int = int(result.get(&"status", -1))
	if status != 0:
		var verbal: String = String(result.get(&"verbal", "unknown"))
		push_warning("[SteamState] Steam init failed (%d): %s" % [status, verbal])
		return
	initialized = true
	steam_id = int(Steam.getSteamID())
	persona_name = String(Steam.getPersonaName())
	print("[SteamState] Initialized — %s (%d)" % [persona_name, steam_id])
	initialized_changed.emit(true)


# Defensive check — running the project before the addon's GDExtension
# has loaded (first editor open, or a build that didn't bundle the lib)
# leaves `Steam` undefined. has_singleton avoids a hard crash and keeps
# the autoload's other code paths safe.
func _has_steam_singleton() -> bool:
	return Engine.has_singleton(&"Steam") or ClassDB.class_exists(&"Steam")
