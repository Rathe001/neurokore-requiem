class_name XBotAnimations
extends RefCounted

## Mixamo ships each animation as a separate .fbx file with its own
## AnimationPlayer holding a single track. This static helper preloads
## every X Bot animation, extracts the motion clip out of each file's
## AnimationPlayer, and assembles a single AnimationLibrary keyed by
## short standard names. Any character whose Skeleton3D uses the
## SkeletonProfileHumanoid BoneMap (i.e. has the x_bot_bonemap.tres
## assigned on import) can play any of these animations after one call
## to install_on().
##
## Library name: "xbot". Animation keys: idle / slow_run / fast_run /
## punch / fire / hit / jump / death. Reference them via _play_anim
## using the qualified form "xbot/idle" etc — combat_constants.gd's
## candidate arrays include these so the enemy state machine finds
## them automatically when the X Bot character is in use.
##
## Cached at class level — the library is built once on first call and
## reused for every subsequent install_on().

const _IDLE_FBX: PackedScene = preload("res://assets/characters/x_bot/Idle.fbx")
const _SLOW_RUN_FBX: PackedScene = preload("res://assets/characters/x_bot/Slow Run.fbx")
const _FAST_RUN_FBX: PackedScene = preload("res://assets/characters/x_bot/Fast Run.fbx")
const _PUNCH_FBX: PackedScene = preload("res://assets/characters/x_bot/Punching.fbx")
const _FIRE_FBX: PackedScene = preload("res://assets/characters/x_bot/Firing Rifle.fbx")
const _HIT_FBX: PackedScene = preload("res://assets/characters/x_bot/Hit Reaction.fbx")
const _JUMP_FBX: PackedScene = preload("res://assets/characters/x_bot/Jumping.fbx")
const _DEATH_FBX: PackedScene = preload("res://assets/characters/x_bot/Death From The Front.fbx")

const LIBRARY_NAME: StringName = &"xbot"

static var _library: AnimationLibrary = null


## Returns the cached AnimationLibrary, building it on first call.
static func get_library() -> AnimationLibrary:
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	_extract(_library, &"idle", _IDLE_FBX, true)
	_extract(_library, &"slow_run", _SLOW_RUN_FBX, true)
	_extract(_library, &"fast_run", _FAST_RUN_FBX, true)
	_extract(_library, &"punch", _PUNCH_FBX, false)
	_extract(_library, &"fire", _FIRE_FBX, false)
	_extract(_library, &"hit", _HIT_FBX, false)
	_extract(_library, &"jump", _JUMP_FBX, false)
	_extract(_library, &"death", _DEATH_FBX, false)
	return _library


## Adds the X Bot library to an AnimationPlayer, idempotently. If the
## library is already installed it's a no-op.
static func install_on(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	if ap.has_animation_library(LIBRARY_NAME):
		return
	ap.add_animation_library(LIBRARY_NAME, get_library())


# Pulls the first non-RESET animation out of `src_scene`'s AnimationPlayer
# and adds it to `lib` under `dst_name`. Sets loop mode based on `loop`
# (idle / locomotion clips loop, one-shot clips like punch don't).
# Duplicates the animation so per-instance modifications don't leak back
# into the preloaded scene's cached resource.
static func _extract(lib: AnimationLibrary, dst_name: StringName, src_scene: PackedScene, loop: bool) -> void:
	var inst: Node = src_scene.instantiate()
	if inst == null:
		return
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		inst.queue_free()
		return
	var names: PackedStringArray = ap.get_animation_list()
	var chosen: StringName = &""
	for n in names:
		if not String(n).contains("RESET"):
			chosen = n
			break
	if chosen == &"" and not names.is_empty():
		chosen = names[0]
	if chosen == &"":
		inst.queue_free()
		return
	var anim: Animation = ap.get_animation(chosen)
	if anim == null:
		inst.queue_free()
		return
	var dup: Animation = anim.duplicate()
	dup.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	lib.add_animation(dst_name, dup)
	inst.queue_free()
