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

# Core locomotion + combat anims (the original X Bot set). These are
# the "base" library every character carries regardless of weapon
# class. Phase 2 will add per-weapon-class overlays (pistol idle,
# rifle idle, sword idle, etc.) that compose on top.
const _IDLE_FBX: PackedScene = preload("res://assets/animations/core/Idle.fbx")
const _SLOW_RUN_FBX: PackedScene = preload("res://assets/animations/core/Slow Run.fbx")
const _FAST_RUN_FBX: PackedScene = preload("res://assets/animations/core/Fast Run.fbx")
const _PUNCH_FBX: PackedScene = preload("res://assets/animations/core/Punching.fbx")
const _FIRE_FBX: PackedScene = preload("res://assets/animations/core/Firing Rifle2.fbx")
const _HIT_FBX: PackedScene = preload("res://assets/animations/core/Hit Reaction.fbx")
const _JUMP_FBX: PackedScene = preload("res://assets/animations/core/Jumping.fbx")
const _JOG_FBX: PackedScene = preload("res://assets/animations/core/Jog Forward.fbx")
const _CROUCH_WALK_FBX: PackedScene = preload("res://assets/animations/core/Crouched Walking.fbx")
const _FIRE_MOVE_FBX: PackedScene = preload("res://assets/animations/core/Strafing.fbx")

# Phase 1 additions — universal slots that fill gaps in the existing
# state machine without requiring per-weapon-class branching.
const _CROUCH_IDLE_FBX: PackedScene = preload("res://assets/animations/ranged 2h/idle crouching.fbx")
const _WALK_BACK_FBX: PackedScene = preload("res://assets/animations/ranged 2h/walk backward.fbx")
const _STRAFE_LEFT_FBX: PackedScene = preload("res://assets/animations/ranged 2h/walk left.fbx")
const _STRAFE_RIGHT_FBX: PackedScene = preload("res://assets/animations/ranged 2h/walk right.fbx")
const _JUMP_START_FBX: PackedScene = preload("res://assets/animations/ranged 2h/jump up.fbx")
const _JUMP_AIR_FBX: PackedScene = preload("res://assets/animations/ranged 2h/jump loop.fbx")
const _JUMP_LAND_FBX: PackedScene = preload("res://assets/animations/ranged 2h/jump down.fbx")
const _HIT_LEFT_FBX: PackedScene = preload("res://assets/animations/skills/Standing React Small From Left.fbx")
const _HIT_RIGHT_FBX: PackedScene = preload("res://assets/animations/skills/Standing React Small From Right.fbx")
const _HIT_BACK_FBX: PackedScene = preload("res://assets/animations/skills/Standing React Small From Back.fbx")
const _HIT_BIG_FBX: PackedScene = preload("res://assets/animations/skills/Standing React Large From Front.fbx")
const _CAST_FBX: PackedScene = preload("res://assets/animations/skills/standing 1H cast spell 01.fbx")
const _CAST_2H_FBX: PackedScene = preload("res://assets/animations/skills/Standing 2H Cast Spell 01.fbx")
const _RELOAD_FBX: PackedScene = preload("res://assets/animations/ranged 2h/Reloading stand.fbx")
const _RELOAD_RUN_FBX: PackedScene = preload("res://assets/animations/ranged 2h/Reload running.fbx")
const _GRENADE_THROW_FBX: PackedScene = preload("res://assets/animations/misc/Run And Throw Grenade.fbx")

