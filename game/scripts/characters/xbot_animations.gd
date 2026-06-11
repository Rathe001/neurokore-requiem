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
# Two authored strafe clips — one per direction. Replaces the earlier
# single-clip-with-runtime-mirror approach, which couldn't cleanly
# derive strafe_left from strafe_right (the source baked the motion
# into Hips rotation, so mirroring either left the legs unchanged or
# rotated the muzzle 90°).
const _STRAFE_LEFT_FBX: PackedScene = preload("res://assets/animations/core/Strafe_Left.fbx")
const _STRAFE_RIGHT_FBX: PackedScene = preload("res://assets/animations/core/Strafe_Right.fbx")
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

# ── Phase 2: per-weapon-class stance overlays ────────────────────────
# Each weapon class (pistol / rifle / sword / axe / unarmed) has its
# own idle/walk/run + class-specific attack. The picker (player +
# enemy) branches on weapon_base_id via weapon_class_for_id below.
# Pistol stance — 1H ranged grip.
const _PISTOL_IDLE_FBX: PackedScene = preload("res://assets/animations/ranged 1h/pistol idle.fbx")
const _PISTOL_WALK_FBX: PackedScene = preload("res://assets/animations/ranged 1h/pistol walk.fbx")
const _PISTOL_RUN_FBX: PackedScene = preload("res://assets/animations/ranged 1h/pistol run.fbx")
# Pistol-class firing pose. No dedicated Mixamo "Firing Pistol" clip
# exists. First attempt used "Standing 1H Magic Attack 01" but that
# clip is a one-shot wind-up → strike → follow-through, and looping
# it visibly snapped from follow-through back to wind-up — read as
# "anim restarts every shot." Reusing pistol idle works because the
# idle clip is already a steady 1H aim pose (arm extended, weapon
# ready) — looping is invisible, muzzle flash + projectile spawn
# carry the "firing" feedback. Same source as _PISTOL_IDLE_FBX
# preloaded under a different name so the library carries the key
# separately and future swaps don't need to touch the picker.
const _PISTOL_FIRE_FBX: PackedScene = preload("res://assets/animations/ranged 1h/pistol idle.fbx")
# Rifle stance — 2H ranged grip. The "idle aiming" clip is the
# tactical ready stance (rifle up to shoulder); the existing
# xbot/idle is relaxed/unarmed and not appropriate when a rifle
# is equipped.
const _RIFLE_IDLE_FBX: PackedScene = preload("res://assets/animations/ranged 2h/idle aiming.fbx")
const _RIFLE_WALK_FBX: PackedScene = preload("res://assets/animations/ranged 2h/walk forward.fbx")
const _RIFLE_RUN_FBX: PackedScene = preload("res://assets/animations/ranged 2h/run forward.fbx")
# 1H melee (sword + shield pack). Knife / karambit / sword bases all
# share this stance.
const _SWORD_IDLE_FBX: PackedScene = preload("res://assets/animations/melee 1h/sword and shield idle.fbx")
const _SWORD_WALK_FBX: PackedScene = preload("res://assets/animations/melee 1h/sword and shield walk.fbx")
const _SWORD_RUN_FBX: PackedScene = preload("res://assets/animations/melee 1h/sword and shield run.fbx")
# 1H melee swing sources. Initially used the "sword and shield slash"
# variants but those clips start with a windup (small arm-forward
# motion) before the actual sweep — rapid LMB clicks cut the anim
# after only the windup played, which read as "pushing a button"
# instead of a swing. The "sword and shield attack" variants begin
# with the strong sweep motion right away, so even truncated playback
# shows a clear attack.
const _SWORD_SLASH_FBX: PackedScene = preload("res://assets/animations/melee 1h/sword and shield attack.fbx")
const _SWORD_SLASH_2_FBX: PackedScene = preload("res://assets/animations/melee 1h/sword and shield attack (2).fbx")
const _SWORD_SLASH_3_FBX: PackedScene = preload("res://assets/animations/melee 1h/sword and shield attack (3).fbx")
# 2H melee (axe pack). Hammer / sledgehammer / warhammer / axe all
# share this stance.
const _AXE_IDLE_FBX: PackedScene = preload("res://assets/animations/melee 2h/standing idle.fbx")
const _AXE_WALK_FBX: PackedScene = preload("res://assets/animations/melee 2h/standing walk forward.fbx")
const _AXE_RUN_FBX: PackedScene = preload("res://assets/animations/melee 2h/standing run forward.fbx")
const _AXE_SWING_FBX: PackedScene = preload("res://assets/animations/melee 2h/standing melee attack horizontal.fbx")
# Axe combo — the pack ships an explicit 3-hit combo (ver 1/2/3).
const _AXE_COMBO_1_FBX: PackedScene = preload("res://assets/animations/melee 2h/standing melee combo attack ver. 1.fbx")
const _AXE_COMBO_2_FBX: PackedScene = preload("res://assets/animations/melee 2h/standing melee combo attack ver. 2.fbx")
const _AXE_COMBO_3_FBX: PackedScene = preload("res://assets/animations/melee 2h/standing melee combo attack ver. 3.fbx")
# Unarmed combo variants — picker randomly chooses per swing.
# The existing _PUNCH_FBX (Punching.fbx) is variant 0.
const _PUNCH_CROSS_FBX: PackedScene = preload("res://assets/animations/unarmed/Cross Punch.fbx")
const _PUNCH_HOOK_FBX: PackedScene = preload("res://assets/animations/unarmed/Hook Punch.fbx")
const _PUNCH_UPPERCUT_FBX: PackedScene = preload("res://assets/animations/unarmed/Uppercut.fbx")

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
	# Strafe — separate authored left + right clips.
	_extract(_library, &"strafe_right", _STRAFE_RIGHT_FBX, true, true)
	_extract(_library, &"strafe_left", _STRAFE_LEFT_FBX, true, true)
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
	# Phase 2 per-weapon-class overlays — idle/walk/run + class
	# attack. Loops on locomotion + idle (stance hold for sustained
	# pose); attack clips are one-shots. All hip-stripped to keep the
	# character rooted; CharacterBody3D velocity drives travel.
	_extract(_library, &"pistol_idle", _PISTOL_IDLE_FBX, true, true)
	_extract(_library, &"pistol_walk", _PISTOL_WALK_FBX, true, true)
	_extract(_library, &"pistol_run", _PISTOL_RUN_FBX, true, true)
	# Pistol fire — loops at sustained-fire rate so LMB-hold reads as
	# steady cracks, same pattern as xbot/fire. The clip is short enough
	# that cycle drift across shots is invisible.
	_extract(_library, &"pistol_fire", _PISTOL_FIRE_FBX, true, true)
	_extract(_library, &"rifle_idle", _RIFLE_IDLE_FBX, true, true)
	_extract(_library, &"rifle_walk", _RIFLE_WALK_FBX, true, true)
	_extract(_library, &"rifle_run", _RIFLE_RUN_FBX, true, true)
	_extract(_library, &"sword_idle", _SWORD_IDLE_FBX, true, true)
	_extract(_library, &"sword_walk", _SWORD_WALK_FBX, true, true)
	_extract(_library, &"sword_run", _SWORD_RUN_FBX, true, true)
	_extract(_library, &"sword_slash", _SWORD_SLASH_FBX, false, true)
	_extract(_library, &"sword_slash_2", _SWORD_SLASH_2_FBX, false, true)
	_extract(_library, &"sword_slash_3", _SWORD_SLASH_3_FBX, false, true)
	_extract(_library, &"axe_idle", _AXE_IDLE_FBX, true, true)
	_extract(_library, &"axe_walk", _AXE_WALK_FBX, true, true)
	_extract(_library, &"axe_run", _AXE_RUN_FBX, true, true)
	_extract(_library, &"axe_swing", _AXE_SWING_FBX, false, true)
	_extract(_library, &"axe_combo_1", _AXE_COMBO_1_FBX, false, true)
	_extract(_library, &"axe_combo_2", _AXE_COMBO_2_FBX, false, true)
	_extract(_library, &"axe_combo_3", _AXE_COMBO_3_FBX, false, true)
	_extract(_library, &"punch_cross", _PUNCH_CROSS_FBX, false, true)
	_extract(_library, &"punch_hook", _PUNCH_HOOK_FBX, false, true)
	_extract(_library, &"punch_uppercut", _PUNCH_UPPERCUT_FBX, false, true)
	# Deaths — hip-stripped so the body topples in place without sliding
	# across the floor. The vertical (Y) component is preserved so the
	# character still falls to the ground; only X/Z drift is zeroed.
	# Ragdoll physics takes over post-death and handles any further
	# settling, so the death anim's role is just to play the topple in
	# the spot the kill occurred.
	for i in _DEATH_FBXS.size():
		_extract(_library, StringName("death_%d" % i), _DEATH_FBXS[i], false, true)
	return _library


