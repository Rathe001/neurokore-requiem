class_name CombatConstants
extends RefCounted
## Shared constants used by both player and enemy physics / animation.
## Import via CombatConstants.KNOCKBACK_DURATION etc. — no autoload needed.

const KNOCKBACK_DURATION := 0.22
const GRAVITY := 22.0

# Animation name fallback arrays. Player and enemy share these core sets;
# character-specific extras (ANIM_WALK_BACK, ANIM_INTERACT, etc.) stay local.
# "xbot/*" entries come from the merged AnimationLibrary that
# XBotAnimations.install_on() registers on characters using the Mixamo X Bot
# rig — listed first so X Bot enemies/players prefer them. Trailing entries
# are the legacy UAL1 / Quaternius animation names, kept so any older
# character that still uses those models continues to work.
const ANIM_IDLE: Array[StringName] = [&"xbot/idle", &"Idle_Normal", &"Idle", &"Idle_Loop", &"IDLE_NORMAL", &"Hard stand"]
const ANIM_RUN: Array[StringName] = [&"xbot/jog", &"xbot/fast_run", &"xbot/slow_run", &"Jog_Fwd", &"Walk_Normal", &"Jog_Fwd_Loop", &"JOG_FWD", &"WALK_NORMAL", &"Run (1_18)", &"Walk (1_24)"]
const ANIM_ATTACK: Array[StringName] = [&"xbot/punch", &"Sword_Attack", &"Punch_Cross", &"SWORD_ATTACK", &"PUNCH_CROSS"]
## Ranged-weapon firing pose, stationary. Loops (set in XBotAnimations)
## so LMB-hold reads as a steady firing stance. Player + enemy code
## branches on weapon ranged-ness to pick ANIM_FIRE over ANIM_ATTACK.
const ANIM_FIRE: Array[StringName] = [&"xbot/fire"]
## Firing while moving — tactical strafe, upper body keeps the rifle
## aimed forward. The player picks this over ANIM_FIRE whenever the
## fire input is held AND _want_dir is non-zero.
const ANIM_FIRE_MOVE: Array[StringName] = [&"xbot/fire_move"]
## No dedicated crouch idle in the X Bot library yet — fall back to
## xbot/idle so the player stays standing visually but the log doesn't
## spam "no match found" every frame while crouched. Source a Mixamo
## "Crouching Idle" clip and add it to XBotAnimations to upgrade.
const ANIM_CROUCH_IDLE: Array[StringName] = [&"Crouch_Idle", &"Crouch_Idle_Loop", &"CROUCH_IDLE", &"Crouch", &"CROUCH", &"xbot/idle"]
const ANIM_JUMP: Array[StringName] = [&"xbot/jump", &"Jump", &"Jump_Start", &"JUMP", &"JUMP_START"]
const ANIM_DEATH: Array[StringName] = [
	&"xbot/death",
	&"Death01", &"Death_1", &"Death_2", &"Death_A", &"Death_B", &"Death",
	&"Dying_A", &"Dying_B", &"Die",
	&"DEATH_1", &"DEATH_2", &"DEATH",
]
const ANIM_HIT: Array[StringName] = [&"xbot/hit"]