# Multiple death animations — randomly selected per kill for variety.
# Keyed `death_0` through `death_N`; random_death_anim() picks one.
# Add new Mixamo death FBXs to this array; they'll auto-key in order.
const _DEATH_FBXS: Array[PackedScene] = [
	preload("res://assets/animations/deaths/Death From The Front.fbx"),
	preload("res://assets/animations/deaths/Death From Right.fbx"),
	preload("res://assets/animations/deaths/Death.fbx"),
	preload("res://assets/animations/deaths/Flying Back Death.fbx"),
	preload("res://assets/animations/deaths/Standing Death Backward 01.fbx"),
	preload("res://assets/animations/deaths/Standing Death Forward 01.fbx"),
	preload("res://assets/animations/deaths/Standing Death Forward 02.fbx"),
	preload("res://assets/animations/deaths/Standing Death Left 01.fbx"),
	preload("res://assets/animations/deaths/Standing Death Left 02.fbx"),
	preload("res://assets/animations/deaths/Standing React Death Backward.fbx"),
	preload("res://assets/animations/deaths/Standing React Death Forward.fbx"),
	preload("res://assets/animations/deaths/Standing React Death Left.fbx"),
	preload("res://assets/animations/deaths/Sword And Shield Death.fbx"),
	preload("res://assets/animations/deaths/Two Handed Sword Death.fbx"),
	# Phase 1 additions — 5 new death variants
	preload("res://assets/animations/deaths/Death From Back Headshot.fbx"),
	preload("res://assets/animations/deaths/Dying.fbx"),
	preload("res://assets/animations/deaths/Falling Back Death.fbx"),
	preload("res://assets/animations/deaths/Standing Death Backward 01(1).fbx"),
	preload("res://assets/animations/deaths/Standing Death Right 01.fbx"),
]

const LIBRARY_NAME: StringName = &"xbot"

static var _library: AnimationLibrary = null


## Returns the cached AnimationLibrary, building it on first call.
static func get_library() -> AnimationLibrary:
	if _library != null:
		return _library
	_library = AnimationLibrary.new()
	# Hip-position stripping policy: ALL clips get strip_hip_position=true.
	# _strip_hip_position only zeros the X/Z components of the Hips
	# position track — vertical (Y) is preserved, so jumps still arc and
	# deaths still topple to the floor. Without stripping, Mixamo's baked-
	# in forward drift makes the visual drift across the floor relative
	# to the CharacterBody3D: punch animations step forward, hit reactions
	# step back, cast animations lean forward, deaths fall forward 1-2m,
	# etc. The body stays put; the mesh wanders. With stripping, all
	# horizontal motion comes from the CharacterBody3D's velocity (or
	# stays still for stationary clips), and limb / rotation animation
	# still reads normally.
	#
	# The flag is a no-op on clips without hip translation (idle, hits,
	# casts that don't step), so it's safe to apply universally.
	_extract(_library, &"idle", _IDLE_FBX, true, true)
	_extract(_library, &"slow_run", _SLOW_RUN_FBX, true, true)
	_extract(_library, &"fast_run", _FAST_RUN_FBX, true, true)
	_extract(_library, &"punch", _PUNCH_FBX, false, true)
	# Fire loops so LMB-hold (and enemy sustained ranged fire) reads as a
	# steady firing pose rather than a per-shot retrigger. The Mixamo
	# "Firing Rifle" clip is a short recoil cycle that loops cleanly —
	# calling _play_anim with the same key during continuous fire is a
	# no-op (no restart), so cycle drift across shots is invisible.
	_extract(_library, &"fire", _FIRE_FBX, true, true)
	_extract(_library, &"hit", _HIT_FBX, false, true)
	_extract(_library, &"jump", _JUMP_FBX, false, true)
	# Locomotion: jog is the new "default run" tempo; crouch_walk drives
	# the crouch-moving state. The CharacterBody3D's velocity drives
	# travel, not the baked-in clip motion.
	_extract(_library, &"jog", _JOG_FBX, true, true)
	_extract(_library, &"crouch_walk", _CROUCH_WALK_FBX, true, true)
	# Strafing — used whenever the player is moving AND holding the fire
	# input with a ranged weapon. Upper body keeps the rifle aimed forward,
	# legs play a tactical sidestep cycle.
	_extract(_library, &"fire_move", _FIRE_MOVE_FBX, true, true)
	# Phase 1 universal slots —
	# Crouch idle: dedicated standing-crouch pose (replaces the
	# xbot/idle fallback that left the player visually upright while
	# crouched).
	_extract(_library, &"crouch_idle", _CROUCH_IDLE_FBX, true, true)
	# Backward / lateral movement.
	_extract(_library, &"walk_back", _WALK_BACK_FBX, true, true)
	_extract(_library, &"strafe_left", _STRAFE_LEFT_FBX, true, true)
	_extract(_library, &"strafe_right", _STRAFE_RIGHT_FBX, true, true)
	# Jump split into start (wind-up + push-off, one-shot) / air
	# (falling loop) / land (touchdown, one-shot). Replaces the single
	# xbot/jump that played for all three phases. Hip-stripping leaves
	# the Y track intact so the jump arc / fall reads correctly.
	_extract(_library, &"jump_start", _JUMP_START_FBX, false, true)
	_extract(_library, &"jump_air", _JUMP_AIR_FBX, true, true)
	_extract(_library, &"jump_land", _JUMP_LAND_FBX, false, true)
	# Directional hit reactions — picker branches on hit direction.
	# Mixamo's react clips include a backward stagger step; hip-strip
	# keeps the enemy / player rooted while the upper body sells the
	# impact.
	_extract(_library, &"hit_left", _HIT_LEFT_FBX, false, true)
	_extract(_library, &"hit_right", _HIT_RIGHT_FBX, false, true)
	_extract(_library, &"hit_back", _HIT_BACK_FBX, false, true)
	_extract(_library, &"hit_big", _HIT_BIG_FBX, false, true)
	# Skill cast poses — 1H for Shield/Telekinesis/Blood Ritual,
	# 2H for AoE / heavier casts. Mixamo's cast spells lean / step
	# forward; stripping keeps the caster rooted.
	_extract(_library, &"cast", _CAST_FBX, false, true)
	_extract(_library, &"cast_2h", _CAST_2H_FBX, false, true)
	# Reload — stationary variant loops (it's a 1-2s repeating
	# rack-and-load motion). reload_run keeps player moving during the
	# reload via CharacterBody3D velocity (clip is hip-stripped).
	_extract(_library, &"reload", _RELOAD_FBX, true, true)
	_extract(_library, &"reload_run", _RELOAD_RUN_FBX, true, true)
	# Grenade throw — one-shot pitching motion. Run-and-throw lets the
	# player keep their forward momentum, hip-stripped so velocity
	# drives travel not the clip.
	_extract(_library, &"grenade_throw", _GRENADE_THROW_FBX, false, true)
	# Deaths — hip-stripped so the body topples in place without sliding
	# across the floor. The vertical (Y) component is preserved so the
	# character still falls to the ground; only X/Z drift is zeroed.
	# Ragdoll physics takes over post-death and handles any further
	# settling, so the death anim's role is just to play the topple in
	# the spot the kill occurred.
	for i in _DEATH_FBXS.size():
		_extract(_library, StringName("death_%d" % i), _DEATH_FBXS[i], false, true)
	return _library