# ── Weapon class mapping + per-class anim helpers ─────────────────────
# weapon_base_id → class key. Lets pickers branch on stance without
# every caller knowing the full base-id taxonomy.
const _WEAPON_CLASS_BY_BASE_ID: Dictionary = {
	&"ranged_1h":      &"pistol",
	&"smg_1h":         &"pistol",
	&"ranged_2h":      &"rifle",
	&"lmg_2h":         &"rifle",
	&"sniper_2h":      &"rifle",
	&"shotgun_2h":     &"rifle",
	&"rpg_2h":         &"rifle",
	&"accelerator_2h": &"rifle",
	&"taser_2h":       &"rifle",
	&"melee_1h":       &"melee_1h",
	&"melee_2h":       &"melee_2h",
}


## Returns the stance class for a weapon base_id (or &"unarmed" when
## the slot is empty or the id is unknown). Picker code branches on
## this to pick idle / walk / run / attack anims appropriate to the
## equipped weapon.
static func weapon_class_for_id(base_id: StringName) -> StringName:
	if base_id == &"":
		return &"unarmed"
	return _WEAPON_CLASS_BY_BASE_ID.get(base_id, &"unarmed")


## Returns the idle anim candidates for a weapon class. Always falls
## back through &"xbot/idle" so an enemy without the per-class clip
## still resolves.
static func idle_anim_for_class(class_id: StringName) -> Array[StringName]:
	match class_id:
		&"pistol":   return [&"xbot/pistol_idle", &"xbot/idle"]
		&"rifle":    return [&"xbot/rifle_idle", &"xbot/idle"]
		&"melee_1h": return [&"xbot/sword_idle", &"xbot/idle"]
		&"melee_2h": return [&"xbot/axe_idle", &"xbot/idle"]
		_:           return [&"xbot/idle"]


