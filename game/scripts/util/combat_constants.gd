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
## Dedicated crouch idle. Prefers the Mixamo "idle crouching" clip
## from the Rifle Pack; falls through to legacy keys then standing
## idle so a character without the new lib still resolves.
const ANIM_CROUCH_IDLE: Array[StringName] = [&"xbot/crouch_idle", &"Crouch_Idle", &"Crouch_Idle_Loop", &"CROUCH_IDLE", &"Crouch", &"CROUCH", &"xbot/idle"]
## Generic jump — single clip. Player code prefers ANIM_JUMP_START /
## _AIR / _LAND below for the three jump phases; this stays as a
## last-resort fallback for enemies that only have a generic jump.
const ANIM_JUMP: Array[StringName] = [&"xbot/jump", &"Jump", &"Jump_Start", &"JUMP", &"JUMP_START"]
## Reload — stationary motion, loops while _reload_remain > 0.
const ANIM_RELOAD: Array[StringName] = [&"xbot/reload"]
## Reload while moving — preferred when the player has wish_dir != 0
## during a reload (run-and-reload feel).
const ANIM_RELOAD_RUN: Array[StringName] = [&"xbot/reload_run"]
## Grenade throw — one-shot pitching motion.
const ANIM_GRENADE_THROW: Array[StringName] = [&"xbot/grenade_throw"]
## Skill cast — 1H magic-style channel pose. Used by Shield /
## Telekinesis / Blood Ritual / similar cast skills.
const ANIM_CAST: Array[StringName] = [&"xbot/cast"]
## Heavier 2H cast variant for AoE / channeled skills.
const ANIM_CAST_2H: Array[StringName] = [&"xbot/cast_2h"]
## Directional hit reactions. Picker chooses based on hit angle
## relative to facing direction. Big variant for heavier impacts.
const ANIM_HIT_LEFT: Array[StringName] = [&"xbot/hit_left"]
const ANIM_HIT_RIGHT: Array[StringName] = [&"xbot/hit_right"]
const ANIM_HIT_BACK: Array[StringName] = [&"xbot/hit_back"]
const ANIM_HIT_BIG: Array[StringName] = [&"xbot/hit_big"]
const ANIM_DEATH: Array[StringName] = [
	&"xbot/death",
	&"Death01", &"Death_1", &"Death_2", &"Death_A", &"Death_B", &"Death",
	&"Dying_A", &"Dying_B", &"Die",
	&"DEATH_1", &"DEATH_2", &"DEATH",
]
const ANIM_HIT: Array[StringName] = [&"xbot/hit"]
