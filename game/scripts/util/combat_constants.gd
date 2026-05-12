class_name CombatConstants
extends RefCounted
## Shared constants used by both player and enemy physics / animation.
## Import via CombatConstants.KNOCKBACK_DURATION etc. — no autoload needed.

const KNOCKBACK_DURATION := 0.22
const GRAVITY := 22.0

# Animation name fallback arrays. Player and enemy share these core sets;
# character-specific extras (ANIM_WALK_BACK, ANIM_INTERACT, etc.) stay local.
const ANIM_IDLE: Array[StringName] = [&"Idle_Normal", &"Idle", &"Idle_Loop", &"IDLE_NORMAL"]
const ANIM_RUN: Array[StringName] = [&"Jog_Fwd", &"Walk_Normal", &"Jog_Fwd_Loop", &"JOG_FWD", &"WALK_NORMAL"]
const ANIM_ATTACK: Array[StringName] = [&"Sword_Attack", &"Punch_Cross", &"SWORD_ATTACK", &"PUNCH_CROSS"]
const ANIM_CROUCH_IDLE: Array[StringName] = [&"Crouch_Idle", &"Crouch_Idle_Loop", &"CROUCH_IDLE", &"Crouch", &"CROUCH"]
const ANIM_JUMP: Array[StringName] = [&"Jump", &"Jump_Start", &"JUMP", &"JUMP_START"]
const ANIM_DEATH: Array[StringName] = [
	&"Death01", &"Death_1", &"Death_2", &"Death_A", &"Death_B", &"Death",
	&"Dying_A", &"Dying_B", &"Die",
	&"DEATH_1", &"DEATH_2", &"DEATH",
]