## Walk-tempo locomotion (currently unused on player path — kept for
## future "walk" state separate from jog). Falls back to xbot/jog.
static func walk_anim_for_class(class_id: StringName) -> Array[StringName]:
	match class_id:
		&"pistol":   return [&"xbot/pistol_walk", &"xbot/jog"]
		&"rifle":    return [&"xbot/rifle_walk", &"xbot/jog"]
		&"melee_1h": return [&"xbot/sword_walk", &"xbot/jog"]
		&"melee_2h": return [&"xbot/axe_walk", &"xbot/jog"]
		_:           return [&"xbot/jog"]


## Run-tempo locomotion — what the player plays at default move speed.
## Falls back to xbot/jog (the universal run).
static func run_anim_for_class(class_id: StringName) -> Array[StringName]:
	match class_id:
		&"pistol":   return [&"xbot/pistol_run", &"xbot/jog"]
		&"rifle":    return [&"xbot/rifle_run", &"xbot/jog"]
		&"melee_1h": return [&"xbot/sword_run", &"xbot/jog"]
		&"melee_2h": return [&"xbot/axe_run", &"xbot/jog"]
		_:           return [&"xbot/jog"]


## Attack anim for the class. Ranged classes return the existing
## fire pose (rifle / pistol firing is the same xbot/fire clip today;
## a dedicated pistol fire is the one remaining "missing" anim flagged
## in the audit). Melee returns the class-specific swing. Unarmed
## picks a random punch variant — caller should treat the array as
## "pick one randomly" rather than a candidate fallback chain.
static func attack_anim_for_class(class_id: StringName) -> Array[StringName]:
	match class_id:
		&"pistol":   return [&"xbot/pistol_fire", &"xbot/fire"]
		&"rifle":    return [&"xbot/fire"]
		&"melee_1h": return [&"xbot/sword_slash", &"xbot/punch"]
		&"melee_2h": return [&"xbot/axe_swing", &"xbot/punch"]
		_:           return [&"xbot/punch"]