## Returns a random qualified animation key ("xbot/death_N") for the
## enemy death handler to play. N is uniformly distributed over the loaded
## death clips.
static func random_death_anim() -> StringName:
	var n: int = _DEATH_FBXS.size()
	var idx: int = randi() % maxi(n, 1)
	return StringName("%s/death_%d" % [LIBRARY_NAME, idx])


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
static func _extract(lib: AnimationLibrary, dst_name: StringName, src_scene: PackedScene, loop: bool, strip_hip_position: bool) -> void:
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
		push_warning("[XBotAnimations] No animation found in %s" % src_scene.resource_path)
		inst.queue_free()
		return
	var anim: Animation = ap.get_animation(chosen)
	if anim == null:
		inst.queue_free()
		return
	var dup: Animation = anim.duplicate()
	dup.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if strip_hip_position:
		_strip_hip_position(dup)
	lib.add_animation(dst_name, dup)
	inst.queue_free()


# Mixamo bakes forward locomotion into the hip bone's position track.
# For loopable run/walk clips we want the character's CharacterBody3D to
# drive movement, so we zero the hip's position track — keeps the leg
# animation but stops the visual from "running off" relative to the body.
static func _strip_hip_position(anim: Animation) -> void:
	for i in range(anim.get_track_count()):
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var path_str := String(anim.track_get_path(i))
		if not path_str.contains("Hips"):
			continue
		# Use the first key as the "rest" position so we keep authored
		# vertical hip height; zero out forward translation by re-anchoring
		# every key to the first one.
		var key_count := anim.track_get_key_count(i)
		if key_count == 0:
			continue
		var rest_pos: Vector3 = anim.track_get_key_value(i, 0)
		for k in range(key_count):
			# Keep Y (vertical bob) but lock X / Z to rest position.
			var cur: Vector3 = anim.track_get_key_value(i, k)
			anim.track_set_key_value(i, k, Vector3(rest_pos.x, cur.y, rest_pos.z))
		break