## Ranged fire pose for the equipped class. Mirrors attack_anim_for_class
## for the ranged subset — keeps a single source of truth for "what
## does THIS gun's firing look like". Used by the player's
## _ranged_fire_anim to override the generic xbot/fire fallback.
static func fire_anim_for_class(class_id: StringName) -> Array[StringName]:
	match class_id:
		&"pistol": return [&"xbot/pistol_fire", &"xbot/fire"]
		_:         return [&"xbot/fire"]


## Combo-aware melee attack. `step` is 0/1/2 from PrototypePlayer's
## melee combo state machine — each step plays a distinct swing so
## a sustained 3-hit chain shows visual variety. Falls back to the
## base attack anim if the variant key isn't loaded.
static func combo_attack_anim_for_class(class_id: StringName, step: int) -> Array[StringName]:
	var s: int = clampi(step, 0, 2)
	match class_id:
		&"melee_1h":
			match s:
				0: return [&"xbot/sword_slash", &"xbot/punch"]
				1: return [&"xbot/sword_slash_2", &"xbot/sword_slash", &"xbot/punch"]
				_: return [&"xbot/sword_slash_3", &"xbot/sword_slash", &"xbot/punch"]
		&"melee_2h":
			# Single-clip pass. Mixamo's axe_combo ver 1/2/3 are authored
			# to chain — each one's end pose flows into the next's start —
			# but they need ~1.5s each at native speed to actually transit.
			# At the cooldown + 1.8× playback the player runs at, no two
			# clips get enough screen time to read as a chained combo;
			# rapid swings cut between disconnected half-strokes. The
			# standalone "standing melee attack horizontal" is a single
			# cohesive swing that reads cleanly at the same playback
			# rate. Step argument ignored — every swing uses the same
			# clip, matching how 1H ranged weapons collapse to one fire
			# pose. Re-author per-step if a chained-combo system lands
			# later (would need playback-rate + cooldown coordination).
			return [&"xbot/axe_swing", &"xbot/punch"]
		_:
			return attack_anim_for_class(class_id)


## Unarmed combo picker — returns one of the four punch variants
## randomly. Use for the bare-fists case to give the swing some
## visual variety across rapid strikes.
static func random_unarmed_punch() -> Array[StringName]:
	const PUNCHES: Array[StringName] = [
		&"xbot/punch",
		&"xbot/punch_cross",
		&"xbot/punch_hook",
		&"xbot/punch_uppercut",
	]
	return [PUNCHES[randi() % PUNCHES.size()]]


## Random pick from the 3-hit axe combo for melee enemies. Gives
## enemy attacks the heavy-swing feel of 2H combat (distinct from
## the player's lighter sword/punch motions) and adds per-swing
## variety so a mob of melee enemies doesn't all read as identical.
## Enemies don't track a combo step today — random is the simplest
## way to mix the three variants.
static func random_enemy_melee_swing() -> Array[StringName]:
	const SWINGS: Array[StringName] = [
		&"xbot/axe_combo_1",
		&"xbot/axe_combo_2",
		&"xbot/axe_combo_3",
	]
	return [SWINGS[randi() % SWINGS.size()], &"xbot/punch"]


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
	if not ap.has_animation_library(LIBRARY_NAME):
		ap.add_animation_library(LIBRARY_NAME, get_library())
	_ground_clips_once(ap)


# ── Clip grounding ─────────────────────────────────────────────────────
# Mixamo clips don't share a ground reference: measured foot-contact
# minimums range from -0.108 (pistol_fire) to +0.087 (strafe_right) on
# the same skeleton. The character seat anchors feet to the floor under
# the EQUIPPED CLASS IDLE, so every other clip rendered offset by the
# difference — strafing with a pistol floated the feet ~13cm ("feet
# float above the ground" bug). This pass shifts each clip's Hips
# position track Y so its OWN contact minimum is exactly 0: every clip
# then agrees with the seat, for every weapon class.
#
# Runs once, lazily, on the first install_on whose AnimationPlayer sits
# under an in-tree skeleton (measurement needs a posed rig — bone
# lengths come from the mesh). One-time cost at first character spawn,
# behind the loading screen. Clip-to-clip deltas are dominated by the
# Mixamo authoring, so one reference mesh grounds them for all bodies.
static var _clips_grounded := false
const _GROUND_SAMPLES := 24
# Clips that legitimately leave the ground reference: deaths topple the
# hips through the floor plane, jumps are airborne by design.
const _GROUND_EXCLUDE_PREFIXES: Array[String] = ["death", "jump"]


static func _ground_clips_once(ap: AnimationPlayer) -> void:
	if _clips_grounded or ap == null or not ap.is_inside_tree():
		return
	var parent := ap.get_parent()
	if parent == null:
		return
	var skel := _find_skeleton_under(parent)
	if skel == null:
		return
	var lib := get_library()
	var prev_anim := ap.assigned_animation
	for clip_name in lib.get_animation_list():
		var name_str := String(clip_name)
		var excluded := false
		for prefix in _GROUND_EXCLUDE_PREFIXES:
			if name_str.begins_with(prefix):
				excluded = true
				break
		if excluded:
			continue
		var anim := lib.get_animation(clip_name)
		if anim == null or anim.length <= 0.0:
			continue
		var full_key := StringName("%s/%s" % [LIBRARY_NAME, name_str])
		if not ap.has_animation(full_key):
			continue
		# Measure this clip's foot-contact minimum in skeleton space.
		var min_y := INF
		for s in _GROUND_SAMPLES:
			ap.stop()
			ap.play(full_key)
			ap.advance(anim.length * float(s) / float(_GROUND_SAMPLES))
			skel.force_update_all_bone_transforms()
			for b in skel.get_bone_count():
				var bn := skel.get_bone_name(b)
				if not (bn.contains("Foot") or bn.contains("Toe")):
					continue
				min_y = minf(min_y, skel.get_bone_global_pose(b).origin.y)
		if min_y == INF or absf(min_y) < 0.005:
			continue
		# Shift the Hips position track so the contact minimum lands at 0.
		for t in anim.get_track_count():
			if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			if not String(anim.track_get_path(t)).contains("Hips"):
				continue
			for k in anim.track_get_key_count(t):
				var v: Vector3 = anim.track_get_key_value(t, k)
				anim.track_set_key_value(t, k, Vector3(v.x, v.y - min_y, v.z))
			break
	ap.stop()
	if prev_anim != "":
		ap.play(prev_anim)
	_clips_grounded = true


static func _find_skeleton_under(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var f := _find_skeleton_under(c)
		if f != null:
			return f
	return null


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
