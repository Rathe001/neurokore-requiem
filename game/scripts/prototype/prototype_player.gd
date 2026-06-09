extends CharacterBody3D
class_name PrototypePlayer

signal health_changed(current: int, max_value: int)
signal resource_changed(current: int, max_value: int)
signal credits_changed(amount: int)
# Active-offhand shield buff state. Fires on activate, on each
# damage hit (pool reduces), on break (active=false), and on
# unequip (active=false, all zero). HUD listens to draw the
# white outline around the HP bar and to show the buff bar entry.
signal shield_buff_changed(active: bool, pool: int, pool_max: int, reduction: float, cooldown_remain: float, cooldown_total: float, duration_remain: float)
signal died
signal respawned
signal notification_requested(text: String)
signal crouch_changed(is_crouching: bool)
signal light_changed(is_on: bool)
# Fires whenever the count of currently-charmed (Doomsayer) enemies
# changes. HUD listens to update the per-perk badge count.
signal charm_count_changed(current: int, max_value: int)
signal stats_changed
# Fires when the slow-pool overlap count crosses 0 → 1 (entered first
# pool, in_pool=true) or N → 0 (exited last pool, in_pool=false). HUD
# listens to add/remove the Slowed debuff bar entry. Does not fire on
# entering/exiting a SECOND simultaneous pool — only on the actual
# state transition.
signal slow_pool_changed(in_pool: bool)
signal blood_pool_changed(in_pool: bool)
# Fires whenever the equipped main weapon's ammo state changes (shot
# fired, reload finished, item swapped). HUD reads InventoryState +
# is_reloading() / get_reload_progress() to repaint the ammo widget.
signal weapon_ammo_changed

const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_item_pickup.tscn")
const UNARMED_SKILL: Skill = preload("res://resources/skills/unarmed_attack.tres")
# Per-(class_id, gender) Meshy character meshes. Every class_id from
# AttributeState — the two origins (analog / cyborg) and all six specs
# (count, survivalist, enculted, forged, automaton, polymath) — has a
# unique mesh in both genders, so _mesh_for_class never has to fall back
# through CLASS_DEFINITIONS.origin.
const _CHARACTER_MESHES: Dictionary = {
	&"analog": {
		&"male":   preload("res://assets/characters/player_analog_male/player_analog_male.fbx"),
		&"female": preload("res://assets/characters/player_analog_female/player_analog_female.fbx"),
	},
	&"cyborg": {
		&"male":   preload("res://assets/characters/player_cyborg_male/player_cyborg_male.fbx"),
		&"female": preload("res://assets/characters/player_cyborg_female/player_cyborg_female.fbx"),
	},
	&"count": {
		&"male":   preload("res://assets/characters/player_count_male/player_count_male.fbx"),
		&"female": preload("res://assets/characters/player_count_female/player_count_female.fbx"),
	},
	&"survivalist": {
		&"male":   preload("res://assets/characters/player_survivalist_male/player_survivalist_male.fbx"),
		&"female": preload("res://assets/characters/player_survivalist_female/player_survivalist_female.fbx"),
	},
	&"enculted": {
		&"male":   preload("res://assets/characters/player_enculted_male/player_enculted_male.fbx"),
		&"female": preload("res://assets/characters/player_enculted_female/player_enculted_female.fbx"),
	},
	&"forged": {
		&"male":   preload("res://assets/characters/player_forged_male/player_forged_male.fbx"),
		&"female": preload("res://assets/characters/player_forged_female/player_forged_female.fbx"),
	},
	&"automaton": {
		&"male":   preload("res://assets/characters/player_automaton_male/player_automaton_male.fbx"),
		&"female": preload("res://assets/characters/player_automaton_female/player_automaton_female.fbx"),
	},
	&"polymath": {
		&"male":   preload("res://assets/characters/player_polymath_male/player_polymath_male.fbx"),
		&"female": preload("res://assets/characters/player_polymath_female/player_polymath_female.fbx"),
	},
}

const KNOCKBACK_DURATION := CombatConstants.KNOCKBACK_DURATION
const DEATH_HOLD := 0.9
const INTERACT_RANGE_SQ := 4.0  # 2.0m — player must stand close to interact
const PLAYER_WORLD_POS_PARAM := &"player_world_pos"

const SKILL_INPUTS: Array[StringName] = [
	&"fire",
	&"alt_fire",
	&"skill_1",
	&"skill_2",
	&"skill_3",
	&"skill_4",
	&"skill_q",
	&"skill_e",
]

const ANIM_IDLE := CombatConstants.ANIM_IDLE
const ANIM_RUN := CombatConstants.ANIM_RUN
const ANIM_WALK_BACK: Array[StringName] = [&"xbot/walk_back", &"Walk"]
const ANIM_CROUCH_IDLE := CombatConstants.ANIM_CROUCH_IDLE
const ANIM_CROUCH_MOVE: Array[StringName] = [&"xbot/crouch_walk", &"Crouch_Fwd", &"Crouch_Fwd_Loop"]
const ANIM_ATTACK := CombatConstants.ANIM_ATTACK
const ANIM_FIRE := CombatConstants.ANIM_FIRE
const ANIM_FIRE_MOVE := CombatConstants.ANIM_FIRE_MOVE
## X Bot has a single Jumping.fbx clip covering takeoff → airborne →
## landing in one animation, so all three jump states reference the
## same key. Legacy Quaternius names kept as fallbacks for any old
## rig still mounted, but the player now ships X Bot by default.
const ANIM_JUMP_START: Array[StringName] = [&"xbot/jump_start", &"xbot/jump", &"Jump_Start"]
const ANIM_JUMP_AIR: Array[StringName] = [&"xbot/jump_air", &"xbot/jump", &"Jump"]
const ANIM_JUMP_LAND: Array[StringName] = [&"xbot/jump_land", &"xbot/jump", &"Jump_Land"]
# Reload/grenade/cast constants pulled from CombatConstants — kept as
# locals so the player code reads the same as the others.
const ANIM_RELOAD := CombatConstants.ANIM_RELOAD
const ANIM_RELOAD_RUN := CombatConstants.ANIM_RELOAD_RUN
const ANIM_GRENADE_THROW := CombatConstants.ANIM_GRENADE_THROW
const ANIM_CAST := CombatConstants.ANIM_CAST
## "Interact" is the legacy Quaternius name; the X Bot library has no
## dedicated interact clip, so we fall back to xbot/idle to suppress the
## no-match warning. The visual effect is that the player keeps playing
## idle during a door/switch interaction — a real interact gesture would
## need a Mixamo grab/lever clip threaded through XBotAnimations.
const ANIM_INTERACT: Array[StringName] = [&"Interact", &"xbot/idle"]
const ANIM_DEATH := CombatConstants.ANIM_DEATH

const CROUCH_SPEED_FACTOR := 0.45
const SPRINT_SPEED_FACTOR := 1.6
# Bullet-weapon reload drags movement so the reload window is a real
# tactical pause, not a free reposition.
const RELOAD_SPEED_FACTOR := 0.85
# Moving while attacking (holding fire / mid-swing) drags movement: you trade
# mobility for putting out damage, so you commit to a stance instead of
# kiting at full speed. Replaces the old backpedal-only penalty.
const ATTACK_MOVE_SLOW_FACTOR := 0.6
const SPRINT_RESOURCE_PER_SEC := 8.0
## Penalty delay before resource regen starts after hitting 0 while sprinting.
const SPRINT_EMPTY_REGEN_DELAY := 2.0
# Health regen — out-of-combat only by default. Any take_damage() resets the
# delay; regen ticks as a percentage of max_health per second once the timer
# expires. Gear/talent surfaces:
#   hp_regen_bonus_pct      — adds to HP_REGEN_BASE_PCT (additive, e.g. +1
#                             means +1% max HP per second on top of the
#                             baseline). Read via get_effective_modifier so
#                             low-ilvl regen gear scales down as the player
#                             outlevels it, like every other power stat.
#   regen_delay_reduction   — subtracts from HP_REGEN_DELAY (seconds). At
#                             5s base, a +2 reduction means regen kicks in
#                             after 3s out of combat instead of 5.
const HP_REGEN_DELAY := 5.0
# Radius for the "any aggro'd enemy nearby" check that gates regen. Slightly
# larger than enemy AGGRO_RANGE (10m) so an enemy that just aggro'd from the
# edge of its detection range still counts as combat for the player.
const COMBAT_PROXIMITY_RADIUS := 12.0
const HP_REGEN_BASE_PCT := 10.0
const HP_REGEN_MIN_DELAY := 0.5
# Movement multiplier while holding the Active Shield (SHIELD_HOLD).
# 20% — the player is essentially planted; the trade is full damage
# block + still being able to attack. SHIELD_BUFF doesn't apply.
const STAND_HEIGHT := 1.6
const CROUCH_HEIGHT := 0.9
# Aim laser — thin red line painted during AIM_HOLD (Sniper Aimed Shot,
# LMG Tripod). Same technique as the Exile curse laser in enemy_afflictions.
const AIM_LASER_RADIUS: float = 0.003
const AIM_LASER_COLOR: Color = Color(1.0, 0.15, 0.15, 0.2)
const AIM_LASER_EMISSION: Color = Color(1.0, 0.25, 0.25, 1.0)
const AIM_LASER_EMISSION_ENERGY: float = 0.5
const AIM_LASER_PLAYER_OFFSET: Vector3 = Vector3(0.0, 1.0, 0.0)
const GRAVITY := CombatConstants.GRAVITY
const JUMP_VELOCITY := 6.5

# Body rotation rates. Aim turns are snappier so kiting stays responsive.
const TURN_RATE_MOVE := 12.0  # rad/s — ~130 ms for a 90° turn
const TURN_RATE_AIM := 30.0   # rad/s — near-instant when an attack is held
# Velocity threshold below which we don't repoint at the velocity vector,
# so the player keeps their facing during a coast-to-stop instead of yanking
# back to the last input direction.
const FACE_BY_VELOCITY_MIN := 0.5
# Scales the run animation playback rate so foot-plants align with the
# distance-based footstep SFX cadence. At move_speed 6.0 and
# FOOTSTEP_DISTANCE 1.4, a step fires every ~0.23s — so we need the jog
# cycle (~1s source clip, 2 contacts) to complete in ~0.47s → factor ~2.6.
# Tune by eye: feet should plant cleanly with no slide at full sprint.
#
# Reset to 1.0 for Mixamo xbot/fast_run: the source clip is already authored
# at a brisk cadence matched to ~6 m/s travel, so the old 1.8 (tuned for the
# slower Quaternius Jog_Fwd) made feet shuffle visibly. Sprint still ramps
# via SPRINT_SPEED_FACTOR on top of this base.
const RUN_ANIM_SPEED_MIN := 0.4
const RUN_ANIM_SPEED_MAX := 2.0

# Final multiplier on the computed playback rate (actual / authored).
# Single knob to dial overall locomotion-anim tempo — lower reads as
# slower / more deliberate legs at every travel speed, higher reads as
# more frantic. Adjust this rather than the per-clip authored values
# when you want a global feel change; tune _CLIP_AUTHORED_SPEED entries
# only when ONE clip's feet specifically drift relative to the rest.
const LOCOMOTION_ANIM_SPEED_FACTOR: float = 0.65

# Each locomotion clip's authored ground-travel rate in m/s. The picker
# divides actual horizontal velocity by this number to get the
# playback-rate multiplier that makes the feet visibly match real
# travel — slower while a debuff caps speed, faster while sprinting.
# Tune by eye if a clip's feet slide: speed_scale = actual / authored,
# so raise the value if feet move TOO FAST at full speed, lower if too
# slow. Default for unknown clips falls back to the player's full
# move_speed (assume "authored for ~the same speed as the player").
const _CLIP_AUTHORED_SPEED: Dictionary = {
	&"xbot/jog": 3.5,
	&"xbot/fast_run": 6.0,
	&"xbot/walk_back": 1.8,
	&"xbot/strafe_left": 3.0,
	&"xbot/strafe_right": 3.0,
	&"xbot/crouch_move": 2.0,
	# Per-class run clips share Mixamo's run-pack cadence — same authored
	# speed as the generic jog.
	&"xbot/pistol_run": 3.5,
	&"xbot/rifle_run": 3.5,
	&"xbot/sword_run": 3.5,
	&"xbot/axe_run": 3.5,
}

## Base ground-travel speed in m/s. 4.0 reads as a brisk jog and lines
## up with Mixamo's authored locomotion clip speeds (jog ~3.5 m/s,
## strafe ~3 m/s, walk_back ~1.8 m/s) so the per-clip authored-speed
## table in _CLIP_AUTHORED_SPEED produces playback rates close to 1.0×
## under normal travel — feet plant cleanly without sliding. Sprint
## multiplies on top via SPRINT_SPEED_FACTOR.
@export var move_speed: float = 4.0
@export var accel: float = 30.0
@export var max_health: int = 100
@export var skills: Array[Skill] = []
@export var resource_pool: ResourcePool

@onready var visual: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/Character/AnimationPlayer
@onready var _collision: CollisionShape3D = $Collision

const FLASHLIGHT_OFFSET := Vector3(0, 1.4, -0.3)
## Render layer used by the player visual so equipped lights can exclude
## it from their shadow_cull_mask (player still lit, just no self-shadow).
const PLAYER_VISUAL_LAYER := 2
const FPS_HEAD_OFFSET := Vector3(0.0, 1.55, 0.0)
const FPS_CROUCH_OFFSET := Vector3(0.0, 0.75, 0.0)
const FPS_PITCH_LIMIT := 1.4
const CROSSHAIR_ARM := 8.0
const CROSSHAIR_GAP := 3.0
const CROSSHAIR_THICK := 1.5
const FPS_FILL_COLOR := Color(0.5, 0.55, 0.62)
const FPS_FILL_ENERGY := 1.2
const FPS_FILL_RANGE := 6.0
const FPS_FILL_ATTENUATION := 2.0
const INTERACT_ANIM_SPEED := 3.0     # legacy — kept for any unconverted call sites
const INTERACT_ANIM_DURATION := 0.6  # interact action timing — clip stretches to this
const FPS_HOVER_INTERVAL := 0.05
const FLASHLIGHT_MAX_PITCH_DEG := 82.0
const FLASHLIGHT_MAX_UP_DEG := 10.0
# Cursor distance at which the beam fully levels off (and begins tilting up).
const FLASHLIGHT_LEVEL_DISTANCE := 9.0
# How far above the flashlight the beam targets at max cursor distance. This is
# what tilts the beam slightly above horizontal at the far end.
const FLASHLIGHT_OVER_LIFT := 0.8

var class_id: StringName = &""
var spec_id: StringName = &""
## For remote (non-authority) peers in MP, this stores the gender published
## by that peer via Steam lobby member data. PlayersContainer sets it
## before add_child so _apply_gender_appearance can pick the right mesh
## without consulting the LOCAL PlayerState.gender (which would always
## be the local player's gender, not the remote's). Empty string means
## "use PlayerState.gender" — the SP / authority path.
var remote_gender: StringName = &""
## Companion to remote_gender for the class identity. PlayersContainer
## reads this from Steam lobby member data (GameplayChatState's CLASS_KEY)
## before add_child. Empty string falls back to the local PlayerState.spec_id
## / class_id, which is correct in SP / for the authority peer.
var remote_class_id: StringName = &""
var _base_mat: StandardMaterial3D = null
var _combat: PlayerCombat
var _camera: Camera3D
var _health: int
var _alive: bool = true
# Most recent death-cause tag. Set by environmental kill paths (pit, future
# DoT/explosion variants) just before take_damage; consumed by the death
# screen to pick a snarky message. Empty = generic combat death.
var _death_cause: StringName = &""
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0

# Melee lunge — for blades only. Player slides toward the closest
# enemy near the cursor on attack press, syncing arrival with the
# swing's impact frame. Same velocity-injection pattern as knockback,
# so move_and_slide handles walls; quadratic ease-out coasts to a
# stop instead of snapping.
var _lunge_vel: Vector3 = Vector3.ZERO
var _lunge_remain: float = 0.0
var _lunge_duration: float = 0.0
const BLADE_LUNGE_SEARCH_RADIUS: float = 4.5    # how close enemy must be to cursor
const BLADE_LUNGE_MAX_DISTANCE: float = 4.0     # cap on how far the player slides
const BLADE_LUNGE_STOP_GAP: float = 1.4         # gap left to the target enemy
const BLADE_LUNGE_MIN_DISTANCE: float = 0.35    # below this, skip the lunge
# Independent busy flags for the two firing paths so LMB-hold and RMB-hold
# can interleave. Movement halt and facing gate on EITHER being true (any
# active commit window stops the player), but each input path only blocks
# its OWN re-entry — RMB cast can still fire while LMB is mid-windup, and
# vice versa.
var _lmb_busy: bool = false
var _skill_busy: bool = false

# Fire-cancellation counter. Every new LMB / RMB / skill press bumps
# this once. Each scheduled-fire (LMB multi-arm timer, RMB await,
# melee impact-frame timer) captures the generation at press time
# and checks it before firing damage / SFX / resolve. If a newer
# press has bumped the counter, the older fire silently returns —
# cancels in-flight LMB damage when RMB takes over, and vice versa.
# Multi-arm LMB shots from the SAME press share the same generation,
# so they all fire correctly together.
var _fire_generation: int = 0


# True while any attack is in its commit window. Used by FACING logic
# (skip the auto-face-forward branch so the cast's explicit aim wins)
# regardless of which input started it. NOT used as a movement freeze
# directly — see _attack_locks_movement() for that.
func _is_attack_committed() -> bool:
	return _lmb_busy or _skill_busy


# True only when the current attack should FREEZE the player in place.
# Melee swings + skill casts lock movement so the strike anchors at a
# committed position; ranged LMB fire does NOT lock — the player runs
# and guns. Without this carve-out, laser_shot (wind_up 0.1s) and
# plasma_bolt (wind_up 0.15s) stuttered the player every shot because
# the wind-up timer kept _lmb_busy=true and the movement gate at
# _physics_process zeroed velocity for that whole window. SMG/LMG/
# sniper/shotgun avoided the bug only because they have wind_up=0,
# so _lmb_busy clears within one physics frame.
func _attack_locks_movement() -> bool:
	# Skill casts (RMB / hotkey skills) lock as before — they're animation-
	# driven gestures (grenade throw, melee finisher, shield raise) where
	# the player committing in place reads correctly.
	if _skill_busy:
		return true
	# LMB-busy: only lock for melee weapons + bare hands. Energy ranged
	# (laser/plasma) and kinetic ranged (smg/lmg/sniper/shotgun) all
	# leave the player free to move.
	if _lmb_busy:
		var weapon: Item = InventoryState.get_equipped(&"weapon")
		if weapon == null:
			return true  # bare hands → unarmed strike, anchor in place
		# Melee weapons no longer freeze movement: the swing plays on the
		# upper body via UpperBodyAimModifier (see _swing_overlay_if_moving)
		# while the legs keep locomoting, so you can move while swinging.
		return false
	return false
var _attack_aim: Vector3 = Vector3.ZERO
var _click_consumed: bool = false
# Auto-aim target while LMB is held over an enemy. Cleared on release, on
# target death/pooling, or in FPS mode. Drives _aim_direction when set.
var _lock_target: Node3D = null
# Click-to-walk-to-interact target. Set when the player LMB-clicks an
# out-of-range hovered interactable; the movement loop synthesises a
# wish_dir toward this node each tick until INTERACT_RANGE_SQ is met,
# then fires the interact and clears the target. Cancelled by manual
# WASD input, target invalidation, or a fresh click on something else.
var _walk_to_interact_target: Node3D = null

var _shield: PlayerShield
var _grenade: PlayerGrenade
var _recovery: PlayerRecovery

var _attack_weapon: Item = null

# ── Melee 3-hit combo ───────────────────────────────────────────────────────
# Tracks where in the 3-step swing chain the player currently is. Reset to 0
# on idle (no melee swing for MELEE_COMBO_RESET_TIME seconds), weapon swap,
# or weapon-archetype change. PlayerCombat reads this in _resolve_cone to
# scale cone width / damage / knockback / 3rd-hit status (bleed for 1H,
# stun for 2H). Hits 0/1/2 represent swing 1/2/3 of the chain.
# Was 1.5 — but with the slower base swing cadence (cooldown / atk_spd
# can exceed 2s on the heaviest rolls), every swing's elapsed time hit
# the reset window before the next click landed, so the combo never
# advanced past step 0. 2.8 leaves room for full-slow rolls while
# still resetting after a real idle pause.
const MELEE_COMBO_RESET_TIME: float = 2.8
const MELEE_BASE_IDS: Array[StringName] = [&"melee_1h", &"melee_2h"]

# Fraction-through-the-swing where each melee clip's visible impact
# frame actually lands. Damage + SFX fire at `melee_interval * this`,
# so dialling per-weapon syncs the visible hit moment with the
# resolved damage.
#  - melee_1h: the registered "sword_slash" keys actually load the
#    "sword and shield attack" clips (commit 22b07a7 swap), which
#    begin with the strong sweep motion. Visible strike at ~15% of
#    the clip — firing damage at 50% left a ~0.25s desync where the
#    player saw the hit land before the audio + damage ever fired.
#  - melee_2h: axe_combo clips peak ~mid-swing, impact ~30% feels
#    natural with a short follow-through.
## Per-(base_id, combo_step) damage-frame ratio. The combo uses DIFFERENT
## clips per step (sword_slash / sword_slash_2 / sword_slash_3), and
## each clip's visible blade-contact frame lands at a different fraction
## of its duration. A single ratio per weapon left step 0 desynced
## while step 1/2 looked right.
##
## Ratios are read as `melee_interval * ratio` where melee_interval =
## skill.cooldown / atk_spd, so any change to weapon attack_speed
## scales the anim duration AND the impact timing together — sync
## holds across all weapon-speed rolls automatically.
# Cap on the stretched-anim duration for melee SKILL casts (RMB
# specials like AoE Burst). Without it, skill_dur = cooldown / atk_spd
# can blow out to 4-5s on slow weapons with high skill cooldowns —
# the AoE Burst (cooldown 1.0 / atk_spd 0.35) would otherwise play
# the swing animation across 2.86s, which feels disconnected from
# the VFX impact regardless of impact_ratio. Cooldown itself is
# untouched — it still gates the next cast. Only the visual swing
# window + the damage-fire delay are capped.
const MELEE_SKILL_MAX_ANIM_DUR: float = 1.2


const _MELEE_IMPACT_RATIO_PER_STEP: Dictionary = {
	# Step 0 pulled 0.55 → 0.35 — user reports the first swing's VFX/
	# damage was firing ~0.25s after the visible blade contact. The
	# sword_slash clip's actual strike frame is much closer to 1/3 of
	# the way through than to mid-swing; the previous 0.5+ values were
	# tuned against a slower clip read that doesn't match this anim.
	# Sync is preserved across weapon-speed rolls automatically because
	# impact_time = swing_duration × ratio.
	&"melee_1h": [0.35, 0.5, 0.5],
	# 2H sledgehammer: tuned to land just AFTER the visible contact
	# frame. axe_swing's native impact is ~40% of the clip; with the
	# 0.8 duration multiplier below, visual contact lands at 0.32 of
	# main_interval (0.4 × 0.8). 0.35 puts the damage tick a beat
	# after the sledge sweeps through — VFX trails the hammer rather
	# than firing before / on top of it. Damage timer is independent
	# of anim duration so this stays correct regardless of player
	# attack_speed roll.
	&"melee_2h": [0.35, 0.35, 0.35],
}

# Multiplier on the duration passed to _play_anim_stretched for the
# named weapon class. <1.0 = play the anim faster (compressed into
# fewer seconds). melee_2h plays at 1/0.8 = 1.25× native rate so the
# sledgehammer arc reads as the heavy-but-decisive swing the weapon
# is supposed to feel like, rather than the over-stretched float that
# main_interval alone produced at high attack_speed rolls.
const _MELEE_ANIM_DURATION_MULT: Dictionary = {
	&"melee_2h": 0.8,
}


func _melee_impact_ratio(base_id: StringName, combo_step: int = 0) -> float:
	var arr: Array = _MELEE_IMPACT_RATIO_PER_STEP.get(base_id, [0.5])
	if arr.is_empty():
		return 0.5
	var i: int = clampi(combo_step, 0, arr.size() - 1)
	return float(arr[i])
var _melee_combo_step: int = 0
var _melee_combo_last_t: float = -1000.0
var _melee_combo_last_weapon_id: StringName = &""


## Advances the melee combo step for the given weapon and returns the
## new step (0/1/2). Resets to 0 on timeout, weapon swap, or non-melee
## weapon. PlayerCombat calls this once per melee SINGLE_CONE cast at
## the top of resolve_skill_hit; multistrike repeats within that same
## cast all share the returned step.
func advance_melee_combo(weapon: Item) -> int:
	if weapon == null or not (weapon.weapon_base_id in MELEE_BASE_IDS):
		_melee_combo_step = 0
		_melee_combo_last_weapon_id = &""
		return 0
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - _melee_combo_last_t
	# Continuation: same weapon archetype within timeout → next step.
	# Otherwise: reset to step 0 and start fresh.
	if elapsed <= MELEE_COMBO_RESET_TIME and weapon.weapon_base_id == _melee_combo_last_weapon_id:
		_melee_combo_step = (_melee_combo_step + 1) % 3
	else:
		_melee_combo_step = 0
	_melee_combo_last_t = now
	_melee_combo_last_weapon_id = weapon.weapon_base_id
	return _melee_combo_step


## Returns what advance_melee_combo WOULD set on the next call,
## without mutating state. The anim picker reads this so the swing
## that's about to play matches the combo step PlayerCombat will
## resolve a moment later (combat advances the step inside
## resolve_skill_hit, AFTER the anim already started). Without the
## peek, the visual would lag combat by one swing.
func peek_next_melee_combo_step(weapon: Item) -> int:
	if weapon == null or not (weapon.weapon_base_id in MELEE_BASE_IDS):
		return 0
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - _melee_combo_last_t
	if elapsed <= MELEE_COMBO_RESET_TIME and weapon.weapon_base_id == _melee_combo_last_weapon_id:
		return (_melee_combo_step + 1) % 3
	return 0


## Read-only accessor for the current combo step. Multistrike repeats
## within a single cast all read this value so the visual + status
## stay consistent across the multistrike loop.
func melee_combo_step() -> int:
	return _melee_combo_step


# Hitstop — brief animation freeze when a melee swing connects with
# any enemy. Sells the "weight" of the hit. Per-player (anim_player.
# speed_scale, not Engine.time_scale), so MP-safe: each peer's hitstop
# fires on their own avatar's hits independently. Resets via timer.
const MELEE_HITSTOP_DURATION: float = 0.06
var _hitstop_remain: float = 0.0
var _hitstop_prev_speed_scale: float = 1.0


func trigger_melee_hitstop() -> void:
	if anim_player == null or _hitstop_remain > 0.0:
		return
	_hitstop_prev_speed_scale = anim_player.speed_scale
	anim_player.speed_scale = 0.0
	_hitstop_remain = MELEE_HITSTOP_DURATION
	get_tree().create_timer(MELEE_HITSTOP_DURATION).timeout.connect(_release_melee_hitstop)


func _release_melee_hitstop() -> void:
	_hitstop_remain = 0.0
	if anim_player != null:
		anim_player.speed_scale = _hitstop_prev_speed_scale


# ── Per-archetype signature-quirk trackers ──────────────────────────────────
# State for the per-weapon quirks that need shot-counting / stacks /
# timestamps. PlayerCombat reads these in damage paths to apply the
# right multiplier or follow-up effect.

# LMG "Heat" — sustained fire stacks a damage bonus that decays after
# 1s of no LMG fire. Each shot adds 1 stack, capped at LMG_HEAT_MAX.
const LMG_HEAT_DECAY_TIME: float = 1.0
const LMG_HEAT_MAX_STACKS: int = 3
const LMG_HEAT_PCT_PER_STACK: float = 0.10
var _lmg_heat_stacks: int = 0
var _lmg_heat_last_fire_t: float = -1000.0

# Accelerator "Resonance" — time-based damage ramp while channeling.
# Multiplier lerps from 1.0× at channel start to ACCEL_RAMP_MAX_MULT
# over ACCEL_RAMP_DURATION seconds, then sustains at peak. Resets to
# 0 when the channel ends, so a fresh tap restarts the ramp.
#
# Old system was stack-based (+5% per damage tick, cap +30%): too
# shallow to feel meaningful and reached cap in <1s. The new ramp is
# slower to build but pays off heavily for sustained channels, which
# is the fantasy of the weapon — "wind-up beam that melts whatever
# stays in front of it."
const ACCEL_RAMP_DURATION: float = 2.5
const ACCEL_RAMP_MAX_MULT: float = 1.8
var _accel_channel_elapsed: float = 0.0
# World-space resonance bar — sits under the player like a cast bar.
var _resonance_bar: MeshInstance3D = null
var _resonance_label: Label3D = null
const _RESONANCE_BAR_Y: float = -0.1
const _RESONANCE_BAR_SCALE := Vector3(1.0, 0.08, 1.0)
const _RESONANCE_COLOR_LOW := Color(0.9, 0.5, 0.15, 0.9)
const _RESONANCE_COLOR_FULL := Color(1.0, 0.95, 0.4, 1.0)

# SMG "Penetration" — every Nth SMG shot deals 2× damage. Counter
# advances on each SMG bullet spawn; the Nth shot's damage roll is
# pre-multiplied at projectile spawn time.
const SMG_PENETRATION_INTERVAL: int = 5
const SMG_PENETRATION_MULT: float = 2.0
var _smg_shot_count: int = 0

# Laser pistol "Charged Shot" — first shot after >=1s of no laser fire
# deals 1.5×. Pure timestamp check; no stacks.
const LASER_CHARGED_IDLE_TIME: float = 1.0
const LASER_CHARGED_MULT: float = 1.5
var _laser_last_fire_t: float = -1000.0


# Returns the LMG heat multiplier and advances the stack counter.
# Stacks decay back to 0 once LMG_HEAT_DECAY_TIME has passed since the
# last LMG fire — i.e. sustained fire keeps stacks; pausing resets.
func consume_lmg_heat() -> float:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _lmg_heat_last_fire_t > LMG_HEAT_DECAY_TIME:
		_lmg_heat_stacks = 0
	_lmg_heat_stacks = mini(LMG_HEAT_MAX_STACKS, _lmg_heat_stacks + 1)
	_lmg_heat_last_fire_t = now
	var pct_per_stack := LMG_HEAT_PCT_PER_STACK
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	if weapon != null:
		var bonus: int = weapon.get_effective_modifier(&"sustained_bonus")
		if bonus > 0:
			pct_per_stack += float(bonus) * 0.01 / float(LMG_HEAT_MAX_STACKS)
	return 1.0 + pct_per_stack * float(_lmg_heat_stacks)


# Advance the channel ramp timer by `delta`. Called every frame from
# _tick_channel while the Accelerator is firing. Separate from the
# read accessor below so multiple damage rolls per tick (multistrike)
# don't accidentally double-advance the ramp.
func tick_accel_resonance(delta: float) -> void:
	_accel_channel_elapsed += delta


# Effective ramp duration accounting for the weapon's ramp_speed stat.
# ramp_speed of 50 means 50% faster ramp → duration ÷ 1.5.
func _effective_accel_ramp_duration() -> float:
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	if weapon != null:
		var ramp_pct: int = weapon.get_effective_modifier(&"ramp_speed")
		if ramp_pct > 0:
			return ACCEL_RAMP_DURATION / (1.0 + float(ramp_pct) * 0.01)
	return ACCEL_RAMP_DURATION


# Current damage multiplier for the channel ramp. Lerp from 1.0 to
# ACCEL_RAMP_MAX_MULT across the effective ramp duration seconds of
# sustained channel, clamped so post-peak ticks stay at the ceiling.
# Side-effect free — called from PlayerCombat._roll_skill_damage for
# every tick.
func accel_resonance_mult() -> float:
	var ratio: float = clampf(_accel_channel_elapsed / _effective_accel_ramp_duration(), 0.0, 1.0)
	return lerp(1.0, ACCEL_RAMP_MAX_MULT, ratio)


## 0–1 progress toward full ramp damage. Read by the HUD ramp indicator.
func accel_ramp_ratio() -> float:
	if _accel_channel_elapsed <= 0.0:
		return 0.0
	return clampf(_accel_channel_elapsed / _effective_accel_ramp_duration(), 0.0, 1.0)


## True when the accelerator channel is actively ramping.
func is_accel_ramping() -> bool:
	return _accel_channel_elapsed > 0.0


func reset_accel_resonance() -> void:
	_accel_channel_elapsed = 0.0
	_update_resonance_bar()


func _build_resonance_bar() -> void:
	var shader := load("res://scripts/prototype/health_bar.gdshader") as Shader
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter(&"back_color", Color(0.1, 0.1, 0.1, 0.6))
	mat.set_shader_parameter(&"fill_color", _RESONANCE_COLOR_LOW)
	mat.set_shader_parameter(&"border_color", Color(0.02, 0.03, 0.05, 1.0))
	mat.set_shader_parameter(&"border_thickness", 0.08)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.6, 0.12)
	mesh.material = mat
	_resonance_bar = MeshInstance3D.new()
	_resonance_bar.mesh = mesh
	_resonance_bar.position = Vector3(0.0, _RESONANCE_BAR_Y, 0.0)
	_resonance_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_resonance_bar.visible = false
	add_child(_resonance_bar)
	_resonance_label = Label3D.new()
	_resonance_label.text = "RESONANCE"
	_resonance_label.font_size = 32
	_resonance_label.pixel_size = 0.004
	_resonance_label.outline_size = 4
	_resonance_label.modulate = Color(1.0, 0.85, 0.5, 0.8)
	_resonance_label.outline_modulate = Color(0, 0, 0, 1)
	_resonance_label.position = Vector3(0.0, _RESONANCE_BAR_Y + 0.12, 0.0)
	_resonance_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_resonance_label.visible = false
	add_child(_resonance_label)


func _update_resonance_bar() -> void:
	if _resonance_bar == null:
		return
	var ramping := is_accel_ramping()
	_resonance_bar.visible = ramping
	if _resonance_label != null:
		_resonance_label.visible = ramping
	if not ramping:
		return
	var ratio: float = accel_ramp_ratio()
	_resonance_bar.set_instance_shader_parameter(&"fill_ratio", ratio)
	var color: Color = _RESONANCE_COLOR_LOW.lerp(_RESONANCE_COLOR_FULL, ratio)
	_resonance_bar.set_instance_shader_parameter(&"fill_color", color)


# Returns the SMG penetration multiplier for THIS shot and advances
# the counter. The 5th, 10th, 15th... shots return 2.0; everything
# else returns 1.0.
func consume_smg_penetration() -> float:
	_smg_shot_count += 1
	if _smg_shot_count % SMG_PENETRATION_INTERVAL == 0:
		return SMG_PENETRATION_MULT
	return 1.0


# Returns the laser charged-shot multiplier for THIS shot and stamps
# the timer. Bonus only fires on the first shot after >=1s idle.
func consume_laser_charged_shot() -> float:
	var now: float = Time.get_ticks_msec() / 1000.0
	var bonus: float = 1.0
	if now - _laser_last_fire_t >= LASER_CHARGED_IDLE_TIME:
		bonus = LASER_CHARGED_MULT
	_laser_last_fire_t = now
	return bonus


# Footstep emission tick — runs each frame for both local and remote
# player instances. Accumulates horizontal distance from the last
# emission point; when it exceeds FOOTSTEP_DISTANCE, spawn a puff at
# the player's feet and reset. The position-delta approach means
# remote peers' replicated positions naturally drive their puffs
# too — no replication needed.
func _tick_footsteps() -> void:
	var result := Footsteps.tick(self, _footstep_distance_accum, _footstep_last_pos,
		FOOTSTEP_DISTANCE, -30.0, true, true)
	_footstep_distance_accum = result[0]
	_footstep_last_pos = result[1]


# ── Hammer Wind-Up ──────────────────────────────────────────────────────────
# Tracks the player's "stillness" — once the player has been not-moving for
# HAMMER_WIND_UP_TIME seconds, the next 2H melee hit deals +75% damage.
# Consumed on hit (one-shot bonus, not per-target). Reset by any movement.
const HAMMER_WIND_UP_TIME: float = 1.0
var _hammer_wind_up_idle_t: float = 0.0
var _hammer_wind_up_ready: bool = false


# Called per physics frame from the player's tick. delta is per-frame time.
# Movement detected via _want_dir; any non-zero direction resets the idle
# accumulator. Once accumulator passes the threshold, ready flag flips on.
#
# Aim-hold skills that immobilize the player (LMG Tripod, Aimed Shot)
# zero _want_dir incidentally, so without this gate a Tripod-equipped
# LMG user would build hammer wind-up while holding RMB. Treat "idle by
# immobilization" as ineligible — wind-up is only meant to reward
# voluntary stillness, not forced stillness from a different weapon.
func _tick_hammer_wind_up(delta: float) -> void:
	if _want_dir.length_squared() > 0.01 or aim_hold_locks_movement():
		_hammer_wind_up_idle_t = 0.0
		_hammer_wind_up_ready = false
		return
	_hammer_wind_up_idle_t += delta
	if _hammer_wind_up_idle_t >= HAMMER_WIND_UP_TIME:
		_hammer_wind_up_ready = true


# Atomic check-and-clear for the wind-up bonus. PlayerCombat calls this
# at the start of each 2H melee swing; returns true once per qualifying
# swing, then resets to require a fresh idle window. This means a
# wind-up swing buffs ONE swing, not a continuous stream.
func consume_hammer_wind_up() -> bool:
	if not _hammer_wind_up_ready:
		return false
	_hammer_wind_up_ready = false
	_hammer_wind_up_idle_t = 0.0
	return true
var _want_dir: Vector3 = Vector3.ZERO
var _resource_current: float = 0.0
var _resource_last_int: int = 0
var _credits: int = 0
var _death_tween: Tween
var _hit_flash_tween: Tween
var _telekinesis: PlayerTelekinesis
var _doomsayer: PlayerDoomsayer
var _drone_swarm: PlayerDroneSwarm
var _ied: PlayerIED
var _spawn_position: Vector3 = Vector3.ZERO
# Could be a SpotLight3D (FLASHLIGHT / UV / SCANNER — directional, follows
# cursor) or an OmniLight3D (RADIANT — omnidirectional bubble around the
# player, no aiming). The aim/pitch helpers gate on `is SpotLight3D` so
# omni mods don't pick up cursor tracking.
var _equipped_light: Light3D
var _tactical_overlay: TacticalOverlay
var _anim_reverse: bool = false
var _light_on: bool = false
var _fps_mode: bool = false
var _fps_camera: Camera3D = null
var _fps_pitch: float = 0.0
var _fps_transitioning: bool = false
var _world_env: Environment = null
var _modal_nodes: Array[CanvasItem] = []
var _fps_fill_light: OmniLight3D = null
var _fade_rect: ColorRect = null
var _chromatic: ChromaticAberrationOverlay = null
var _retro_filter: RetroFilterOverlay = null
var _low_hp_warning: LowHpWarningOverlay = null
var _damage_flash: DamageFlashOverlay = null
var _death_glitch: DeathGlitchOverlay = null
# Replicated by the MultiplayerSynchronizer attached to player.tscn — the
# authority sets it from velocity each physics tick; remote peers read it
# to choose between idle and run animations. Other replicated state
# (global_position, Visual:rotation) the synchronizer pulls automatically.
var net_moving: bool = false
var _crouching: bool = false
var _sprinting: bool = false
## Time remaining on the regen penalty after emptying resource while sprinting.
var _sprint_regen_penalty: float = 0.0
var _is_airborne: bool = false
var _backing: bool = false
# Strafe-selection hysteresis state so the strafe/jog and left/right choice
# can't flip-flop frame-to-frame (which restarted the clip and read as a pause).
var _strafing: bool = false
var _strafe_right: bool = false
var _interacting: bool = false
# HOLD-mode fire pose flag — true while a non-looping fire anim has
# played through and is sitting on its last frame, waiting for the
# next shot. Set by _on_anim_finished; cleared on the next fire
# event (or when we restart fire-anim playback). See _play_fire_pose.
var _fire_pose_holding: bool = false
var _fps_hovered: Node3D = null
var _crosshair_root: Control = null
var _crosshair_bars: Array[ColorRect] = []
var _stand_test_shape: CapsuleShape3D = null
var _fps_hover_timer: float = 0.0
# Stat-driven HP tracking: base + level gains + stat bonus = max_health.
var _base_max_health: int = 100
var _level_hp_bonus: int = 0
# Base resource pool max before stat bonuses.
var _base_resource_max: int = 100
# Gear-aggregated combat bonuses — recomputed on equipment change.
# Bullet-weapon reload state. _reload_remain > 0 means the weapon is
# currently reloading (firing is gated). _reload_target tracks the slot
# that's being reloaded so a quick weapon swap mid-reload doesn't fill
# the wrong magazine. Cleared when a fresh reload starts on a different
# slot or the reload completes.
var _reload_remain: float = 0.0
var _reload_total: float = 0.0
var _reload_target: StringName = &""

# ── Behavior mod runtime state ──────────────────────────────────────────────
# Mods that ramp / time / arm need a small bit of player-side state. Keep
# the fields adjacent so all behavior-mod state lives in one block; the
# effects themselves dispatch through BehaviorModRegistry from the hooks
# that read these (take_damage / start_reload / move_speed compute /
# landing / _deal_damage).
# Pain Compiler (chest): set on take_damage to the rolled duration_sec.
# Decrements each physics tick; while > 0, outgoing damage gets the rolled
# multiplier and healing is suppressed.
var _pain_compiler_remain: float = 0.0
var _pain_compiler_mult: float = 1.0
# Shock Discharge (chest): armed when HP is above 30%, fires the pulse the
# frame HP crosses below the threshold; re-arms when the player heals back
# above. Prevents the pulse from firing repeatedly on every hit at low HP.
var _shock_discharge_armed: bool = true
# Recoil Soles (feet): peak height during the current airborne phase. Set
# at jump start, updated each physics frame while airborne, consumed +
# cleared at landing to compute fall distance for the shockwave.
var _airborne_peak_y: float = 0.0
# Recoil Soles trade: 1-second landed slow after every jump. Decrements
# each physics tick. Composes with the move-speed multipliers like the
# other slow factors.
var _recoil_landed_slow_remain: float = 0.0

# AIM_HOLD state — Tripod (LMG) and Aimed Shot (sniper) RMB-hold buffs.
# While active, the configured Skill drains resource per tick and applies
# its accuracy/crit bonuses to every shot fired. Releasing RMB or running
# the resource dry exits the hold.
var _aim_hold_skill: Skill = null
# True when an aim-hold skill (LMG Tripod) forced the player into a
# crouch posture. Cleared on _stop_aim_hold so we only uncrouch
# automatically if the hold was the reason the player was crouched —
# a manually-crouching player who triggers Tripod stays down after
# the hold ends until they release Ctrl themselves.
var _aim_hold_forced_crouch: bool = false
var _aim_laser: MeshInstance3D = null

# CHANNEL_BEAM state — Taser hold-tase, Accelerator stream. While the
# bound input is held, the skill's targeting_mode resolves on a fixed
# tick interval and resource drains continuously. Stops when the input
# releases, the resource pool empties, or the player dies.
var _channel_skill: Skill = null
var _channel_input_action: StringName = &""
var _channel_tick_accum: float = 0.0
# Hold-loop SFX player spawned in _start_channel for channel weapons
# (taser, accelerator); null otherwise. _stop_channel fades + frees it
# via WeaponSounds.stop_channel_loop, which tolerates null.
var _channel_hold_player: AudioStreamPlayer3D = null
# Cooldown after channel stops due to resource depletion. Prevents the
# instant start→stop→start stutter when LMB is still held but the pool
# is empty. Counts down each frame in _tick_channel; _start_channel
# refuses to begin while > 0.
const CHANNEL_DEPLETED_COOLDOWN := 0.5
var _channel_depleted_cd: float = 0.0
const GRUNT_COOLDOWN := 1.5
## Grunt only fires when the incoming hit clears this fraction of max HP.
## At 5% of a 100-HP base, that's 5 dmg — SMG/taser chip-ticks stay silent
## but a sniper round or a melee bruiser still reads as "ouch." Without
## the threshold the cooldown alone still spams during burst-heavy fights.
const GRUNT_DAMAGE_PCT_MIN := 0.05
var _grunt_cd: float = 0.0
# ── Footstep dust puffs ─────────────────────────────────────────────────────
# Position-based footstep emission. Each frame we accumulate the
# horizontal distance moved since the last puff; once it crosses
# FOOTSTEP_DISTANCE, we spawn a small puff at the player's feet and
# reset. Tracked PER PLAYER NODE (every PrototypePlayer instance has
# its own accumulator), so remote peers' avatars emit footsteps too
# as their replicated positions update — no RPC needed. Skipped when
# airborne or below the speed floor so jumping / standing-still
# doesn't dribble puffs.
const FOOTSTEP_DISTANCE: float = 1.7
# Target move speed this frame (after all modifiers). Written by the
# movement block, read by the animation block to keep legs pumping at
# the intended cadence rather than dipping during accel ramps.
var _target_move_speed: float = 0.0
const FOOTSTEP_MIN_SPEED_SQR: float = 0.04  # ignore micro-jitter from sync
var _footstep_distance_accum: float = 0.0
var _footstep_last_pos: Vector3 = Vector3.ZERO



# Flame visual for SINGLE_CONE CHANNEL_BEAM weapons (Energy Accelerator).
# Pivot Node3D parented to the player at chest height — yawed each tick
# to face aim. Cylinder MeshInstance3D under the pivot runs the
# jet_flame.gdshader. Created lazily on first channel start; hidden
# between casts so the shader's noise time uniform stays warm.
var _flame_visual: Node3D = null
var _flame_material: ShaderMaterial = null
var _gear_damage_reduction: float = 0.0
var _gear_move_speed_bonus: int = 0
var _gear_base_damage_bonus: int = 0
var _gear_crit_chance_bonus: float = 0.0
var _gear_attack_speed_bonus: float = 0.0
var _gear_hit_chance_bonus: float = 0.0
var _gear_cooldown_reduction: float = 0.0
var _gear_hp_regen_bonus: float = 0.0
var _gear_regen_delay_reduction: float = 0.0
var _gear_life_on_kill: int = 0
var _gear_barrier_on_kill: int = 0
var _barrier: int = 0
var _barrier_max: int = 0
var _barrier_decay_timer: float = 0.0
const BARRIER_DECAY_DELAY := 4.0
const BARRIER_DECAY_RATE := 15
# Time since the player was last hit. Counts up each frame; HP regen kicks
# in once it crosses (HP_REGEN_DELAY - regen_delay_reduction). Reset by
# take_damage().
var _out_of_combat_t: float = HP_REGEN_DELAY
# Sub-integer accumulator so % regen produces the right value at any frame
# rate — flushed to _health when it crosses 1.0. Without this, a 4%/sec
# tick at 60fps produces 0 (rounded) every frame and HP never climbs.
var _hp_regen_accum: float = 0.0

func _ready() -> void:
	# Non-authority players on this client (remote peers' avatars in MP)
	# get a minimal setup — no combat, no abilities, no overlays.
	# Position + facing come via MultiplayerSynchronizer; animations
	# come from net_moving + _update_remote_anim() in _physics_process.
	# In SP we explicitly skip the authority check — Godot's
	# is_multiplayer_authority() returns false with no peer (default
	# authority 1, unique_id 0), which would incorrectly route the
	# baked-scene player down the remote path.
	if _is_remote_player():
		_ready_remote()
		return
	_combat = PlayerCombat.new()
	_combat.setup(self)
	add_child(_combat)
	_telekinesis = PlayerTelekinesis.new()
	_telekinesis.setup(self)
	add_child(_telekinesis)
	_camera = get_viewport().get_camera_3d()
	_fps_camera = Camera3D.new()
	_fps_camera.position = FPS_HEAD_OFFSET
	_fps_camera.current = false
	_fps_camera.far = _camera.far if _camera != null else 1000.0
	add_child(_fps_camera)
	_fps_fill_light = OmniLight3D.new()
	_fps_fill_light.light_color = FPS_FILL_COLOR
	_fps_fill_light.light_energy = FPS_FILL_ENERGY
	_fps_fill_light.omni_range = FPS_FILL_RANGE
	_fps_fill_light.omni_attenuation = FPS_FILL_ATTENUATION
	_fps_fill_light.shadow_enabled = false
	_fps_fill_light.light_volumetric_fog_energy = 0.0
	_fps_fill_light.visible = false
	_fps_camera.add_child(_fps_fill_light)
	var _fade_canvas := CanvasLayer.new()
	_fade_canvas.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_canvas.add_child(_fade_rect)
	add_child(_fade_canvas)
	_chromatic = ChromaticAberrationOverlay.new()
	add_child(_chromatic)
	# Added after chromatic so its shader samples the chromatic-aberrated
	# screen — both live on CanvasLayer 0, tree order picks the order.
	_retro_filter = RetroFilterOverlay.new()
	add_child(_retro_filter)
	# Real-game warning overlays. setup() before add_child so health_changed
	# is connected before any initial emissions.
	_low_hp_warning = LowHpWarningOverlay.new()
	_low_hp_warning.setup(self)
	add_child(_low_hp_warning)
	_damage_flash = DamageFlashOverlay.new()
	add_child(_damage_flash)
	_death_glitch = DeathGlitchOverlay.new()
	_death_glitch.setup(self)
	add_child(_death_glitch)
	add_to_group(&"player")
	add_to_group(&"world_item_dropper")
	SpatialGrid.register(self, &"player")
	class_id = PlayerState.class_id
	spec_id = PlayerState.spec_id
	PlayerState.leveled_up.connect(_on_player_leveled_up)
	# Local-class swap: when the user picks a different class/spec via the
	# talents menu, PlayerState fires class_changed / spec_changed. Refresh
	# the cached IDs + the visual mesh. Remote peers use refresh_remote_class
	# instead (driven from PlayersContainer's lobby_data_update listener).
	PlayerState.class_changed.connect(_on_local_class_or_spec_changed)
	PlayerState.spec_changed.connect(_on_local_class_or_spec_changed)
	_drone_swarm = PlayerDroneSwarm.new()
	_drone_swarm.setup(self)
	add_child(_drone_swarm)
	_ied = PlayerIED.new()
	_ied.setup(self)
	add_child(_ied)
	PerkState.perks_changed.connect(_drone_swarm.reconcile)
	_doomsayer = PlayerDoomsayer.new()
	_doomsayer.setup(self)
	add_child(_doomsayer)
	_shield = PlayerShield.new()
	_shield.setup(self)
	add_child(_shield)
	_build_shield_visual()
	shield_buff_changed.connect(_on_shield_buff_changed_visual)
	_grenade = PlayerGrenade.new()
	_grenade.setup(self)
	add_child(_grenade)
	_recovery = PlayerRecovery.new()
	_recovery.setup(self)
	_recovery.sync_consumable()
	add_child(_recovery)
	_build_resonance_bar()
	PerkState.perks_changed.connect(_doomsayer.reconcile)
	# Gender-correct mesh swap must happen before the visual-layer pass and
	# before anim_player wiring — the swap re-resolves anim_player and the
	# subsequent calls operate on the new subtree.
	_apply_gender_appearance()
	# Put player meshes on an extra render layer so equipped lights can
	# exclude it from shadow casting (no self-shadow under own flashlight,
	# and no self-shadow under the omni-directional Radiant lamp).
	if visual != null:
		_apply_player_visual_layer_recursive(visual)
	_base_max_health = max_health
	if resource_pool != null:
		_base_resource_max = resource_pool.max_value
	_recompute_stat_bonuses()
	_health = max_health
	_ensure_loop(ANIM_IDLE)
	_ensure_loop(ANIM_RUN)
	_ensure_loop(ANIM_WALK_BACK)
	_ensure_loop(ANIM_CROUCH_IDLE)
	_ensure_loop(ANIM_CROUCH_MOVE)
	_ensure_loop(ANIM_JUMP_AIR)
	# LMB-hold fire poses MUST loop — when the clip finishes,
	# is_playing flips false, and the per-tick picker's "same anim
	# already playing" early-out fails, so it calls anim_player.play
	# again and restarts the clip from frame 0 (visible hitch / re-
	# starting motion). Memory: project_looping_anim_hold.
	_ensure_loop(ANIM_FIRE)
	_ensure_loop(ANIM_FIRE_MOVE)
	# Pistol-specific fire pose. fire_anim_for_class falls back to
	# ANIM_FIRE for non-pistol classes, so xbot/fire above covers
	# rifle/smg/shotgun/etc.
	_ensure_loop(XBotAnimations.fire_anim_for_class(&"pistol"))
	if anim_player != null:
		anim_player.animation_finished.connect(_on_anim_finished)
	_play_anim(ANIM_IDLE)
	_apply_class_appearance()
	_build_light_mount()
	# Walk up the ancestor chain looking for the WorldEnvironment sibling.
	# Pre-MP refactor the player was a direct child of LevelShell so
	# get_parent() worked; now players sit under PlayersContainer, so the
	# WorldEnvironment is the player's GRANDPARENT's child.
	var ancestor: Node = get_parent()
	while ancestor != null and _world_env == null:
		var we_node := ancestor.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
		if we_node != null:
			_world_env = we_node.environment
			break
		ancestor = ancestor.get_parent()
	if resource_pool != null:
		_resource_current = float(resource_pool.start_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)
	_apply_saved_state()
	_apply_debug_overrides()
	_spawn_position = global_position
	_build_crosshair()
	_stand_test_shape = CapsuleShape3D.new()
	_stand_test_shape.radius = 0.4
	# Probe only the slab ABOVE the crouch capsule — the volume that
	# needs to be clear for the player to stand. Probing the full
	# stand-height capsule would catch the floor under the player every
	# tick (bottom hemisphere reaches y=0) and lock crouch on. Mirrors
	# the enemy's CROUCH_PROBE_HEIGHT pattern.
	_stand_test_shape.height = STAND_HEIGHT - CROUCH_HEIGHT
	_build_stat_vfx()
	_drone_swarm.reconcile()
	_doomsayer.reconcile()


# Mirrors prototype_hud.gd's disconnect pattern. Autoload signals
# (PlayerState / PerkState / InventoryState) live beyond the player
# node, so we must unwire them on tree exit to prevent stale callbacks
# firing into freed lambdas / methods. is_connected guards each
# disconnect so the remote-player path (which only connects a subset
# of these) doesn't error on signals it never wired.
#
# Skipped intentionally: signals on owned descendants (anim_player,
# shield_buff_changed, screen.continue_pressed) — those nodes are
# freed with this one, so their connections evaporate. Timer.timeout
# lambdas also skipped — one-shot timers + CONNECT_ONE_SHOT.
func _exit_tree() -> void:
	if PlayerState.leveled_up.is_connected(_on_player_leveled_up):
		PlayerState.leveled_up.disconnect(_on_player_leveled_up)
	if PlayerState.class_changed.is_connected(_on_local_class_or_spec_changed):
		PlayerState.class_changed.disconnect(_on_local_class_or_spec_changed)
	if PlayerState.spec_changed.is_connected(_on_local_class_or_spec_changed):
		PlayerState.spec_changed.disconnect(_on_local_class_or_spec_changed)
	if _drone_swarm != null and is_instance_valid(_drone_swarm) \
			and PerkState.perks_changed.is_connected(_drone_swarm.reconcile):
		PerkState.perks_changed.disconnect(_drone_swarm.reconcile)
	if _doomsayer != null and is_instance_valid(_doomsayer) \
			and PerkState.perks_changed.is_connected(_doomsayer.reconcile):
		PerkState.perks_changed.disconnect(_doomsayer.reconcile)
	if InventoryState.equipment_changed.is_connected(_on_equipment_changed):
		InventoryState.equipment_changed.disconnect(_on_equipment_changed)
	if InventoryState.items_overflowed.is_connected(_on_items_overflowed):
		InventoryState.items_overflowed.disconnect(_on_items_overflowed)


# Minimal _ready path for non-authority remote players. Only sets up the
# visual side (animation player wiring, mesh shadow layers) — the rest of
# the player's behavior is intentionally inert because it's driven by
# the authority on another peer.
func _ready_remote() -> void:
	# remote_gender must be set by PlayersContainer before add_child for
	# the swap to pick the right mesh. If it's still empty here (a remote
	# spawned before gender lobby data was replicated), apply_gender will
	# fall back to PlayerState.gender, and a later refresh_gender() call
	# from PlayersContainer's lobby_data_update listener will swap.
	_apply_gender_appearance()
	if anim_player != null:
		XBotAnimations.install_on(anim_player)
	_ensure_loop(ANIM_IDLE)
	_ensure_loop(ANIM_RUN)
	_ensure_loop(ANIM_WALK_BACK)
	if anim_player != null:
		anim_player.animation_finished.connect(_on_anim_finished)
	_play_anim(ANIM_IDLE)
	# Same shadow-layer trick as the authority path so equipped lights
	# (added later, when we sync those) won't self-shadow on remotes.
	if visual != null:
		_apply_player_visual_layer_recursive(visual)
	add_to_group(&"remote_player")


func _apply_player_visual_layer_recursive(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers |= (1 << (PLAYER_VISUAL_LAYER - 1))
	for child in node.get_children():
		_apply_player_visual_layer_recursive(child)


# True when this Player instance represents another peer's avatar on
# the local client (full setup, input, combat all skipped). False in
# single-player and on the local peer's own avatar in multiplayer.
#
# Detection caveat: we can't gate on multiplayer.has_multiplayer_peer()
# because GodotSteam auto-binds a SteamMultiplayerPeer at Steam init —
# that flag is true even in SP. NetState.is_in_lobby() is the signal
# for "we're actually networked," and only when that's true do we
# care about authority routing.
func _is_remote_player() -> bool:
	if not NetState.is_in_lobby():
		return false
	return not is_multiplayer_authority()




# Drives idle / run animation on a non-authority remote player using the
# replicated `net_moving` flag. _play_anim is idempotent — already-playing
# animations don't restart — so calling this every physics tick is cheap.
func _update_remote_anim() -> void:
	if anim_player == null:
		return
	var wc := _equipped_weapon_class()
	if net_moving:
		_play_anim(XBotAnimations.run_anim_for_class(wc), 1.0, 0.15)
	else:
		_play_anim(XBotAnimations.idle_anim_for_class(wc), 1.0, 0.15)
	# Per-frame flame orientation update for remote channels — the start
	# RPC only latches the damage_type + range; the visual transform
	# tracks the remote player's facing direction every tick.
	if _remote_flame_active:
		_update_remote_flame_visual()


func _build_stat_vfx() -> void:
	if _base_mat == null or visual == null:
		return
	var controller := StatVFXController.new()
	add_child(controller)
	controller.setup(visual, _base_mat)

func _apply_class_appearance() -> void:
	# Was tinting the whole Visual subtree via material_override to give
	# the old flat-shaded Quaternius character a class color. The Mixamo
	# player Meshy character meshes carry authored PBR
	# textures we want visible, so we no longer override their materials.
	# _base_mat stays around for StatVFXController, which only uses it as
	# an emission scratch material.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UIThemeState.palette.player_color
	mat.metallic = 0.1
	mat.roughness = 0.6
	_base_mat = mat


## Public hook for PlayersContainer to call when Steam pushes a lobby data
## update for this peer (e.g. their gender was set after their Player node
## was already spawned). Re-runs the swap if the resolved gender no longer
## matches the current Character mesh.
func refresh_remote_gender(new_gender: StringName) -> void:
	if remote_gender == new_gender:
		return
	remote_gender = new_gender
	_apply_gender_appearance()


## Companion to refresh_remote_gender for the class identity. Called from
## PlayersContainer's lobby_data_update listener so a peer's mesh swaps if
## their published class_id changes after their Player was spawned.
func refresh_remote_class(new_class_id: StringName) -> void:
	if remote_class_id == new_class_id:
		return
	remote_class_id = new_class_id
	_apply_gender_appearance()


## Local-only: PlayerState.class_changed / spec_changed both route here.
## Refreshes the cached class/spec IDs (other systems read these locals
## instead of touching PlayerState every frame) then triggers the mesh
## swap. _apply_gender_appearance pulls the new values via
## _effective_class_id, so the mesh always matches the current PlayerState.
func _on_local_class_or_spec_changed(_id: StringName) -> void:
	class_id = PlayerState.class_id
	spec_id = PlayerState.spec_id
	_apply_gender_appearance()
	# Class-specific visuals (drone colors, etc.) also need to refresh
	# since the resolved class drives their identity.
	_apply_class_appearance()


# Resolves the effective class identity for mesh + appearance lookups.
# Remote peers in MP carry the value published by that peer through the
# gameplay lobby's CLASS_KEY (already most-specific: spec when specced,
# origin otherwise). Local / SP path returns spec_id when set, falling
# back to the origin class_id — same convention.
func _effective_class_id() -> StringName:
	if remote_class_id != &"":
		return remote_class_id
	if PlayerState.spec_id != &"":
		return PlayerState.spec_id
	return PlayerState.class_id


# Picks a PackedScene from _CHARACTER_MESHES for the given (class, gender).
# Every origin (analog / cyborg) and every spec (count / survivalist /
# enculted / forged / automaton / polymath) has a unique mesh, so a
# direct lookup hits in all valid cases. Defensive fallback through
# CLASS_DEFINITIONS.origin guards against an unexpected class_id (e.g.
# a corrupted save) — landing on the analog origin's mesh in that case.
func _mesh_for_class(class_id: StringName, gender: StringName) -> PackedScene:
	var gender_key: StringName = &"female" if gender == &"female" else &"male"
	if _CHARACTER_MESHES.has(class_id):
		return _CHARACTER_MESHES[class_id][gender_key]
	var def: Dictionary = AttributeState.CLASS_DEFINITIONS.get(class_id, {})
	var origin: StringName = def.get(&"origin", &"analog")
	return _CHARACTER_MESHES[origin][gender_key]


# Swaps the Visual/Character mesh to match the effective class + gender
# (local PlayerState OR the remote peer's published lobby data) and
# installs the X Bot animation library on the new AnimationPlayer. Mirrors
# the enemy's _apply_class_mesh pattern. Must run BEFORE anim_player.
# animation_finished is connected and BEFORE _play_anim(ANIM_IDLE) —
# otherwise the @onready anim_player still points at the freed FBX's
# AnimationPlayer.
func _apply_gender_appearance() -> void:
	if visual == null:
		return
	var effective_gender: StringName = remote_gender if remote_gender != &"" else PlayerState.gender
	var effective_class: StringName = _effective_class_id()
	var is_female: bool = effective_gender == &"female"
	var scene: PackedScene = _mesh_for_class(effective_class, effective_gender)
	# Per-gender Y offset to keep feet at floor level. Female meshes'
	# geometric origin sits ~0.20m above the feet. Male meshes were
	# clipping at y=0 — origin is BELOW the feet just enough that the
	# 1.02× scale (and a small import drift) put the feet below floor
	# level; +0.06 lifts them out of the floor without floating.
	var y_offset: float = 0.26 if is_female else 0.06
	# Meshy meshes import a touch smaller than the player capsule
	# expects. 1.05× over-corrected (feet clipped through floor),
	# 1.02× is the sweet spot — silhouette reads at iso distance
	# without pushing feet below the floor plane.
	var char_scale: float = 1.02
	var current_char := visual.get_node_or_null(^"Character") as Node3D
	if current_char == null or current_char.scene_file_path != scene.resource_path:
		if current_char != null:
			visual.remove_child(current_char)
			current_char.queue_free()
			# Invalidate the cached skeleton — the old one is on its
			# way out and the next _find_player_skeleton call will
			# re-resolve on the new Character subtree.
			_cached_skeleton = null
		var new_char := scene.instantiate() as Node3D
		if new_char != null:
			new_char.name = "Character"
			# Match the static tscn's 180° yaw — Mixamo FBX root faces the
			# opposite direction from what the Visual node's facing logic
			# expects.
			new_char.rotation.y = PI
			new_char.position.y = y_offset
			new_char.scale = Vector3.ONE * char_scale
			# Stash the resolved gender on the Character node so any helper
			# that walks up from the skeleton (notably WeaponAttachment, which
			# picks a per-gender grip table) can resolve the right variant
			# without consulting PlayerState — which would always return the
			# LOCAL player's gender, wrong for remote MP avatars.
			new_char.set_meta(&"gender", effective_gender)
			# Backfill grey for any surface whose material resolved to
			# null — Meshy FBXs whose post-import texture lookup failed
			# would otherwise spam "material_*: Parameter 'material' is
			# null" four times per surface per frame. Same fix the
			# enemy path uses (prototype_enemy.gd line ~694).
			XBotRagdoll.ensure_surface_materials(new_char)
			visual.add_child(new_char)
			# Meshy FBXs ship without baked animations, so the imported scene
			# has no AnimationPlayer node — create one before
			# XBotAnimations.install_on can populate it. Old Mixamo "Idle"
			# FBXs supplied their own AnimationPlayer; this branch covers the
			# new path uniformly.
			var new_ap := new_char.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if new_ap == null:
				new_ap = AnimationPlayer.new()
				new_ap.name = "AnimationPlayer"
				new_char.add_child(new_ap)
			anim_player = new_ap
	else:
		# No swap needed; just re-apply Y offset + scale in case the default
		# tscn instance was at 0/1 or the per-gender constants changed.
		current_char.position.y = y_offset
		current_char.scale = Vector3.ONE * char_scale
		current_char.set_meta(&"gender", effective_gender)
	if anim_player != null:
		XBotAnimations.install_on(anim_player)
	# Bake uniform scale into the FBX's intermediate Armature / Skeleton
	# nodes so any future PhysicalBone3D children Jolt builds inherit a
	# clean parent chain. Without this, Mixamo's per-axis scale residue
	# triggers Jolt _try_build_shape warnings — historically the source
	# of huge log spam during sessions with ragdoll deaths. The player
	# doesn't ragdoll today, but the visual layer pass and any future
	# physics body on the rig benefit equally.
	var skel := _find_player_skeleton()
	if skel != null:
		XBotRagdoll.normalize_parent_chain_scale(skel, visual)
	# Backfill null surface materials so the renderer doesn't spam null-
	# material warnings about FBX sub-meshes that imported without a
	# material slot. The PBR meshes still keep their real textures —
	# this only patches surfaces where the FBX had no material at all.
	var character := visual.get_node_or_null(^"Character")
	if character != null:
		XBotRagdoll.ensure_surface_materials(character)
	# Move every MeshInstance3D on the player onto layer 2 (rendered
	# but invisible to floor blood decals at cull_mask=1) plus the
	# CHARACTER_BLOOD_LAYER so spawn_blood_on_character can paint
	# splatter that follows the body. Same scheme as PrototypeEnemy.
	_walk_player_visual_layers(visual, 2 | PrototypeAttackIndicator.CHARACTER_BLOOD_LAYER)
	# The gender swap rebuilt the skeleton, dropping any previous weapon
	# mount. Re-attach the equipped weapon's model to the new hand bone.
	_apply_weapon_model()


# Same recursive walk PrototypeEnemy uses — kept local so the player
# doesn't have to depend on the enemy script. Sets `layers` on every
# VisualInstance3D descendant of `node`.
func _walk_player_visual_layers(node: Node, mask: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = mask
	for child in node.get_children():
		_walk_player_visual_layers(child, mask)


# Cache for _find_player_skeleton — the lookup is a recursive walk
# down the Visual subtree and gets called every physics tick by hot
# paths (accelerator flame muzzle reads, sniper aim-laser updates).
# is_instance_valid covers the gender-swap case where the previous
# skeleton is queue_freed.
var _cached_skeleton: Skeleton3D = null
# Upper-body aim overlay (lazily built under the skeleton). See
# UpperBodyAimModifier + _drive_aim_overlay.
var _aim_modifier: UpperBodyAimModifier = null


# Walks the visual subtree looking for any Skeleton3D. FBX skeleton node
# name varies by importer version; find_child name-only search would miss
# renamed cases.
func _find_player_skeleton() -> Skeleton3D:
	if _cached_skeleton != null and is_instance_valid(_cached_skeleton):
		return _cached_skeleton
	if visual == null:
		_cached_skeleton = null
		return null
	_cached_skeleton = _find_skeleton_recursive(visual)
	return _cached_skeleton


static func _find_skeleton_recursive(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton_recursive(child)
		if found != null:
			return found
	return null


func _tint_meshes(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_meshes(child, mat)

func _apply_saved_state() -> void:
	# Restore accumulated level-up HP before recomputing stats so max_health
	# reflects all past level-up rolls, not just the base @export value.
	if PlayerState.saved_level_hp_bonus > 0:
		_level_hp_bonus = PlayerState.saved_level_hp_bonus
		_recompute_stat_bonuses()
	# Restore current health. -1 means fresh character → use max_health.
	if PlayerState.saved_health >= 0:
		_health = mini(PlayerState.saved_health, max_health)
	else:
		_health = max_health
	health_changed.emit(_health, max_health)
	if PlayerState.saved_credits > 0:
		_credits = PlayerState.saved_credits
		credits_changed.emit(_credits)
	if PlayerState.saved_resource_current > 0.0 and resource_pool != null:
		_resource_current = minf(PlayerState.saved_resource_current, float(resource_pool.max_value))
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)


func _apply_debug_overrides() -> void:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return
	if cfg.override_start_position:
		global_position = cfg.start_position
	if cfg.starting_credits > 0:
		_credits = cfg.starting_credits
		credits_changed.emit(_credits)
	if not cfg.starter_loadout.is_empty():
		_apply_debug_loadout(cfg.starter_loadout)


func _apply_debug_loadout(entries: PackedStringArray) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ilvl := maxi(1, PlayerState.level)
	for entry in entries:
		if entry.strip_edges().is_empty():
			continue
		var item: Item = ItemRoller.roll_debug_entry(entry, ilvl, rng)
		if item == null:
			continue
		var slot: StringName = item.kind
		if slot != &"" and InventoryState.get_equipped(slot) == null:
			InventoryState.set_equipped(slot, item)
		else:
			InventoryState.add_to_inventory(item)

func is_alive() -> bool:
	return _alive


func is_player_friendly(target: Node) -> bool:
	if _combat == null:
		return false
	return _combat.is_player_friendly(target)


## Static helper: route damage to a player, handling SP / MP authority
## transparently. Every enemy-side damage source (enemy_combat melee /
## skill / AoE, projectile direct hit + AoE blast) calls this instead
## of target.take_damage() so remote co-op players receive the hit.
##
## In SP or when the local instance owns the target: calls take_damage
## directly. In MP when targeting a player owned by a different peer:
## sends request_damage.rpc_id to that peer's authority. Mirrors the
## PrototypeEnemy.deal_damage pattern.
static func apply_damage(target: Node3D, amount: int, knockback_from: Vector3, knockback_strength: float = 0.0) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not (target is PrototypePlayer):
		# Defensive fallback — callers should pre-filter, but in case a
		# caller passes a generic Node3D we still dispatch take_damage if
		# present rather than silently dropping the hit.
		if target.has_method(&"take_damage"):
			target.take_damage(amount, knockback_from, knockback_strength)
		return
	# MP routing: if this peer doesn't own the player, send the damage
	# request to the peer that does. Otherwise apply locally.
	if NetState.is_in_lobby() and not target.is_multiplayer_authority():
		var auth_id: int = target.get_multiplayer_authority()
		target.request_damage.rpc_id(auth_id, amount, knockback_from, knockback_strength)
		return
	target.take_damage(amount, knockback_from, knockback_strength)


## RPC endpoint: any peer can request damage on a player. Only the
## peer with authority over this player applies it; everyone else's
## local take_damage is gated by `_is_remote_player()`. Mirrors
## PrototypeEnemy.request_damage but with the player's narrower 3-arg
## signature.
@rpc("any_peer", "call_remote", "reliable")
func request_damage(amount: int, knockback_from: Vector3, knockback_strength: float) -> void:
	if not is_multiplayer_authority():
		return
	if not is_inside_tree():
		return
	take_damage(amount, knockback_from, knockback_strength)


func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0) -> void:
	if _is_remote_player():
		return
	if not _alive:
		return
	if DebugState.config != null and DebugState.config.god_mode:
		return
	# Percentage damage reduction from armor gear bonuses (0–40%).
	if _gear_damage_reduction > 0.0:
		amount = maxi(1, int(round(float(amount) * (1.0 - _gear_damage_reduction * 0.01))))
	# Knockback reduction from the active shield. Computed BEFORE the
	var shield_result := _shield.absorb_damage(amount, knockback_strength)
	amount = shield_result.amount
	knockback_strength = shield_result.knockback
	# Barrier absorbs remaining damage after shield (temporary HP buffer
	# from barrier_on_kill gear stat).
	if _barrier > 0 and amount > 0:
		var absorbed := mini(amount, _barrier)
		_barrier -= absorbed
		amount -= absorbed
	var hp_before := _health
	_health = max(_health - amount, 0)
	health_changed.emit(_health, max_health)
	# Pain Compiler (chest mod): taking damage triggers a brief outgoing-
	# damage buff. Refreshed on each hit so sustained combat keeps the
	# buff active. The healing-suppression trade lives in heal().
	var pain_dur := BehaviorModRegistry.get_active_param(&"chest", &"pain_compiler", &"duration_sec", 0.0)
	if pain_dur > 0.0:
		_pain_compiler_remain = pain_dur
		_pain_compiler_mult = BehaviorModRegistry.get_active_param(&"chest", &"pain_compiler", &"damage_multiplier", 1.0)
	# Shock Discharge (chest mod): one-shot AoE knockback pulse the frame
	# HP crosses below 30%. Armed/disarmed flag prevents per-hit re-firing
	# while the player lingers at low HP; only re-arms after healing above.
	var shock_radius := BehaviorModRegistry.get_active_param(&"chest", &"shock_discharge", &"pulse_radius_m", 0.0)
	if shock_radius > 0.0 and _shock_discharge_armed:
		var threshold := int(round(float(max_health) * 0.30))
		if hp_before > threshold and _health <= threshold and _health > 0:
			_shock_discharge_armed = false
			_fire_shock_discharge_pulse(shock_radius)
	# Reset out-of-combat regen — any take_damage() call delays HP recovery
	# by the full configured window. Environmental DoTs / pit damage / boss
	# AoE all flow through this path, so regen pauses uniformly regardless
	# of damage source.
	_out_of_combat_t = 0.0
	_hp_regen_accum = 0.0
	_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween)
	# Splatter blood on the player's own mesh too — mirrors the enemy
	# take_damage hook so taking hits in combat actually shows.
	if visual != null:
		var impact_pos: Vector3 = knockback_from if knockback_from != Vector3.ZERO else global_position + Vector3(0, 1.0, 0)
		PrototypeAttackIndicator.spawn_blood_on_character(visual, impact_pos)
	if _damage_flash != null:
		_damage_flash.flash(amount, max_health)
	WeaponSounds.play_generic(&"hit_player", global_position)
	var grunt_threshold: int = maxi(2, int(round(float(max_health) * GRUNT_DAMAGE_PCT_MIN)))
	if _grunt_cd <= 0.0 and amount >= grunt_threshold:
		_grunt_cd = GRUNT_COOLDOWN
		WeaponSounds.play_generic(&"hit_grunt", global_position, -4.0, true)
	if knockback_strength > 0.0:
		var dir := global_position - knockback_from
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			_knockback_vel = dir.normalized() * knockback_strength
			_knockback_remain = KNOCKBACK_DURATION
	if _health <= 0:
		_die()

func get_recovery_charges() -> int:
	if _recovery == null:
		return 0
	return _recovery.get_charges()


func get_recovery_heal_remaining() -> int:
	if _recovery == null:
		return 0
	return _recovery.get_heal_remaining()


## Static helper: route a heal to a player, handling SP / MP authority
## transparently. Mirrors apply_damage. Today the only heal callers are
## self-targeting (player_recovery sends heals to the local player's
## own _host), so this is defensive — the moment any AoE / ally-heal
## feature targets a remote player, the routing will already work.
##
## Note: heal() itself has no _is_remote_player() guard the way
## take_damage does, so SP "heal whoever" still works via direct
## call. The MP routing here only kicks in when the target is owned
## by another peer.
static func apply_heal(target: Node3D, amount: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not (target is PrototypePlayer):
		if target.has_method(&"heal"):
			target.heal(amount)
		return
	if NetState.is_in_lobby() and not target.is_multiplayer_authority():
		var auth_id: int = target.get_multiplayer_authority()
		target.request_heal.rpc_id(auth_id, amount)
		return
	target.heal(amount)


## RPC endpoint: any peer can request a heal on a player. Only the peer
## with authority over this player applies it. Mirrors request_damage.
@rpc("any_peer", "call_remote", "reliable")
func request_heal(amount: int) -> void:
	if not is_multiplayer_authority():
		return
	if not is_inside_tree():
		return
	heal(amount)


func heal(amount: int) -> void:
	if not _alive:
		return
	# Pain Compiler trade: healing is suppressed for the duration of the
	# damage buff. Skipped silently — the player feels it when expected
	# heal pickups have no effect during the buff window.
	if _pain_compiler_remain > 0.0:
		return
	var old := _health
	_health = mini(_health + amount, max_health)
	if _health != old:
		health_changed.emit(_health, max_health)
	# Shock Discharge re-arm: once HP climbs back above the 30% threshold,
	# the pulse is available to fire again on the next downward crossing.
	var threshold := int(round(float(max_health) * 0.30))
	if not _shock_discharge_armed and _health > threshold:
		_shock_discharge_armed = true


func on_enemy_killed() -> void:
	if not _alive:
		return
	var lok := _gear_life_on_kill
	# Survivalist talent: +25% life on kill while a melee weapon is equipped.
	if lok > 0:
		var melee_mult := Effects.get_aggregate(&"life_on_kill_melee_mult")
		if melee_mult > 0.0 and _has_melee_equipped():
			lok = int(round(float(lok) * (1.0 + melee_mult)))
		heal(lok)
	var bok := _gear_barrier_on_kill
	# Forged talent: +25% barrier on kill.
	if bok > 0:
		var barrier_mult := Effects.get_aggregate(&"barrier_on_kill_mult")
		if barrier_mult > 0.0:
			bok = int(round(float(bok) * (1.0 + barrier_mult)))
		_add_barrier(bok)
	# Ammo Reclamator (backpack mod) — chance to refund one round to the
	# current weapon's magazine on each kill. Quiet failure when nothing
	# is equipped or the weapon isn't a bullet weapon.
	var refund_chance := BehaviorModRegistry.get_active_param(&"backpack", &"ammo_reclamator", &"refund_chance_pct", 0.0)
	if refund_chance > 0.0 and randf() * 100.0 < refund_chance:
		var weapon: Item = InventoryState.get_equipped(&"weapon")
		if weapon != null and weapon.is_bullet_weapon() and weapon.ammo_current < weapon.ammo_max:
			weapon.ammo_current += 1
			InventoryState.equipment_changed.emit()


func _has_melee_equipped() -> bool:
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	return weapon != null and weapon.weapon_base_id in MELEE_BASE_IDS


func _add_barrier(amount: int) -> void:
	if _barrier_max <= 0:
		return
	_barrier = mini(_barrier + amount, _barrier_max)
	_barrier_decay_timer = BARRIER_DECAY_DELAY
	health_changed.emit(_health, max_health)


func _tick_barrier(delta: float) -> void:
	if _barrier <= 0:
		return
	_barrier_decay_timer -= delta
	if _barrier_decay_timer > 0.0:
		return
	var decay := maxi(1, int(BARRIER_DECAY_RATE * delta))
	_barrier = maxi(0, _barrier - decay)
	health_changed.emit(_health, max_health)


func get_barrier() -> int:
	return _barrier


func _on_player_leveled_up(new_level: int, hp_gain: int) -> void:
	_level_hp_bonus += hp_gain
	_recompute_stat_bonuses()
	_health = max_health
	health_changed.emit(_health, max_health)
	# Banner: "Level up!" plus a conditional second line when THIS level-up
	# granted a talent point. Cadence must match PlayerState._do_level_up:
	# points are granted on level 2, then every LEVELS_PER_TALENT_POINT
	# after that — i.e. (level - 2) % cadence == 0. The previous check used
	# `level % cadence == 0` which would have shown the banner on levels
	# 3/6/9 instead of the actual grant levels 2/5/8/11.
	var msg := tr("HUD_LEVEL_UP_FORMAT")
	if new_level >= 2 and (new_level - 2) % PlayerState.LEVELS_PER_TALENT_POINT == 0:
		var unspent: int = PlayerState.talent_points_total - PlayerState.get_talent_points_spent()
		if unspent > 0:
			msg += "\n" + (tr("HUD_LEVEL_UP_TALENT_POINT") % unspent)
	notification_requested.emit(msg)
	_play_levelup_vfx()

func _play_levelup_vfx() -> void:
	if visual == null:
		return
	# Audio — ui_confirm as a stand-in until a dedicated level_up sting exists.
	WeaponSounds.play_generic(&"ui_confirm", global_position, 2.0, true)
	# Screen flash — brief gold overlay.
	if _damage_flash != null:
		# Reuse the damage flash overlay with a gold tint for level-up.
		# Manually set the color + visible since flash() expects damage args.
		_damage_flash._rect.color = Color(1.0, 0.85, 0.4, 0.3)
		_damage_flash._rect.visible = true
		if _damage_flash._tween != null and _damage_flash._tween.is_valid():
			_damage_flash._tween.kill()
		_damage_flash._tween = _damage_flash.create_tween()
		_damage_flash._tween.tween_property(_damage_flash._rect, "color:a", 0.0, 0.2) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		# instance_id capture to survive level reload between schedule + fire.
		var flash_rect_id: int = _damage_flash._rect.get_instance_id()
		_damage_flash._tween.tween_callback(func() -> void:
			var r := instance_from_id(flash_rect_id) as ColorRect
			if r != null:
				r.visible = false
		)
	# Camera shake — small celebratory jolt.
	var cam := get_viewport().get_camera_3d() as PrototypeCamera
	if cam != null:
		cam.shake(0.25, 0.3)
	# Expanding golden ring.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.7
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.emission_energy_multiplier = 3.0
	ring.material_override = mat
	add_child(ring)
	ring.position = Vector3(0.0, 0.05, 0.0)
	ring.scale = Vector3(0.4, 0.4, 0.4)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.5, 0.4, 3.5), 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(ring, "position:y", 0.6, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# instance_id capture instead of direct method bind — see comment on
	# the dismember prop free in prototype_enemy.gd.
	var ring_id: int = ring.get_instance_id()
	tween.chain().tween_callback(func() -> void:
		var n := instance_from_id(ring_id) as Node
		if n != null:
			n.queue_free()
	)

func _recompute_stat_bonuses() -> void:
	# Aggregate all gear-driven bonuses from every equipped slot.
	var hp_bonus := 0
	var res_bonus := 0
	var dmg_red := 0.0
	var move_spd := 0
	var base_dmg := 0
	var crit := 0.0
	var atk_spd := 0.0
	var hit := 0.0
	var cdr := 0.0
	var hp_regen_bonus := 0.0
	var regen_delay_red := 0.0
	var life_on_kill := 0
	var barrier_on_kill := 0
	for slot in SlotRegistry.SLOTS:
		var item: Item = InventoryState.get_equipped(slot)
		if item == null:
			continue
		# All gear bonuses here contribute to combat power, so they go
		# through get_effective_modifier — the aggregate respects ilvl
		# scaling. Storage stats (inventory_bonus) are read elsewhere via
		# the raw get_modifier so backpack capacity doesn't shrink with level.
		hp_bonus += item.get_effective_modifier(&"max_health_bonus")
		res_bonus += item.get_effective_modifier(&"max_resource_bonus")
		# DR: per-piece cap of 10%, total cap of 40%. Effective modifier
		# already applies ilvl decay so outleveled armor loses DR naturally.
		var piece_dr := minf(item.get_effective_modifier_float(&"damage_reduction"), 10.0)
		dmg_red += piece_dr
		move_spd += item.get_effective_modifier(&"move_speed_bonus")
		base_dmg += item.get_effective_modifier(&"base_damage_bonus")
		crit += float(item.get_effective_modifier(&"crit_chance_bonus")) * 0.01
		atk_spd += float(item.get_effective_modifier(&"attack_speed_bonus")) * 0.01
		hit += float(item.get_effective_modifier(&"hit_chance_bonus")) * 0.01
		cdr += float(item.get_effective_modifier(&"cooldown_reduction")) * 0.01
		hp_regen_bonus += float(item.get_effective_modifier(&"hp_regen_bonus"))
		regen_delay_red += float(item.get_effective_modifier(&"regen_delay_reduction"))
		life_on_kill += item.get_effective_modifier(&"life_on_kill")
		barrier_on_kill += item.get_effective_modifier(&"barrier_on_kill")
	_gear_damage_reduction = minf(dmg_red, 40.0)
	_gear_move_speed_bonus = move_spd
	_gear_base_damage_bonus = base_dmg
	_gear_crit_chance_bonus = crit
	_gear_attack_speed_bonus = atk_spd
	_gear_hit_chance_bonus = hit
	_gear_cooldown_reduction = cdr
	_gear_hp_regen_bonus = hp_regen_bonus
	_gear_regen_delay_reduction = regen_delay_red
	_gear_life_on_kill = life_on_kill
	_gear_barrier_on_kill = barrier_on_kill
	_barrier_max = 50 + barrier_on_kill * 3
	var new_max := _base_max_health + _level_hp_bonus + hp_bonus
	if new_max != max_health:
		var old_max := max_health
		max_health = new_max
		# Scale current HP proportionally so equipping gear doesn't leave the
		# player at 50/200 when they were at 50/100. On first call (_health==0)
		# just fill to max.
		if old_max > 0 and _health > 0:
			_health = clampi(int(round(float(_health) * float(new_max) / float(old_max))), 1, new_max)
		health_changed.emit(_health, max_health)
	if resource_pool != null:
		var new_res_max := _base_resource_max + res_bonus
		if new_res_max != resource_pool.max_value:
			var old_res_max := resource_pool.max_value
			resource_pool.max_value = new_res_max
			# Scale current resource proportionally, same logic as HP.
			if old_res_max > 0 and _resource_current > 0.0:
				_resource_current = clampf(_resource_current * float(new_res_max) / float(old_res_max), 0.0, float(new_res_max))
			_emit_resource_if_changed()
			# Force emit even if int didn't change, since max changed.
			resource_changed.emit(int(_resource_current), resource_pool.max_value)
	stats_changed.emit()

func _process(delta: float) -> void:
	# Remote players don't push their position into the global shader
	# param (multiple writers would fight every frame) and don't run any
	# of the FPS / interact-cursor / mouse-mode UX. All of that lives
	# with whoever has authority on the local machine.
	if _is_remote_player():
		return
	RenderingServer.global_shader_parameter_set(PLAYER_WORLD_POS_PARAM, global_position)
	# FPS hover used to run here, but its raycast errors under threaded
	# physics ("Space state is inaccessible outside of physics process").
	# The hover update was already throttled to FPS_HOVER_INTERVAL (~50ms),
	# so polling it from _physics_process (60 Hz) is visually identical.
	if not _fps_mode:
		_update_interact_cursor()
	_tick_fps_mouse_mode()
	_apply_color_grading_toggle()


# Mirror the DebugConfig.color_grading_enabled flag onto the cached
# Environment's adjustment_enabled each frame. One bool compare + an
# occasional property write — negligible cost, and lets the debug
# panel flip the grading on/off live for A/B comparison.
func _apply_color_grading_toggle() -> void:
	if _world_env == null or DebugState.config == null:
		return
	var want: bool = DebugState.config.color_grading_enabled
	if _world_env.adjustment_enabled != want:
		_world_env.adjustment_enabled = want

func _tick_fps_mouse_mode() -> void:
	if not _fps_mode or _fps_transitioning:
		return
	# Capture the cursor for normal FPS gameplay; release it whenever a
	# modal is open OR the player is dead — without the dead check the
	# death screen's Continue button would be unclickable in FPS mode.
	var want_captured := _alive and not _is_any_modal_open()
	var current := Input.get_mouse_mode()
	if want_captured and current != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif not want_captured and current == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	# Remote (non-authority) players: no input, no combat, no physics.
	# Position / rotation come from the synchronizer; animation is
	# chosen from the synced net_moving flag.
	if _is_remote_player():
		_update_remote_anim()
		_tick_footsteps()
		return
	if not _alive:
		velocity = Vector3.ZERO
		net_moving = false
		return
	if _grunt_cd > 0.0:
		_grunt_cd -= delta
	if _blood_stumble_remaining > 0.0:
		_blood_stumble_remaining = maxf(0.0, _blood_stumble_remaining - delta)
	# Behavior-mod timers — decremented uniformly each physics tick. Effects
	# downstream read `_pain_compiler_remain > 0.0` etc., so just ticking
	# them down is enough to keep buffs honest. No-op when the mod isn't
	# equipped because nothing ever sets them.
	if _pain_compiler_remain > 0.0:
		_pain_compiler_remain = maxf(0.0, _pain_compiler_remain - delta)
	if _recoil_landed_slow_remain > 0.0:
		_recoil_landed_slow_remain = maxf(0.0, _recoil_landed_slow_remain - delta)
	if not Input.is_action_pressed(SKILL_INPUTS[0]):
		_click_consumed = false
	_update_lock_target()
	_combat.tick_cooldowns(delta)
	_tick_resource_regen(delta)
	_tick_health_regen(delta)
	_tick_barrier(delta)
	_telekinesis.tick(delta)
	_shield.tick(delta)
	_doomsayer.tick(delta)
	_grenade.tick(delta)
	_recovery.tick(delta)
	_ied.tick(delta)
	_tick_reload(delta)
	_tick_aim_hold(delta)
	_tick_channel(delta)
	_tick_hammer_wind_up(delta)
	_tick_footsteps()

	# Throttled FPS crosshair hover (raycast against interactables). Has to
	# live in _physics_process because Jolt's threaded mode forbids direct
	# space-state queries from _process. Same FPS_HOVER_INTERVAL throttle as
	# before — 60 Hz physics tick is finer-grained than the throttle anyway.
	if _fps_mode:
		_fps_hover_timer -= delta
		if _fps_hover_timer <= 0.0:
			_fps_hover_timer = FPS_HOVER_INTERVAL
			_update_fps_hover()

	var on_floor := is_on_floor()

	if not on_floor:
		velocity.y -= GRAVITY * delta
	elif not _is_airborne:
		velocity.y = 0.0

	if on_floor and not _crouching and not GameplayChatState.typing and Input.is_action_just_pressed(&"jump"):
		_interacting = false
		# Glide Pads (legs mod): trade vertical impulse for horizontal carry.
		# Reads the rolled % (e.g. 15%) → 0.85× JUMP_VELOCITY.
		var glide_pen := BehaviorModRegistry.get_active_param(&"legs", &"glide_pads", &"jump_height_penalty_pct", 0.0)
		velocity.y = JUMP_VELOCITY * (1.0 - glide_pen * 0.01)
		# Inject the live input direction as horizontal momentum, otherwise
		# a standing-still + move+jump on the same frame would skip it
		# because _want_dir is set later in _physics_process.
		var jump_wish := _input_wish_dir()
		if jump_wish.length_squared() > 0.01 and Vector2(velocity.x, velocity.z).length_squared() < 1.0:
			velocity.x = jump_wish.x * move_speed
			velocity.z = jump_wish.z * move_speed
		_is_airborne = true
		# Recoil Soles (feet mod): seed peak-height tracking for the landing
		# shockwave. Updated each frame while airborne; consumed at landing.
		_airborne_peak_y = global_position.y
		# Drop PILLAR from the collision mask for the duration of the jump
		# so destructible clutter (barrels, crates — PILLAR-only) becomes
		# phase-through and the injected horizontal velocity isn't zeroed
		# by move_and_slide's wall projection every frame. Indestructible
		# cover sits on WORLD+PILLAR, so it still blocks via WORLD —
		# server racks and cell bars stay solid mid-jump as intended.
		_apply_airborne_collision_mask()
		_play_anim(ANIM_JUMP_START, 1.2)

	# Recoil Soles peak-height tracking — sample each frame while airborne
	# so the landing shockwave can scale damage with fall distance. Cheap
	# (one float compare per tick).
	if _is_airborne and global_position.y > _airborne_peak_y:
		_airborne_peak_y = global_position.y

	if _is_airborne and on_floor and velocity.y <= 0.0:
		_is_airborne = false
		# Restore ground-state mask so destructibles are solid again once
		# the player lands — otherwise they'd remain phase-through forever.
		_restore_ground_collision_mask()
		# Recoil Soles (feet mod): land-from-height shockwave + landed slow.
		_recoil_soles_on_land()

	if _knockback_remain > 0.0:
		# Quadratic ease-out: matches PrototypeEnemy so the player coasts to a
		# stop on hit instead of snapping back to input mid-shove.
		var t: float = _knockback_remain / KNOCKBACK_DURATION
		var falloff: float = t * t
		velocity.x = _knockback_vel.x * falloff
		velocity.z = _knockback_vel.z * falloff
		_knockback_remain -= delta
		_want_dir = Vector3.ZERO
		# Incoming knockback cancels any in-flight melee lunge — being
		# hit interrupts the offensive commit.
		_lunge_remain = 0.0
		_lunge_vel = Vector3.ZERO
	elif _lunge_remain > 0.0 and _lunge_duration > 0.0:
		# Melee lunge — same quadratic ease-out as knockback so the
		# player coasts in. Goes through move_and_slide so walls stop
		# the slide instead of clipping.
		var lt: float = _lunge_remain / _lunge_duration
		var lfalloff: float = lt * lt
		velocity.x = _lunge_vel.x * lfalloff
		velocity.z = _lunge_vel.z * lfalloff
		_lunge_remain -= delta
		_want_dir = Vector3.ZERO
	elif _attack_locks_movement() and not _is_airborne:
		# Was _is_attack_committed() — but that returned true for ranged
		# LMB fire too, freezing the player every shot for the weapon's
		# wind_up window (0.1s laser, 0.15s plasma). _attack_locks_movement
		# carves out ranged so run-and-gun works on those archetypes.
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		# Camera-relative wish direction. Chat-typing + top-down + FPS
		# corner cases all live in _input_wish_dir() so the jump-check
		# above and this block stay in lockstep.
		var wish_dir := _input_wish_dir()
		if wish_dir.length_squared() > 0.01:
			# Manual WASD cancels auto-walk-to-interact — the player took
			# direct control.
			_walk_to_interact_target = null
		elif _walk_to_interact_target != null:
			wish_dir = _tick_walk_to_interact()
		_want_dir = wish_dir
		if _interacting and wish_dir.length_squared() > 0.01:
			_interacting = false
		# Hysteresis on backing detection — use a tighter threshold to enter
		# backing (-0.4) and a looser one to exit (-0.2) so the flag doesn't
		# flicker when movement is near-perpendicular to facing direction.
		var _back_dot := wish_dir.dot(-visual.global_transform.basis.z)
		var _back_threshold := -0.2 if _backing else -0.4
		_backing = not _is_airborne and wish_dir.length_squared() > 0.01 and _back_dot < _back_threshold
		if not _is_airborne:
			# Sprint: hold shift while moving to spend resource for a speed burst.
			# Can't sprint while crouching, backing, airborne, or out of resource.
			var wants_sprint := Input.is_action_pressed(&"sprint") and wish_dir.length_squared() > 0.01
			var infinite_res := DebugState.config != null and DebugState.config.infinite_resource
			# Crouch Tactician (legs mod): sprinting is disabled entirely as
			# the trade for the crouch-speed / accuracy buff.
			var crouch_tactician := BehaviorModRegistry.is_mod_equipped_and_active(&"legs", &"crouch_tactician")
			_sprinting = wants_sprint and not _crouching and not _backing and not crouch_tactician and (infinite_res or _resource_current > 0.0)
			if _chromatic != null:
				_chromatic.set_active(_sprinting)
			if _sprinting and not infinite_res:
				# Servo Stride (legs mod) zeroes the sprint resource cost.
				# Tradeoff (walk speed penalty) is applied separately
				# wherever move_speed gets computed — see #68's wiring.
				var sprint_cost: float = SPRINT_RESOURCE_PER_SEC
				if BehaviorModRegistry.is_mod_equipped_and_active(&"legs", &"servo_stride"):
					sprint_cost = 0.0
				var drain := sprint_cost * delta
				var was_above_zero := _resource_current > 0.0
				_resource_current = maxf(0.0, _resource_current - drain)
				_emit_resource_if_changed()
				if was_above_zero and _resource_current <= 0.0:
					_sprint_regen_penalty = SPRINT_EMPTY_REGEN_DELAY
			# Active Shield (SHIELD_HOLD) slows the player to 20% — the
			# trade for full damage block is being a near-stationary
			# target. Buff (SHIELD_BUFF) doesn't slow; it's a passive
			# 25% reduction that shouldn't impact mobility.
			var shield_factor: float = _shield.get_speed_factor()
			var sprint_factor: float = SPRINT_SPEED_FACTOR if _sprinting else 1.0
			var gear_speed_factor := 1.0 + float(_gear_move_speed_bonus) * 0.01
			# Slow-pool effect: standing in a liquid puddle multiplies move
			# speed by Traction.slow_factor_for(...) — full -50% at no
			# traction, scaling to immune at TIER_SLOW (traction 50).
			var pool_factor: float = _slow_pool_factor()
			# Blood-pool effect: mild additional slow (-15% at T0, immune
			# at TIER_SLOW). Multiplies with pool_factor when the player
			# stands in both (rare — but the result composes naturally).
			var blood_factor: float = _blood_pool_factor()
			# Stumble: 100% speed kill for BLOOD_STUMBLE_DURATION after
			# a failed slip-chance roll on pool entry. Composes
			# multiplicatively so other factors stay unchanged after the
			# stumble window ends.
			var stumble_factor: float = 0.0 if is_stumbling() else 1.0
			# Reloading drags movement by 15% — small enough that you can
			# still reposition, large enough that mid-fight reloads feel
			# costly and reward the "back off, then reload" rhythm.
			var reload_factor: float = RELOAD_SPEED_FACTOR if is_reloading() else 1.0
			# AIM_HOLD (Tripod / Aimed Shot) pins the player in place — that's
			# the trade for the accuracy / crit buff.
			var aim_hold_factor: float = 0.0 if aim_hold_locks_movement() else 1.0
			# Behavior-mod movement factors. Each defaults to 1.0 (no effect)
			# so unequipped mods leave the speed math untouched.
			# Crouch Tactician: crouch speed equals walk speed (factor 1.0
			# instead of CROUCH_SPEED_FACTOR). When NOT active, normal crouch
			# factor applies.
			var ct_active := BehaviorModRegistry.is_mod_equipped_and_active(&"legs", &"crouch_tactician")
			var crouch_factor: float = 1.0 if ct_active else CROUCH_SPEED_FACTOR
			# Servo Stride trade: walk speed penalty for getting free sprint.
			# Reads the rolled percent (e.g. 10%) → 0.9 multiplier.
			var servo_penalty_pct := BehaviorModRegistry.get_active_param(&"legs", &"servo_stride", &"walk_speed_penalty_pct", 0.0)
			var servo_factor: float = 1.0 - servo_penalty_pct * 0.01
			# Recoil Soles trade: 1-second landed-slow after each jump. -40%
			# during the slow window — heavy enough to feel, short enough
			# that it doesn't punish casual movement.
			var recoil_slow_factor: float = 0.6 if _recoil_landed_slow_remain > 0.0 else 1.0
			# Attacking-while-moving trade: holding fire or swinging on the move
			# costs speed. _is_aim_input_held() covers held LMB fire and active
			# RMB attack skills (passive shield / aim-hold RMB are excluded).
			var attack_factor: float = ATTACK_MOVE_SLOW_FACTOR if _is_aim_input_held() else 1.0
			var speed := move_speed * (crouch_factor if _crouching else 1.0) * attack_factor * sprint_factor * shield_factor * gear_speed_factor * pool_factor * blood_factor * stumble_factor * reload_factor * aim_hold_factor * servo_factor * recoil_slow_factor
			_target_move_speed = speed
			var flat := Vector2(velocity.x, velocity.z)
			var target := Vector2(wish_dir.x, wish_dir.z) * speed
			# Slip on blood: when releasing wish_dir, multiply the decel step
			# by _blood_friction_factor() (< 1.0) so the player skids past
			# the stop instead of crisp-stopping. Accel step (wish_dir
			# non-zero) is unaffected — feels like "wet boots can't grab
			# the floor when stopping" rather than "starting from rest is
			# sluggish".
			var is_decelerating := wish_dir.length_squared() <= 0.0
			var step_mult: float = 2.5 if is_decelerating else 1.0
			if is_decelerating:
				step_mult *= _blood_friction_factor()
			var step := accel * step_mult * delta
			flat = flat.move_toward(target, step)
			velocity.x = flat.x
			velocity.z = flat.y
		else:
			# Air control — without this, jumping straight up against an
			# obstacle leaves the player no way to nudge themselves over
			# it. Reduced cap (60% of ground speed) and reduced accel so
			# the rise still feels weighty; just enough lateral influence
			# to clear knee-high clutter when starting from rest.
			#
			# Asymmetric application by design: only accelerates UP TO the
			# air cap. A running jump (lateral speed already above the cap)
			# coasts at its launch velocity for the entire arc — without
			# this, `move_toward(flat, air_target)` would drag running
			# jumps from ~8m/s down to ~4.8m/s and kill any pillar-hop
			# distance. Standing-still jumps still get lateral nudges
			# because they start below the cap.
			const AIR_CONTROL_SPEED_FACTOR: float = 0.6
			const AIR_CONTROL_ACCEL_FACTOR: float = 0.5
			var flat := Vector2(velocity.x, velocity.z)
			var air_cap: float = move_speed * AIR_CONTROL_SPEED_FACTOR
			if wish_dir.length_squared() > 0.01 and flat.length() < air_cap:
				var air_target := Vector2(wish_dir.x, wish_dir.z) * air_cap
				var air_step := accel * AIR_CONTROL_ACCEL_FACTOR * delta
				flat = flat.move_toward(air_target, air_step)
				velocity.x = flat.x
				velocity.z = flat.y
	# Capture the wished horizontal motion before move_and_slide so step-up can
	# probe in that direction even if the slide zeroed velocity against a wall.
	var wish_horiz := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	# Auto step-up over short obstacles (pit-edge fences, future stair steps).
	# 0.4m clears anything authored as "low wall" while staying below typical
	# crouch-tunnel ceiling heights.
	StepUp.try(self, wish_horiz, 0.4, delta)

	# Auto-uncrouch as soon as the key isn't held. Polls the physical key
	# directly because Godot's action system can miss the release event for
	# Ctrl when it's released while another key (e.g. WASD) is still held.
	# Aim-hold skills that lock movement (LMG Tripod) force a crouch posture
	# while held; skip the auto-uncrouch in that case so the player stays
	# down even though Ctrl isn't physically pressed.
	if _crouching and not Input.is_physical_key_pressed(KEY_CTRL) and not aim_hold_locks_movement():
		_set_crouch(false)

	if _alive and not _is_attack_committed() and _knockback_remain <= 0.0:
		if _fps_mode:
			# In FPS the body follows camera yaw; snapping is fine because the
			# camera *is* the player view.
			var forward := -_fps_camera.global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.0001:
				_face_direction(forward.normalized())
			if _equipped_light is SpotLight3D:
				_equipped_light.rotation.x = _fps_pitch
		else:
			# Top-down: face the cursor while an attack input is held, otherwise
			# face the direction the player is travelling. Smooth in both cases
			# so direction changes have weight instead of snapping.
			var aiming := _is_aim_input_held()
			var target_dir := Vector3.ZERO
			if aiming:
				var offset := _cursor_offset()
				if offset.length_squared() > 0.0001:
					target_dir = offset.normalized()
			elif _want_dir.length_squared() > 0.01:
				target_dir = _want_dir
			elif Vector2(velocity.x, velocity.z).length_squared() > FACE_BY_VELOCITY_MIN * FACE_BY_VELOCITY_MIN:
				target_dir = Vector3(velocity.x, 0.0, velocity.z).normalized()
			if target_dir.length_squared() > 0.0001:
				_smooth_face(target_dir, TURN_RATE_AIM if aiming else TURN_RATE_MOVE, delta)
			# Flashlight tracks the cursor in world space, independent of body
			# facing — the body smooths toward movement direction, but the beam
			# should follow the mouse so aiming reads as instant.
			if _equipped_light is SpotLight3D:
				_aim_flashlight_at_cursor()
		if _is_airborne:
			anim_player.speed_scale = 1.0
			if velocity.y > 0.0:
				_play_anim(ANIM_JUMP_START, 1.2, 0.1)
			else:
				_play_anim(ANIM_JUMP_AIR, 1.0, 0.15)
		elif not _interacting and _is_oneshot_anim_playing():
			# A one-shot attack / cast / grenade / hit-react animation is
			# still running. Skip the locomotion picker entirely so its
			# per-tick _play_anim(idle/run/...) calls can't truncate the
			# swing before the player actually sees it. The fire/strafe
			# loop, reload pose, and idle return resume the moment the
			# clip finishes. Movement / facing are unaffected — the
			# CharacterBody3D drives travel regardless of which anim plays.
			pass
		elif not _interacting:
			# Firing no longer takes over the body here. The legs stay on the
			# locomotion / idle picker below (grounded feet, free to move while
			# firing); the aim pose is layered onto the upper body only by
			# UpperBodyAimModifier via _drive_aim_overlay() each tick.
			if _want_dir.length_squared() > 0.01:
				# Leg cadence tracks ACTUAL horizontal speed against each
				# clip's authored ground-travel rate (see
				# _CLIP_AUTHORED_SPEED). speed_scale = actual / authored
				# keeps the feet planted regardless of debuffs, sprint,
				# or attack-penalty slow — and uniformly across whichever
				# clip the picker chose (jog / strafe / walk_back /
				# per-class run / crouch_move).
				var actual_speed: float = Vector2(velocity.x, velocity.z).length()
				if _crouching:
					_play_anim_with_synced_speed(ANIM_CROUCH_MOVE, actual_speed)
				else:
					# Directional locomotion picker. Compute wish_dir
					# relative to facing and pick walk_back / strafe_left
					# / strafe_right / jog accordingly. Sprint bypasses
					# the strafe picker because Mixamo's strafe loops are
					# walk-tempo — sprinting laterally with a strafe clip
					# looks oddly slow. Reverts to jog for sprinting +
					# back. Lateral threshold is asymmetric: prefer the
					# strafe clip only when the lateral component clearly
					# dominates so diagonal-forward stays as jog.
					var fwd: Vector3 = -visual.global_transform.basis.z
					var right_axis: Vector3 = visual.global_transform.basis.x
					fwd.y = 0.0
					right_axis.y = 0.0
					var dot_fwd: float = _want_dir.dot(fwd.normalized()) if fwd.length_squared() > 0.0001 else 1.0
					var dot_right: float = _want_dir.dot(right_axis.normalized()) if right_axis.length_squared() > 0.0001 else 0.0
					# Strafe selection with hysteresis: enter strafe only on clear lateral
					# dominance, stay until movement is clearly forward again, and keep a
					# deadband on the L/R direction. Without this the choice flip-flopped as
					# the player circled a target, restarting the strafe clip every switch
					# (the "pausing"). Strafe clips are rifle-stance but the legs read fine.
					var lat_margin: float = absf(dot_right) - absf(dot_fwd)
					if _strafing:
						_strafing = lat_margin > -0.10
					else:
						_strafing = lat_margin > 0.10
					if dot_right > 0.12:
						_strafe_right = true
					elif dot_right < -0.12:
						_strafe_right = false
					if _backing and not _sprinting:
						_play_anim_with_synced_speed(ANIM_WALK_BACK, actual_speed)
					elif _strafing and not _sprinting:
						var strafe_clip: Array[StringName]
						if _strafe_right:
							strafe_clip = [&"xbot/strafe_right"]
						else:
							strafe_clip = [&"xbot/strafe_left"]
						_play_anim_with_synced_speed(strafe_clip, actual_speed)
					else:
						# Forward jog — pick the per-class run stance
						# (pistol_run / rifle_run / sword_run / axe_run /
						# unarmed jog). Falls back to xbot/jog if the
						# class clip isn't loaded.
						_play_anim_with_synced_speed(XBotAnimations.run_anim_for_class(_equipped_weapon_class()), actual_speed)
			else:
				anim_player.speed_scale = 1.0
				if _crouching:
					_play_anim(ANIM_CROUCH_IDLE, 1.0, 0.15)
				else:
					# Class-specific idle stance — rifle ready / sword
					# guard / axe shoulder-rest / fists up / relaxed.
					_play_anim(XBotAnimations.idle_anim_for_class(_equipped_weapon_class()), 1.0, 0.15)

	_drive_aim_overlay(delta)
	_handle_skill_input()
	# Replicated to remote peers via the player's MultiplayerSynchronizer.
	# Threshold matches the existing `_want_dir.length_squared() > 0.01`
	# logic above so the moving / idle state stays consistent between
	# the local animation choice and what's broadcast to remotes.
	net_moving = _want_dir.length_squared() > 0.01 and not _interacting


func _unhandled_input(event: InputEvent) -> void:
	if _is_remote_player():
		return
	# Suppress single-press hotkeys (reload, light, inventory, etc) while
	# the chat input is open. Godot's LineEdit consumes most printable
	# keys before they reach _unhandled_input, but action keys bound to
	# functional keys (Tab, F-keys) can still leak through.
	if GameplayChatState.typing:
		return
	if not _alive:
		return
	if event.is_action_pressed(&"interact"):
		if _is_any_modal_open() or _is_mouse_over_ui():
			return
		_try_interact()
	elif event.is_action_pressed(&"toggle_light"):
		if _equipped_light != null:
			_light_on = not _light_on
			light_changed.emit(_light_on)
			_update_light_visibility()
		else:
			notification_requested.emit(tr("HUD_BANNER_NO_LIGHT"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"reload"):
		# Manual reload — only meaningful for bullet weapons. Auto-reload
		# already triggers when the magazine empties on fire; this is the
		# "I have one bullet left and want to top off before the firefight"
		# convenience path.
		start_reload()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"crouch"):
		_set_crouch(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"crouch"):
		# Don't call _set_crouch(false) here — its ceiling probe queries
		# direct_space_state, which is null under threaded physics when
		# called from input context (crashes with "intersect_shape on null").
		# The auto-uncrouch path in _physics_process (line ~1394) polls
		# Input.is_physical_key_pressed(KEY_CTRL) every physics tick and
		# handles the release safely from a physics-step context. The
		# ~16ms delay between input release and uncrouch is imperceptible.
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_view") and BuildInfo.dev_tools_enabled():
		_handle_toggle_view()
		get_viewport().set_input_as_handled()
	elif _fps_mode and not _fps_transitioning and event is InputEventMouseMotion:
		var sens := DisplayState.config.fps_mouse_sensitivity if DisplayState.config != null else 0.006
		_fps_camera.rotation.y -= (event as InputEventMouseMotion).relative.x * sens
		_fps_pitch = clampf(_fps_pitch - (event as InputEventMouseMotion).relative.y * sens, -FPS_PITCH_LIMIT, FPS_PITCH_LIMIT)
		_fps_camera.rotation.x = _fps_pitch
		get_viewport().set_input_as_handled()

func _try_interact() -> void:
	var interact_range := sqrt(INTERACT_RANGE_SQ)
	var nearest := SpatialGrid.query_nearest(global_position, interact_range, &"interactables")
	if nearest != null and nearest.has_method(&"interact"):
		if not nearest.is_in_group(&"pickups") and not _is_airborne:
			_interacting = true
			_play_anim_stretched(ANIM_INTERACT, INTERACT_ANIM_DURATION, 0.1)
		nearest.interact(self)

func _handle_skill_input() -> void:
	# Suppress all skill input while chat is being typed — number keys and
	# Q/E would otherwise cast skills as the player types those characters.
	if GameplayChatState.typing:
		return
	# No global commit-window gate — each input path self-blocks via its
	# own busy flag (_lmb_busy / _skill_busy) so LMB-hold and RMB-hold
	# operate independently. The loop visits every input each frame
	# instead of returning after the first match.
	for i in SKILL_INPUTS.size():
		if not Input.is_action_pressed(SKILL_INPUTS[i]):
			continue
		if _is_any_modal_open() or _is_mouse_over_ui():
			return
		# LMB-only carve-outs: interactable click consumption + hovered
		# pickup walk-to-interact. These should never block RMB or
		# hotkeys, so they `continue` past LMB instead of returning.
		if i == 0 and _click_consumed:
			continue
		if i == 0 and _fps_mode and _fps_hovered != null and is_instance_valid(_fps_hovered):
			if Input.is_action_just_pressed(SKILL_INPUTS[i]):
				_try_interact_with(_fps_hovered)
			continue
		elif i == 0 and not _fps_mode:
			var hovered := _hovered_clickable()
			if hovered != null:
				if _within_interact_range(hovered):
					if Input.is_action_just_pressed(SKILL_INPUTS[i]):
						_click_consumed = true
						_walk_to_interact_target = null
						_interact_with_hovered(hovered)
					continue
				else:
					# Out of range — start walking to it. Movement loop in
					# _physics_process synthesises a wish_dir toward this
					# node each tick until in range, then fires the interact.
					if Input.is_action_just_pressed(SKILL_INPUTS[i]) and hovered is Node3D:
						_click_consumed = true
						_walk_to_interact_target = hovered as Node3D
					continue
		# LMB fans out across every equipped weapon slot (Forged Amalgamation
		# adds extras). _cast_lmb_combat handles per-slot cooldowns +
		# stagger; the single-skill _cast_skill path stays for RMB and the
		# hotkey skills (1-4 / Q / E).
		if i == 0:
			_cast_lmb_combat()
			continue
		var skill := resolve_skill(i)
		if skill != null:
			_cast_skill(skill)

func resolve_skill(index: int) -> Skill:
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	if index == 0:
		# LMB binds to the MAIN weapon's fire skill for HUD display. Extra
		# weapons (Amalgamation) fire alongside it via _cast_lmb_combat,
		# but the slot icon shows the main weapon's cooldown.
		if weapon != null:
			return weapon.fire_skill
		return UNARMED_SKILL
	elif index == 1:
		# Two-handed weapons own RMB via their alt_fire_skill. One-handed
		# weapons leave RMB to the offhand — the design rule is that
		# 1H+offhand always pairs as LMB+RMB, never weapon-only.
		if weapon != null and weapon.two_handed:
			return weapon.alt_fire_skill
		var offhand: Item = InventoryState.get_equipped(&"offhand")
		return offhand.fire_skill if offhand != null else null
	# Q key (index 6) — consumable recovery overrides talents + skills array.
	if index == 6:
		var consumable: Item = InventoryState.get_equipped(&"consumable")
		if consumable != null:
			return preload("res://resources/skills/health_recovery.tres")
	# Hotkey slots (1, 2, 3, 4, Q, E). A talent that has granted a
	# skill to this slot wins over the player's @export skills array,
	# so a Sanctify node can replace the default skill_q with its own
	# active without reauthoring the player scene.
	var input_action: StringName = SKILL_INPUTS[index]
	var granted := TalentState.get_granted_skill_for_slot(input_action)
	if granted != null:
		return granted
	var skill_index := index - 2
	if skill_index < skills.size():
		return skills[skill_index]
	return null

func _hovered_clickable() -> Node:
	var nodes := get_tree().get_nodes_in_group(&"hovered_clickable")
	for node in nodes:
		if is_instance_valid(node):
			return node
	return null


# Distance check shared by the click-to-interact path and the cursor
# affordance. Without this, hovering a chest from across the room and
# clicking would silently fire the interact() (door unlocks, crate
# opens) regardless of how far away the player is — the proximity
# E-key path uses INTERACT_RANGE_SQ; this brings click-on-hover in line.
# Pickups don't go through this path (they self-handle in
# prototype_item_pickup._on_input_event), so their walk-to / click-to-
# loot behaviour is unchanged.
func _within_interact_range(node: Node) -> bool:
	if node == null or not (node is Node3D):
		return false
	return global_position.distance_squared_to((node as Node3D).global_position) <= INTERACT_RANGE_SQ


# Drive auto-walk toward _walk_to_interact_target. Returns the wish_dir
# the movement loop should use this frame, OR Vector3.ZERO when the
# target is invalid / in range / already interacted with. Side effects:
# clears _walk_to_interact_target on completion / invalidation, and
# fires _interact_with_hovered as soon as the player crosses the
# INTERACT_RANGE_SQ threshold. WASD cancellation is handled by the
# caller (movement loop in _physics_process).
func _tick_walk_to_interact() -> Vector3:
	var target: Node3D = _walk_to_interact_target
	if target == null or not is_instance_valid(target) or not target.has_method(&"interact"):
		_walk_to_interact_target = null
		return Vector3.ZERO
	if _within_interact_range(target):
		_walk_to_interact_target = null
		_interact_with_hovered(target)
		return Vector3.ZERO
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return Vector3.ZERO
	return to_target.normalized()

# Pickups consume their own click via Area3D input_event, so we just suppress
# the skill cast and let the pickup handle it. Doors / switches need an explicit
# interact() call.
func _interact_with_hovered(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.has_method(&"interact"):
		return
	if not node.is_in_group(&"pickups") and not _is_airborne:
		_interacting = true
		_play_anim_stretched(ANIM_INTERACT, INTERACT_ANIM_DURATION, 0.1)
	node.interact(self)

func _is_any_modal_open() -> bool:
	# Cache is built lazily and rebuilt if any entry was freed since last call —
	# UI modals are usually long-lived, but level reset can free and replace them.
	var rebuild := _modal_nodes.is_empty()
	if not rebuild:
		for modal in _modal_nodes:
			if not is_instance_valid(modal):
				rebuild = true
				break
	if rebuild:
		_modal_nodes.clear()
		for node in get_tree().get_nodes_in_group(&"ui_modal"):
			if node is CanvasItem:
				_modal_nodes.append(node as CanvasItem)
	for modal in _modal_nodes:
		if modal.visible:
			return true
	return false

func _is_mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

## Fallback stagger when there's no main weapon to derive a reference
## interval from (e.g. main slot empty but extras equipped). Otherwise
## the per-volley stagger is computed dynamically: main weapon's effective
## attack interval (cooldown / attack_speed) divided by the number of
## ready weapons. So a 1s-interval main with 3 extras fires at 0 / 0.25 /
## 0.5 / 0.75; a 0.5s main with 1 extra fires at 0 / 0.25; etc.
const LMB_MULTI_STAGGER_FALLBACK := 1.0

## Per-arm spawn offsets for Forged Amalgamation extras. weapon_2 fires from
## the player's right (relative to aim), weapon_3 from the left, weapon_4
## from above. Magnitudes sized to clear the player capsule visually
## without throwing trajectories so far that targeting reads as off.
const ARM_OFFSET_LATERAL := 0.5
const ARM_OFFSET_VERTICAL := 1.0

# LMB attack path. Iterates every active weapon slot (main + Amalgamation
# extras), fires each whose slot cooldown is ready, and staggers their
# windups so the volley reads as a sequence not a single click. Each
# weapon's cooldown is tracked per-slot so two identical weapons don't
# share a timer; the main weapon also writes the skill-keyed cooldown so
# the HUD slot icon's progress ring stays accurate for the LMB display.
func _cast_lmb_combat() -> void:
	if _lmb_busy:
		return
	# CHANNEL_BEAM main weapon (Taser tase, Accelerator stream) starts
	# the channel held-state instead of going through the standard
	# multi-arm volley for its own slot. _tick_channel ticks damage
	# on its own and stops when the input releases. The volley loop
	# below still runs so Forged Amalgamation extras keep firing —
	# the main slot just gets skipped because it's running on a
	# different code path. Without this, a Taser-as-main blocked
	# every extra arm from firing.
	var main_weapon: Item = InventoryState.get_equipped(&"weapon")
	var main_is_channel := main_weapon != null and main_weapon.fire_skill != null and main_weapon.fire_skill.active_kind == Skill.ActiveKind.CHANNEL_BEAM
	if main_is_channel and _channel_skill == null:
		_start_channel(main_weapon.fire_skill, &"fire")
	_lmb_busy = true
	_interacting = false
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		_lmb_busy = false
		return

	# Extra Amalgamation arms fire FREE — they don't gate on resource and
	# don't consume it. Otherwise a 4-arm Forged drains the pool in one
	# click. Only the main weapon's fire_skill spends resource.
	var slots := InventoryState.get_active_weapon_slots()
	var ready_fires: Array[Dictionary] = []
	for slot in slots:
		var item: Item = InventoryState.get_equipped(slot)
		if item == null or item.fire_skill == null:
			continue
		var skill: Skill = item.fire_skill
		if _combat.is_slot_on_cooldown(slot):
			continue
		var is_main := slot == &"weapon"
		# Skip the main slot when it's running as a CHANNEL_BEAM —
		# the channel handles its own ticks via _tick_channel. Firing
		# the standard volley path on top would double-resolve the
		# damage every frame.
		if is_main and main_is_channel:
			continue
		# Bullet weapons: ammo gates fire (and is_reloading() blocks). Energy
		# weapons: resource cost gates fire. Helper centralises both checks.
		if is_main and not _skill_can_fire(item, skill, true):
			# Empty-magazine LMB on a bullet weapon kicks an auto-reload.
			# The post-fire trigger in _skill_pay_cost (line ~2946) handles
			# the normal "you just spent your last round" case, but it can't
			# cover the load-in-with-0-ammo path (fire gate skips the slot
			# before pay_cost runs) — without this the player has to press
			# R manually after loading a save with an empty mag. Skip when
			# already reloading so we don't restart the timer.
			if item.is_bullet_weapon() and not is_reloading():
				start_reload()
			continue
		ready_fires.append({"slot": slot, "item": item, "skill": skill, "is_main": is_main})

	if ready_fires.is_empty():
		# No weapon equipped — fall back to unarmed strike. Fires the
		# unarmed skill with null weapon; damage comes from skill.damage
		# plus any unarmed_damage_bonus on gloves.
		if main_weapon == null:
			_fire_unarmed(aim)
		_lmb_busy = false
		return

	# Bump the fire-cancellation counter NOW that we know a real fire is
	# going to schedule. If we bumped above the cooldown check, LMB-hold
	# would call _cast_lmb_combat every frame, find every slot on cooldown,
	# return early — but the generation bump would have already invalidated
	# the in-flight damage timer from the previous press (gen mismatch in
	# the lambda below). Net result: holding LMB on a slow weapon (any
	# melee, any windup ranged) NEVER resolved damage / SFX / animation
	# because each frame cancelled the pending fire.
	_fire_generation += 1
	var fire_gen: int = _fire_generation

	# Stagger across the MAIN weapon's effective attack interval so a
	# 1s-interval Forged with 3 extras fires at 0 / 0.25 / 0.5 / 0.75
	# regardless of each individual weapon's speed. Reads off the equipped
	# main weapon directly (not ready_fires) so the cadence stays stable
	# even when main is on cooldown and only extras are ready this volley.
	var main_interval := LMB_MULTI_STAGGER_FALLBACK
	var main_item: Item = InventoryState.get_equipped(&"weapon")
	if main_item != null and main_item.fire_skill != null:
		var main_atk_spd: float = main_item.effective_attack_speed() if main_item.attack_speed > 0.0 else 1.0
		main_interval = main_item.fire_skill.cooldown / main_atk_spd
	var stagger: float = main_interval / float(ready_fires.size())

	# Aim-relative axes for per-arm offsets. aim_right is 90° clockwise from
	# the horizontal aim vector (Vector3.UP cross flat-aim), so an extra
	# arm's bullets emerge from the player's right relative to the cursor,
	# not relative to world space.
	var aim_flat := Vector3(aim.x, 0.0, aim.z)
	if aim_flat.length_squared() < 0.0001:
		aim_flat = Vector3.FORWARD
	else:
		aim_flat = aim_flat.normalized()
	var aim_right := aim_flat.cross(Vector3.UP).normalized()

	var max_fire_delay := 0.0
	for i in ready_fires.size():
		var f: Dictionary = ready_fires[i]
		var skill: Skill = f["skill"]
		var item: Item = f["item"]
		var slot: StringName = f["slot"]
		var is_main: bool = f["is_main"]
		var atk_spd: float = item.effective_attack_speed() if item.attack_speed > 0.0 else 1.0
		_combat.start_slot_cooldown(slot, skill, atk_spd)
		# Mirror onto the skill-keyed dict for the MAIN weapon so the HUD's
		# LMB slot reads cooldown the same way it always has.
		if is_main:
			_combat.start_cooldown(skill, atk_spd)
			# Pay either resource (energy) or ammo (bullet); helper also
			# fires the auto-reload trigger on the empty-magazine shot.
			_skill_pay_cost(item, skill, true)
		# Each fire's projectile spawn / damage event is delayed by:
		#   (i * stagger)              — multi-arm visual stagger
		# + per-weapon-class wind-up   — see below
		#
		# For ranged weapons we use the skill's authored wind_up so
		# weapons with audio pre-roll (RPG: 1s charging then launch
		# transient) keep their existing rhythm. For MELEE weapons we
		# override wind_up to half the effective attack interval —
		# that lands the damage event mid-swing instead of at the
		# wind-up start, syncing it with the animation's visual hit
		# moment (~50% of the stretched clip). The SFX gets the same
		# treatment below so the strike sound lands on the impact frame
		# rather than at LMB press.
		var is_melee: bool = item != null and item.weapon_base_id in MELEE_BASE_IDS
		var wind_up_delay: float
		if is_melee:
			var melee_interval: float = (skill.cooldown / atk_spd) if skill.cooldown > 0.0 else 0.5
			# Damage / SFX fires at this fraction through the stretched
			# swing clip. The "right" value is where the clip's visible
			# impact frame actually lands — Mixamo's stock melee swings
			# aren't authored with impact at exactly 50%, so the default
			# 0.5 leaves damage feeling slightly desynced from the visual
			# hit on weapons whose clip front-loads the windup.
			# `axe_swing` (sledgehammer) leans into a heavy windup before
			# the strike — the visible impact lands ~40% in, not 50%.
			# Per-class table lets each weapon dial its own ratio without
			# tuning the others.
			# Use the combo step the upcoming swing will resolve at
			# (peek, not advance — combat will advance the step a few
			# ms later inside _resolve_cone). Different combo clips
			# have different impact frames; the per-step ratio table
			# keeps every step's damage synced to its own clip.
			var impact_step: int = peek_next_melee_combo_step(item)
			wind_up_delay = melee_interval * _melee_impact_ratio(item.weapon_base_id, impact_step)
		else:
			wind_up_delay = (skill.wind_up / atk_spd) if skill.wind_up > 0.0 else 0.0
		var fire_delay: float = float(i) * stagger + wind_up_delay
		max_fire_delay = maxf(max_fire_delay, fire_delay)
		# Fire SFX timing:
		#   Ranged → synchronous at LMB-press, so audio pre-roll runs
		#     concurrent with the wind-up and the launch transient lands
		#     when the projectile spawns.
		#   Melee  → deferred into the fire timer below so the strike
		#     sound lands on the impact frame, not at LMB press. The
		#     melee swing isn't a wind-up audio cue — it's the hit
		#     itself, and playing it 0.5s early reads as desync.
		#   Channel weapons skip both — own SFX path.
		if item != null and not WeaponSounds.is_channel_weapon(item.weapon_base_id) and not is_melee:
			WeaponSounds.play_fire(item.weapon_base_id, global_position)
		var captured_skill := skill
		var captured_item := item
		var captured_offset := _arm_offset_for_slot(slot, aim_right)
		# Resolve `self` through instance_from_id at fire time. Implicit
		# `self` captures (via `_alive`, `_combat`, etc.) would log a
		# "Lambda capture freed" error if the player dies / level reloads
		# between LMB-press and the wind-up timer firing — SceneTreeTimers
		# survive scene reloads, so this fires AFTER the new level loads
		# without `p`. Skill/Item are Resources (RefCounted) so their
		# captures keep them alive on their own — no ID dance needed.
		var player_id: int = get_instance_id()
		var captured_is_melee: bool = is_melee
		get_tree().create_timer(fire_delay).timeout.connect(func() -> void:
			var p := instance_from_id(player_id) as PrototypePlayer
			if p == null or not p._alive:
				return
			# Cancel this fire if a newer LMB / RMB press has bumped
			# the generation — the user pressed RMB (or another LMB)
			# before our wind-up window closed; the newer attack owns
			# the damage / SFX / animation now.
			if p._fire_generation != fire_gen:
				return
			var fire_aim := aim
			if p._lock_target != null:
				var refreshed := p._aim_direction()
				if refreshed != Vector3.ZERO:
					fire_aim = refreshed
			# Melee strike SFX fires now (on impact), not at LMB press
			# — see the SFX comment above. Item is Resource so the
			# captured ref is safe across the timer.
			if captured_is_melee and captured_item != null and not WeaponSounds.is_channel_weapon(captured_item.weapon_base_id):
				WeaponSounds.play_fire(captured_item.weapon_base_id, p.global_position)
			p._combat.resolve_skill_hit(captured_skill, fire_aim, captured_item, captured_offset)
		, CONNECT_ONE_SHOT)

	# Animation + movement stop only when the main weapon fired this volley.
	# Extra arms fire silently — the Forged stays mobile while extras shoot.
	var main_fired := false
	for f in ready_fires:
		if f["is_main"]:
			main_fired = true
			break
	if main_fired:
		_face_direction(aim)
		# Ranged weapons play the looping firing-rifle pose; melee + unarmed
		# fall back to the punch/swing animation. _play_fire_pose with
		# restart=true triggers a visible recoil cycle for slow weapons
		# (HOLD mode) and is a no-op restart for fast weapons (LOOP
		# mode's _play_anim early-out skips it).
		if main_item != null and not _attack_is_melee(main_item):
			_pulse_fire_recoil()
		else:
			# Melee swing — picks the variant for the current combo
			# step (0/1/2). peek_next_melee_combo_step previews what
			# advance_melee_combo will set inside PlayerCombat a few
			# ms later, so the visual matches the gameplay step. Plays
			# the full clip stretched to fit the effective attack
			# interval (cooldown / attack_speed), so increasing attack
			# speed scales the animation rate accordingly and the
			# weapon's physical attack rhythm matches the visible
			# motion. main_interval is already computed for multi-arm
			# stagger above; reuse it here as the animation duration.
			var combo_step := peek_next_melee_combo_step(main_item)
			# Compress the visual duration for weapon classes that read
			# as over-stretched at standard main_interval. Sledgehammer's
			# axe_swing in particular floats when stretched 1.3× past its
			# native length; 0.8× brings it back to a snappy, committed
			# swing while damage stays at impact_ratio × main_interval
			# (damage timer is independent of anim duration).
			var weapon_base_id: StringName = main_item.weapon_base_id if main_item != null else &""
			var anim_duration_mult: float = _MELEE_ANIM_DURATION_MULT.get(weapon_base_id, 1.0)
			var anim_duration: float = main_interval * anim_duration_mult
			if not _swing_overlay_if_moving(combo_step, anim_duration):
				_play_anim_stretched(XBotAnimations.combo_attack_anim_for_class(_equipped_weapon_class(), combo_step), anim_duration)
			# Blade-only auto-lunge toward the closest enemy under the
			# cursor — closes the gap so the player doesn't have to
			# manually walk into range on every swing. main_atk_spd
			# was computed above for the multi-arm stagger formula.
			var lunge_atk_spd: float = main_item.effective_attack_speed() if main_item != null and main_item.attack_speed > 0.0 else 1.0
			_try_blade_lunge(main_item, lunge_atk_spd)
		_ied.toss_trap(_cursor_offset())
	# Hold the player still for the main weapon's wind-up only. Extra arms
	# don't contribute to the stop — Forged stays mobile while extras fire.
	var stop_duration := 0.0
	if main_fired and main_item != null and main_item.fire_skill != null:
		var main_wind_up: float = main_item.fire_skill.wind_up
		if main_wind_up > 0.0:
			var main_atk_spd_for_stop: float = main_item.effective_attack_speed() if main_item.attack_speed > 0.0 else 1.0
			stop_duration = maxf(stop_duration, main_wind_up / main_atk_spd_for_stop)
	if stop_duration > 0.0:
		_attack_aim = aim
		await get_tree().create_timer(stop_duration).timeout
	else:
		# No wind-up — hold the guard for one physics frame so a second
		# _cast_lmb_combat call on the very next tick can't slip through.
		await get_tree().process_frame
	_lmb_busy = false


# Unarmed strike — fires the unarmed skill with null weapon. Glove
# modifiers (unarmed_damage_bonus, unarmed_stun_chance, unarmed_aoe_radius)
# are applied inside PlayerCombat's damage path via _host helpers.
func _fire_unarmed(aim: Vector3) -> void:
	if _combat.is_on_cooldown(UNARMED_SKILL):
		return
	_face_direction(aim)
	_combat.start_cooldown(UNARMED_SKILL, 1.0)
	# Sync the punch animation, sound, and damage on the impact frame
	# — same principle as melee weapons. The anim stretches to fill
	# the cooldown, damage + impact SFX fire at the midpoint (~50%
	# through the anim, which is where the visible punch lands).
	var duration: float = UNARMED_SKILL.cooldown if UNARMED_SKILL.cooldown > 0.0 else 0.3
	_play_anim_stretched(XBotAnimations.random_unarmed_punch(), duration)
	var impact_delay: float = duration * 0.5
	# Capture player by instance_id so the lambda survives a death /
	# scene reload that fires between press and impact — same pattern
	# as the melee fire timer.
	var player_id: int = get_instance_id()
	get_tree().create_timer(impact_delay).timeout.connect(func() -> void:
		var p := instance_from_id(player_id) as PrototypePlayer
		if p == null or not p._alive:
			return
		WeaponSounds.play_generic(&"unarmed_swing", p.global_position)
		p._combat.resolve_skill_hit(UNARMED_SKILL, aim, null)
	, CONNECT_ONE_SHOT)


# Per-arm world-space offset for the projectile / hitscan source position.
# weapon (main): no offset — fires from chest.
# weapon_2:      right of player (relative to aim direction).
# weapon_3:      left of player.
# weapon_4:      above the player.
# Aim_right is the precomputed horizontal "right relative to aim" vector.
func _arm_offset_for_slot(slot: StringName, aim_right: Vector3) -> Vector3:
	match slot:
		&"weapon_2":
			return aim_right * ARM_OFFSET_LATERAL
		&"weapon_3":
			return -aim_right * ARM_OFFSET_LATERAL
		&"weapon_4":
			return Vector3(0.0, ARM_OFFSET_VERTICAL, 0.0)
	return Vector3.ZERO


func _cast_skill(skill: Skill) -> void:
	if skill == null or _skill_busy:
		return
	# Face the cursor at press time, same as LMB. Applied here at the
	# top so every active-kind path picks it up — AIM_HOLD, CHANNEL_BEAM,
	# SHIELD_BUFF, SECOND_WIND, RECOVERY, plus the standard fire pipeline
	# below. Cheap; even self-targeted skills (Second Wind, Recovery)
	# read better when the character commits to a facing direction on
	# activation. Aim-zero is a defensive guard for a cursor that hasn't
	# resolved yet (rare).
	var cast_aim := _aim_direction()
	if cast_aim != Vector3.ZERO:
		_face_direction(cast_aim)
	# Active offhands (shield, grenade, generator) bypass the standard
	# fire pipeline — they own state machines that don't fit the
	# one-shot cone/aoe/projectile/hitscan model.
	if skill.active_kind != Skill.ActiveKind.NONE:
		match skill.active_kind:
			Skill.ActiveKind.AIM_HOLD:
				# RMB-press starts the hold; the tick handler watches for
				# RMB-release and ends it. No cooldown — the resource
				# drain is the cost gate.
				_start_aim_hold(skill)
			Skill.ActiveKind.CHANNEL_BEAM:
				# Hold-to-stream — start the channel if not already
				# active. _tick_channel ticks damage and stops on release.
				if _channel_skill == null:
					# Detect which input was held — RMB if the bound
					# skill matches resolve_skill(1), otherwise hotkey.
					var input_action: StringName = &"alt_fire"
					if resolve_skill(1) != skill:
						# Hotkey channel — match by skill identity to
						# the SKILL_INPUTS slot. Edge case; channels
						# usually live on LMB or RMB.
						for i in range(2, SKILL_INPUTS.size()):
							if resolve_skill(i) == skill:
								input_action = SKILL_INPUTS[i]
								break
					_start_channel(skill, input_action)
			Skill.ActiveKind.SHIELD_BUFF, Skill.ActiveKind.SHIELD_HOLD:
				# Cast anim gated on actual activation — a press while
				# on cooldown shouldn't play the visual. Duration is the
				# wind-up (the cast gesture); the shield then stays active
				# longer but the gesture itself is the wind-up.
				if _shield.activate_offhand_skill(skill):
					_play_anim_stretched(ANIM_CAST, maxf(skill.wind_up, 0.5))
			Skill.ActiveKind.GRENADE:
				if _grenade.is_on_cooldown():
					return
				# Compute the throw vector BEFORE spending resource — the
				# grenade activate() bails on zero offset (FPS-mode used
				# to drop here because _cursor_offset() relies on the iso
				# camera's mouse-ray, which is meaningless when the cursor
				# is captured). Bailing here keeps energy and cooldown in
				# sync with whether a grenade actually leaves the hand.
				var throw_dir := _grenade_throw_offset()
				if throw_dir.length_squared() < 0.0001:
					return
				var infinite_res := DebugState.config != null and DebugState.config.infinite_resource
				if skill.resource_cost > 0 and not infinite_res and _resource_current < float(skill.resource_cost):
					return
				if skill.resource_cost > 0:
					_spend_resource(skill.resource_cost)
				_face_direction(throw_dir)
				# Was ANIM_ATTACK (xbot/punch) — grenades now play the
				# dedicated pitching motion stretched to the throw's
				# wind-up duration (0.5s fallback if the skill author
				# left wind_up unset).
				_play_anim_stretched(ANIM_GRENADE_THROW, maxf(skill.wind_up, 0.5))
				_grenade.activate(skill, throw_dir)
			Skill.ActiveKind.SECOND_WIND:
				if _activate_second_wind(skill):
					_play_anim_stretched(ANIM_CAST, maxf(skill.wind_up, 0.5))
			Skill.ActiveKind.RECOVERY:
				if _recovery.activate(skill):
					_play_anim_stretched(ANIM_CAST, maxf(skill.wind_up, 0.5))
		return
	_interacting = false
	if _combat.is_on_cooldown(skill):
		return
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		return
	var weapon := _combat.resolve_skill_source(skill)
	# Treat the resolved weapon as the main-hand item for the cost gate
	# so a bullet weapon's alt-fire (e.g. RPG nuke) burns ammo from the
	# same magazine the LMB shot uses, and energy weapons keep the
	# resource-cost path. Reload also blocks alt-fires.
	if not _skill_can_fire(weapon, skill, true):
		return
	# Bump the fire-cancellation counter so any in-flight LMB timer from
	# the previous press self-cancels — pressing an RMB attack after LMB
	# should hand the rhythm over to the skill, not have the old swing
	# fire its damage / SFX mid-cast.
	#
	# Only bumped on the standard-attack branch (skill.active_kind == NONE).
	# The earlier `match` block handles AIM_HOLD / SHIELD / GRENADE /
	# SECOND_WIND / RECOVERY / CHANNEL_BEAM — those don't replace the LMB
	# rhythm (they're concurrent buffs / state machines), so bumping at
	# the top of _cast_skill would cancel every LMB shot while the player
	# is holding RMB. That broke Aimed Shot / Tripod: the AIM_HOLD re-enters
	# _cast_skill every frame RMB is held, and each entry was nuking the
	# fire_gen captured by the still-windup-ing LMB damage timer.
	_fire_generation += 1
	var fire_gen: int = _fire_generation
	var atk_spd := weapon.effective_attack_speed() if weapon != null else 1.0
	if atk_spd <= 0.0:
		atk_spd = 1.0
	_combat.start_cooldown(skill, atk_spd)
	_skill_pay_cost(weapon, skill, true)
	_skill_busy = true
	_attack_aim = aim
	_attack_weapon = weapon
	_face_direction(aim)
	# Ranged skills (RPG, sniper alt-fire, etc.) use the firing-rifle pose;
	# melee skills and class skills with no weapon fall back to the swing
	# animation. Same FIRE / FIRE_MOVE branch as the LMB path so the
	# per-tick picker doesn't undo our choice. restart=true for the
	# per-shot recoil cycle in slow-weapon HOLD mode.
	if weapon != null and not _attack_is_melee(weapon):
		_pulse_fire_recoil()
	else:
		# Combo-aware melee swing — see peek_next_melee_combo_step.
		# Plays the clip stretched to fit the skill's effective window,
		# but capped at MELEE_SKILL_MAX_ANIM_DUR so a long cooldown
		# doesn't drag the visible swing into multi-second windup
		# territory. Cooldown still gates the next cast independently.
		var combo_step := peek_next_melee_combo_step(weapon)
		var skill_atk_spd: float = atk_spd if atk_spd > 0.0 else 1.0
		var skill_dur: float = skill.cooldown / skill_atk_spd if skill.cooldown > 0.0 else 0.7
		skill_dur = minf(skill_dur, MELEE_SKILL_MAX_ANIM_DUR)
		if not _swing_overlay_if_moving(combo_step, skill_dur):
			_play_anim_stretched(XBotAnimations.combo_attack_anim_for_class(_equipped_weapon_class(), combo_step), skill_dur)
	PrototypeAttackIndicator.spawn(self, skill, aim, _combat.effective_range(skill, weapon))
	# Per-weapon SFX timing:
	#   Ranged → synchronous at press so audio pre-roll (RPG charge,
	#     etc.) aligns with the wind-up wait.
	#   Melee  → deferred until the impact-frame await below — the
	#     strike sound IS the hit, not a wind-up cue.
	#   Channel → own SFX path, skipped.
	var skill_is_melee: bool = weapon != null and weapon.weapon_base_id in MELEE_BASE_IDS
	if weapon != null and not WeaponSounds.is_channel_weapon(weapon.weapon_base_id) and not skill_is_melee:
		WeaponSounds.play_fire(weapon.weapon_base_id, global_position)
	# Damage-event delay. For melee, derive from the SAME capped
	# anim window the swing animation uses + the per-step impact ratio
	# (matches the LMB sync logic) so the strike lands at the visible
	# impact frame regardless of cooldown. Ranged keeps the authored
	# wind_up so pre-roll audio stays aligned.
	var resolve_delay: float
	if skill_is_melee and skill.cooldown > 0.0:
		var melee_dur: float = minf(skill.cooldown / atk_spd, MELEE_SKILL_MAX_ANIM_DUR)
		var base_id: StringName = weapon.weapon_base_id if weapon != null else &""
		var step: int = peek_next_melee_combo_step(weapon)
		resolve_delay = melee_dur * _melee_impact_ratio(base_id, step)
	elif skill.wind_up > 0.0:
		resolve_delay = skill.wind_up / atk_spd
	else:
		resolve_delay = 0.0
	if resolve_delay > 0.0:
		await get_tree().create_timer(resolve_delay).timeout
	_skill_busy = false
	if not _alive:
		return
	# Cancel if a newer LMB / skill press has taken over.
	if _fire_generation != fire_gen:
		return
	var fire_aim := _attack_aim
	if _lock_target != null:
		var refreshed := _aim_direction()
		if refreshed != Vector3.ZERO:
			fire_aim = refreshed
	# Deferred melee strike SFX — fires on the impact frame.
	if skill_is_melee and weapon != null and not WeaponSounds.is_channel_weapon(weapon.weapon_base_id):
		WeaponSounds.play_fire(weapon.weapon_base_id, global_position)
	_combat.resolve_skill_hit(skill, fire_aim, _attack_weapon)

func _tick_resource_regen(delta: float) -> void:
	if resource_pool == null or resource_pool.regen_per_sec <= 0.0:
		return
	if _sprinting:
		return
	# Penalty cooldown after emptying resource while sprinting.
	if _sprint_regen_penalty > 0.0:
		_sprint_regen_penalty -= delta
		return
	if _resource_current >= float(resource_pool.max_value):
		return
	_resource_current = minf(float(resource_pool.max_value), _resource_current + resource_pool.regen_per_sec * delta)
	_emit_resource_if_changed()


# Out-of-combat HP regen. _out_of_combat_t counts up since the last
# take_damage() and crosses the (delay - reduction) threshold to start
# regenerating. Regen rate = HP_REGEN_BASE_PCT + gear bonus, applied as
# a percentage of max_health per second. Stops at full HP and on death.
# Also stops when any aggro'd enemy is within COMBAT_PROXIMITY_RADIUS —
# dodging hits for 5+ seconds shouldn't count as "out of combat" if the
# enemy is still actively chasing. A sub-integer accumulator handles
# low-rate-low-fps cases where a single delta tick produces less than 1
# HP — without it nothing ever regens.
func _tick_health_regen(delta: float) -> void:
	if not _alive:
		return
	if _health >= max_health:
		_hp_regen_accum = 0.0
		return
	_out_of_combat_t += delta
	var delay := maxf(HP_REGEN_DELAY - _gear_regen_delay_reduction, HP_REGEN_MIN_DELAY)
	if _out_of_combat_t < delay:
		return
	if _is_in_combat():
		_hp_regen_accum = 0.0
		return
	var rate_pct := HP_REGEN_BASE_PCT + _gear_hp_regen_bonus
	if rate_pct <= 0.0:
		return
	_hp_regen_accum += float(max_health) * (rate_pct / 100.0) * delta
	if _hp_regen_accum < 1.0:
		return
	var whole_hp := int(floor(_hp_regen_accum))
	_hp_regen_accum -= float(whole_hp)
	var prev := _health
	_health = mini(_health + whole_hp, max_health)
	if _health != prev:
		health_changed.emit(_health, max_health)


# True when any non-charmed enemy within COMBAT_PROXIMITY_RADIUS is in an
# active engagement state (chasing, knocked back, stunned, grabbed).
# Charmed pets and idle / returning enemies don't count — the player is
# only "in combat" when something is actively hostile and aware of them.
func _is_in_combat() -> bool:
	var nearby := SpatialGrid.query_radius(global_position, COMBAT_PROXIMITY_RADIUS, &"enemies")
	for n in nearby:
		if not is_instance_valid(n):
			continue
		if n.has_method(&"is_engaged_with_player") and n.is_engaged_with_player():
			return true
	return false


# Public accessors for the buff bar. Live counts of the per-spec
# entity lists the player owns — charmed pets (AMB), IED traps (ING),
# orbiting drones (OPT). Max counters are derived from the perk
# aggregates so the HUD can render "X/Y" without re-reading internals.
func get_charm_count() -> int:
	if _doomsayer == null:
		return 0
	return _doomsayer.get_charm_count()


func get_charm_max() -> int:
	if _doomsayer == null:
		return 0
	return _doomsayer.get_charm_max()


func get_trap_count() -> int:
	if _ied == null:
		return 0
	return _ied.get_trap_count()


func get_trap_max() -> int:
	if _ied == null:
		return 0
	return _ied.get_trap_max()


func get_drone_count() -> int:
	if _drone_swarm == null:
		return 0
	return _drone_swarm.get_drone_count()


## Returns true if the resource pool was actually refilled. False when
## the skill is on cooldown so the caller can skip the cast anim.
func _activate_second_wind(skill: Skill) -> bool:
	if _combat.is_on_cooldown(skill):
		return false
	if resource_pool == null:
		return false
	_resource_current = float(resource_pool.max_value)
	_sprint_regen_penalty = 0.0
	_emit_resource_if_changed()
	resource_changed.emit(int(_resource_current), resource_pool.max_value)
	_combat.start_cooldown(skill, 1.0)
	return true


func _spend_resource(amount: int) -> void:
	if resource_pool == null:
		return
	if DebugState.config != null and DebugState.config.infinite_resource:
		return
	_resource_current = maxf(0.0, _resource_current - float(amount))
	_emit_resource_if_changed()

func _emit_resource_if_changed() -> void:
	var new_int := int(_resource_current)
	if new_int != _resource_last_int:
		_resource_last_int = new_int
		resource_changed.emit(new_int, resource_pool.max_value)

func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	_credits += amount
	credits_changed.emit(_credits)

func get_credits() -> int:
	return _credits


# ── Bullet weapon reload ────────────────────────────────────────────────────

## True while the main weapon is mid-reload. Firing is blocked; HUD shows
## a progress indicator instead of the ammo count.
func is_reloading() -> bool:
	return _reload_remain > 0.0

## 0.0 → 1.0 progress through the current reload, or 0.0 when not
## reloading. HUD uses this to paint a fill bar on the ammo widget.
func get_reload_progress() -> float:
	if _reload_total <= 0.0 or _reload_remain <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_remain / _reload_total, 0.0, 1.0)

## Start a reload of the main weapon if it's a bullet weapon, not full,
## and not already reloading. No-op otherwise. Called automatically when
## the magazine empties on fire AND on R-key press.
func start_reload() -> void:
	var w: Item = InventoryState.get_equipped(&"weapon")
	if w == null or not w.is_bullet_weapon():
		return
	if w.ammo_current >= w.ammo_max:
		return
	if is_reloading():
		return
	var reload_time := w.reload_time
	# Reflex Loader (hands mod): reload time scales down with current
	# resource. Reduction % = reload_reduction_per_100_res * (resource_current
	# / 100). Capped at 80% so even a full pool doesn't trivialize reloads.
	# The trade (empty-damage penalty) lives in PlayerCombat._deal_damage.
	var reflex_per_100 := BehaviorModRegistry.get_active_param(&"hands", &"reflex_loader", &"reload_reduction_per_100_res", 0.0)
	if reflex_per_100 > 0.0:
		var reduction_pct := minf(80.0, reflex_per_100 * (_resource_current * 0.01))
		reload_time *= maxf(0.2, 1.0 - reduction_pct * 0.01)
	_reload_total = maxf(reload_time, 0.05)
	_reload_remain = _reload_total
	_reload_target = &"weapon"
	WeaponSounds.play_reload(w.weapon_base_id, global_position)
	weapon_ammo_changed.emit()
	# Route the reload as an upper-body overlay via UpperBodyAimModifier
	# rather than a full-body anim. Legs continue with whatever the
	# locomotion picker chose (idle, jog, strafe), so the player can
	# walk through a reload without the legs snapping into the
	# stationary reload pose. include_hips=false so the reload clip's
	# backward-lean balancing pose stays off the gameplay stance — the
	# arms work the magazine while the body keeps its locomotion frame.
	var modifier := _ensure_aim_modifier()
	if modifier != null:
		var skel := _find_player_skeleton()
		for key in ANIM_RELOAD:
			if anim_player != null and anim_player.has_animation(key):
				modifier.play_swing(skel, anim_player, key, _reload_total, false)
				break

# ── AIM_HOLD (Tripod / Aimed Shot) ───────────────────────────────────────────────

func aim_hold_accuracy_bonus() -> float:
	if _aim_hold_skill == null:
		return 0.0
	return _aim_hold_skill.aim_hold_accuracy_bonus


## Additive crit chance from the active aim hold (0 when not holding).
## player_combat folds this into _roll_crit.
func aim_hold_crit_bonus() -> float:
	if _aim_hold_skill == null:
		return 0.0
	return _aim_hold_skill.aim_hold_crit_bonus


## Movement lock requested by the active aim hold. False when no hold is
## active or when the active hold's skill explicitly allows movement.
func aim_hold_locks_movement() -> bool:
	return _aim_hold_skill != null and _aim_hold_skill.aim_hold_locks_movement


# Begin or refresh the aim hold for the given skill. No-op if already
# active for the same skill, or if the player is out of resource. Called
# from _cast_skill on RMB-press of an AIM_HOLD skill.
func _start_aim_hold(skill: Skill) -> void:
	if skill == null or skill.active_kind != Skill.ActiveKind.AIM_HOLD:
		return
	# Need at least a sliver of resource to enter the stance — otherwise
	# the next tick would just kick us straight back out.
	var infinite_res := DebugState.config != null and DebugState.config.infinite_resource
	if not infinite_res and _resource_current <= 0.0:
		return
	_aim_hold_skill = skill
	_show_aim_laser()
	# Movement-locking aim-holds (Tripod) drop the player into a crouch
	# stance for the duration. Only forces it if the player isn't already
	# crouched — if they are, leave their state alone so we don't yank
	# them back up when the hold ends.
	if skill.aim_hold_locks_movement and not _crouching:
		_set_crouch(true)
		_aim_hold_forced_crouch = _crouching  # may be false if a ceiling blocked the crouch


func _stop_aim_hold() -> void:
	if _aim_hold_skill == null:
		return
	_clear_aim_laser()
	_aim_hold_skill = null
	if _aim_hold_forced_crouch:
		_aim_hold_forced_crouch = false
		# Only uncrouch if the player isn't manually holding crouch — they
		# might be pressing Ctrl by the time the hold ends.
		if not Input.is_physical_key_pressed(KEY_CTRL):
			_set_crouch(false)


func _tick_aim_hold(delta: float) -> void:
	if _aim_hold_skill == null:
		return
	# Released? End the hold without spending any further resource on
	# this frame. resolve_skill(1) returns the current RMB binding, which
	# is the same skill we entered with as long as the weapon hasn't
	# changed. A weapon swap mid-hold should also end the hold.
	if not Input.is_action_pressed(&"alt_fire"):
		_stop_aim_hold()
		return
	var rmb := resolve_skill(1)
	if rmb != _aim_hold_skill:
		_stop_aim_hold()
		return
	# Drain resource over time. Infinite-resource debug mode skips the
	# spend (so the hold runs forever, intentional for testing).
	var infinite_res := DebugState.config != null and DebugState.config.infinite_resource
	if not infinite_res and resource_pool != null:
		var drain: float = _aim_hold_skill.aim_hold_resource_drain * delta
		if drain > 0.0:
			_resource_current = maxf(0.0, _resource_current - drain)
			_emit_resource_if_changed()
		if _resource_current <= 0.0:
			_stop_aim_hold()
			return
	# Track the cursor every tick while aim-holding — the gun (and the
	# red-dot laser that emerges from its muzzle) should stay aligned
	# with the cursor as the player drags it around, not just snap
	# once at press time. _face_direction is an instant set_look_at,
	# matches the rest of the game's no-lerp camera contract.
	var hold_aim := _aim_direction()
	if hold_aim != Vector3.ZERO:
		_face_direction(hold_aim)
	_update_aim_laser()


# ── Aim laser (Aimed Shot / Tripod visual) ─────────────────────────────────

func _show_aim_laser() -> void:
	if _aim_laser != null and is_instance_valid(_aim_laser):
		return
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = AIM_LASER_RADIUS
	cyl.bottom_radius = AIM_LASER_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.cap_top = false
	cyl.cap_bottom = false
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = AIM_LASER_COLOR
	mat.emission_enabled = true
	mat.emission = AIM_LASER_EMISSION
	mat.emission_energy_multiplier = AIM_LASER_EMISSION_ENERGY
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shadow_to_opacity = false
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.top_level = true
	add_child(mesh_inst)
	_aim_laser = mesh_inst
	_update_aim_laser()


func _clear_aim_laser() -> void:
	if _aim_laser != null and is_instance_valid(_aim_laser):
		_aim_laser.queue_free()
	_aim_laser = null


func _update_aim_laser() -> void:
	if _aim_laser == null or not is_instance_valid(_aim_laser):
		return
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		_aim_laser.visible = false
		return
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	var eff_range: float = _combat.effective_range(_aim_hold_skill, weapon) if _aim_hold_skill != null else 10.0
	if eff_range <= 0.0:
		eff_range = 10.0
	# Origin defaults to chest centre, but if a weapon model is mounted
	# (sniper, etc.) read its tuned muzzle so the laser sight emerges
	# from the actual barrel tip instead of floating off the chest.
	var p_pos: Vector3 = global_position + AIM_LASER_PLAYER_OFFSET
	var skel := _find_player_skeleton()
	if skel != null:
		var muzzle := WeaponAttachment.get_muzzle_position(skel, aim)
		if muzzle != Vector3.ZERO:
			p_pos = muzzle
	var target: Vector3 = p_pos + aim * eff_range
	var diff := target - p_pos
	var dist := diff.length()
	if dist < 0.05:
		_aim_laser.visible = false
		return
	_aim_laser.visible = true
	_aim_laser.global_position = (p_pos + target) * 0.5
	var dir := diff / dist
	if dir.dot(Vector3.UP) < -0.9999:
		_aim_laser.basis = Basis(Vector3(1.0, 0.0, 0.0), PI)
	else:
		_aim_laser.basis = Basis(Quaternion(Vector3.UP, dir))
	_aim_laser.scale = Vector3(1.0, dist, 1.0)


# ── CHANNEL_BEAM (Taser hold, Accelerator stream) ───────────────────────────

func _start_channel(skill: Skill, input_action: StringName) -> void:
	if skill == null or skill.active_kind != Skill.ActiveKind.CHANNEL_BEAM:
		return
	# Cooldown after resource depletion — prevents the glitchy start/stop
	# stutter when LMB is held but the resource pool just emptied.
	if _channel_depleted_cd > 0.0:
		return
	# Need at least a sliver of resource to begin — otherwise the next
	# tick would just kick us straight back out.
	var infinite_res := DebugState.config != null and DebugState.config.infinite_resource
	if not infinite_res and _resource_current <= 0.0:
		return
	_channel_skill = skill
	_channel_input_action = input_action
	_channel_tick_accum = 0.0
	# Channel-weapon SFX: one-shot zap at start + continuous hold loop
	# parented to this player so it follows positionally. Stored on
	# _channel_hold_player so _stop_channel can fade it out cleanly.
	# is_channel_weapon() returns true only for weapons with a hold_loop
	# registered in WeaponSounds (currently just the taser).
	var weapon_for_channel: Item = InventoryState.get_equipped(&"weapon")
	if weapon_for_channel != null and WeaponSounds.is_channel_weapon(weapon_for_channel.weapon_base_id):
		WeaponSounds.play_channel_start(weapon_for_channel.weapon_base_id, global_position)
		_channel_hold_player = WeaponSounds.play_channel_loop(weapon_for_channel.weapon_base_id, self)
	# Flame visual is SINGLE_CONE-only — Taser (CHAIN_LIGHTNING) draws
	# its own lightning arcs per tick, so it doesn't need the cone.
	if skill.targeting_mode == Skill.TargetingMode.SINGLE_CONE:
		_show_flame_visual()
		# MP: tell every other peer to render the flame on our avatar
		# too. Authority-routed RPC — only the firing peer (us) sends;
		# remote peers' copies of this node receive and call
		# _rpc_channel_flame_start. Range and damage_type are latched
		# now so the remote update loop has consistent values without
		# per-frame param replication.
		if NetState.is_in_lobby():
			var weapon: Item = InventoryState.get_equipped(&"weapon")
			var damage_type: StringName = &""
			var weapon_range: float = FLAME_DEFAULT_RANGE
			if weapon != null:
				damage_type = weapon.effective_damage_type()
				if weapon.weapon_range > 0.0:
					weapon_range = weapon.weapon_range
			_rpc_channel_flame_start.rpc(damage_type, weapon_range)


func _stop_channel() -> void:
	var was_flame_channel := _channel_skill != null and _channel_skill.targeting_mode == Skill.TargetingMode.SINGLE_CONE
	_channel_skill = null
	_channel_input_action = &""
	_channel_tick_accum = 0.0
	# Accelerator Resonance — reset stack so the next channel start
	# rebuilds from zero. Without this, lifting LMB and immediately
	# re-firing would skip past the ramp window.
	reset_accel_resonance()
	# Fade out + free the hold-loop SFX (no-op when nothing was playing).
	WeaponSounds.stop_channel_loop(_channel_hold_player)
	_channel_hold_player = null
	_hide_flame_visual()
	# Only broadcast a stop if this was a flame channel — Taser hold's
	# stop doesn't need an RPC because the lightning arcs were per-tick
	# (each one self-fades; nothing persistent to tear down on remotes).
	if was_flame_channel and NetState.is_in_lobby():
		_rpc_channel_flame_stop.rpc()


func _tick_channel(delta: float) -> void:
	if _channel_depleted_cd > 0.0:
		_channel_depleted_cd -= delta
	if _channel_skill == null:
		return
	# End on input release, weapon swap (resolve_skill returns something
	# different than what we started with), or death.
	if not _alive:
		_stop_channel()
		return
	if not Input.is_action_pressed(_channel_input_action):
		_stop_channel()
		return
	# Re-resolve the bound skill from the current weapon — if the player
	# swapped weapons mid-hold, the new fire/alt-fire is a different
	# skill and we need to bail.
	var current_skill: Skill = _resolve_channel_skill_for_input()
	if current_skill != _channel_skill:
		_stop_channel()
		return
	# Resource drain — continuous, not per-tick. Lets the resource bar
	# read smoothly instead of stair-stepping at the tick interval.
	var infinite_res := DebugState.config != null and DebugState.config.infinite_resource
	if not infinite_res and resource_pool != null:
		var drain: float = _channel_skill.channel_resource_per_sec * delta
		if drain > 0.0:
			_resource_current = maxf(0.0, _resource_current - drain)
			_emit_resource_if_changed()
		if _resource_current <= 0.0:
			_channel_depleted_cd = CHANNEL_DEPLETED_COOLDOWN
			_stop_channel()
			return
	# Channel-loop audio plays at the listener (not world-position) so
	# isometric movement doesn't shift volume/panning. No position
	# update needed — the listener already tracks the player.
	# Drive the flame visual every frame so it tracks the cursor in
	# real-time, not just on damage ticks. Skipped if the flame isn't
	# active (CHAIN_LIGHTNING channels never created it).
	if _flame_visual != null and _flame_visual.visible:
		_update_flame_visual()
	# Accelerator damage ramp — advance the elapsed timer every frame
	# so the multiplier lerps smoothly toward peak even between damage
	# ticks. Gated to the flame channel (accelerator stream) — Taser
	# tase uses CHAIN_LIGHTNING and doesn't have its own ramp.
	if _channel_skill.targeting_mode == Skill.TargetingMode.SINGLE_CONE:
		tick_accel_resonance(delta)
		_update_resonance_bar()
	# Damage tick — when accum exceeds the configured interval, resolve
	# a hit via the skill's targeting_mode through the standard combat
	# pipeline (so multistrike, talents, crits all apply).
	_channel_tick_accum += delta
	var interval: float = maxf(_channel_skill.channel_tick_interval, 0.05)
	while _channel_tick_accum >= interval:
		_channel_tick_accum -= interval
		var aim := _aim_direction()
		if aim == Vector3.ZERO:
			continue
		var weapon: Item = _combat.resolve_skill_source(_channel_skill)
		_combat.resolve_skill_hit(_channel_skill, aim, weapon)


# ── Channel flame visual (Energy Accelerator stream) ────────────────────────

const FLAME_SHADER: Shader = preload("res://scripts/prototype/jet_flame.gdshader")
const FLAME_DEFAULT_RANGE: float = 7.0
# Cone half-angle in radians — matches the 32° hit cone (16° each side).
const FLAME_HALF_ANGLE: float = deg_to_rad(16.0)
const FLAME_FAN_SEGMENTS: int = 16
# Height above floor for the flat fan. Slightly above the fog layer
# so it reads as a ground-level energy wash, not floating.
const FLAME_MUZZLE_HEIGHT: float = 0.2


static func _build_flame_fan_mesh() -> ArrayMesh:
	# Flat pizza-slice triangle fan in the XY plane. Apex at origin,
	# arc at Y=1.0 spanning ±FLAME_HALF_ANGLE. Scaled to range each tick.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Vertex 0: apex (muzzle)
	verts.append(Vector3.ZERO)
	uvs.append(Vector2(0.5, 1.0))  # center, muzzle end
	# Arc vertices
	for i in range(FLAME_FAN_SEGMENTS + 1):
		var t := float(i) / float(FLAME_FAN_SEGMENTS)
		var angle := lerpf(-FLAME_HALF_ANGLE, FLAME_HALF_ANGLE, t)
		verts.append(Vector3(sin(angle), cos(angle), 0.0))
		uvs.append(Vector2(t, 0.0))  # tip end
	# Triangle fan: apex + consecutive arc pairs.
	for i in range(FLAME_FAN_SEGMENTS):
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _ensure_flame_visual() -> void:
	if _flame_visual != null:
		return
	# Pivot in world space (top_level=true). +Y = aim direction.
	# The flat fan mesh lies in the XY plane — visible from the iso
	# camera, can't clip into the floor.
	var pivot := Node3D.new()
	pivot.name = "ChannelFlamePivot"
	pivot.top_level = true
	add_child(pivot)
	var mat := ShaderMaterial.new()
	mat.shader = FLAME_SHADER
	var inst := MeshInstance3D.new()
	inst.name = "ChannelFlameMesh"
	inst.mesh = _build_flame_fan_mesh()
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.position = Vector3(0.0, 0.0, 0.0)
	pivot.add_child(inst)
	pivot.visible = false
	_flame_visual = pivot
	_flame_material = mat


func _show_flame_visual() -> void:
	_ensure_flame_visual()
	if _flame_visual == null:
		return
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	var elem_color := Color(1.0, 0.5, 0.1, 1.0)
	if weapon != null:
		var elem := weapon.effective_damage_type()
		if elem != &"":
			elem_color = Item.damage_type_color(elem)
	_flame_material.set_shader_parameter(&"flame_color", Vector3(elem_color.r, elem_color.g, elem_color.b))
	var core := elem_color.lerp(Color(1.0, 0.95, 0.7, 1.0), 0.65)
	_flame_material.set_shader_parameter(&"inner_color", Vector3(core.r, core.g, core.b))
	_flame_material.set_shader_parameter(&"intensity", 0.0)
	_flame_material.set_shader_parameter(&"clip_ratio", 0.0)
	_flame_visual.visible = true
	_update_flame_visual()


func _hide_flame_visual() -> void:
	if _flame_visual == null:
		return
	_flame_visual.visible = false


func _update_flame_visual() -> void:
	if _flame_visual == null or _channel_skill == null:
		return
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		return
	var weapon: Item = _combat.resolve_skill_source(_channel_skill)
	var range_m := FLAME_DEFAULT_RANGE
	if weapon != null and weapon.weapon_range > 0.0:
		range_m = weapon.weapon_range
	_apply_flame_transform(aim, range_m)


# Update the flame on a REMOTE player's avatar. Aim comes from the
# player's facing direction (visual.basis.-z) since remote peers don't
# see the firing player's cursor. Range and damage_type were latched
# at _rpc_channel_flame_start time. Called every physics tick from
# _update_remote_anim while _remote_flame_active.
func _update_remote_flame_visual() -> void:
	if not _remote_flame_active or _flame_visual == null:
		return
	var aim := -visual.global_transform.basis.z
	_apply_flame_transform(aim, _remote_flame_range)


# Shared transform/scale logic for the flame pivot. Aim is flattened to
# horizontal, wall-clipped via shader uniform (not mesh scale), then
# turned into an orthonormal basis with +Y = aim. The flat fan mesh is
# always scaled to the weapon's full range — the shader discards pixels
# beyond the wall distance so the fan shape stays consistent.
func _apply_flame_transform(aim: Vector3, range_m: float) -> void:
	var aim_flat := aim
	aim_flat.y = 0.0
	if aim_flat.length_squared() < 0.0001:
		return
	var aim_norm := aim_flat.normalized()
	# Try the visible weapon model's muzzle first — keeps the accelerator
	# beam consistent with the per-weapon muzzle override the tuner sets.
	# Falls back to the legacy chest-height approximation for bare hands
	# or any path where the skeleton / weapon model isn't ready.
	var muzzle := global_position + Vector3(0.0, FLAME_MUZZLE_HEIGHT, 0.0)
	var skel := _find_player_skeleton()
	if skel != null:
		var weapon_muzzle := WeaponAttachment.get_muzzle_position(skel, aim_norm)
		if weapon_muzzle != Vector3.ZERO:
			muzzle = weapon_muzzle
	# Wall clip: raycast to find the wall distance, then pass a clip
	# ratio to the shader instead of shrinking the mesh. This keeps the
	# fan's angular spread constant — only the length gets capped.
	var clip_ratio: float = 0.0
	var space := get_world_3d().direct_space_state
	if space != null:
		if _flame_ray_query == null:
			_flame_ray_query = PhysicsRayQueryParameters3D.new()
			_flame_ray_query.collision_mask = 1
			_flame_ray_query.collide_with_areas = false
			_flame_ray_query.collide_with_bodies = true
		_flame_ray_query.from = muzzle
		_flame_ray_query.to = muzzle + aim_norm * range_m
		var hit := space.intersect_ray(_flame_ray_query)
		if not hit.is_empty():
			var wall_dist: float = maxf(0.5, muzzle.distance_to(hit["position"]) - 0.2)
			# clip_ratio: fraction of the fan to hide (0 = no clip, 1 = all hidden).
			clip_ratio = clampf(1.0 - wall_dist / range_m, 0.0, 1.0)
	if _flame_material != null:
		_flame_material.set_shader_parameter(&"clip_ratio", clip_ratio)
		# Intensity ramps with the resonance so the effect fades in over
		# the weapon's ramp-up time instead of popping to full brightness.
		var ramp := clampf(accel_ramp_ratio(), 0.0, 1.0)
		# Floor at 0.15 so there's always a hint of the stream on first frame,
		# then lerp up to full intensity (1.5) as the ramp completes.
		_flame_material.set_shader_parameter(&"intensity", lerpf(0.15, 1.5, ramp))
	# Basis: +Y = aim, +Z = world up.
	var ref_up := Vector3.UP
	var x_axis := aim_norm.cross(ref_up).normalized()
	var z_axis := x_axis.cross(aim_norm).normalized()
	var flame_basis := Basis(x_axis, aim_norm, z_axis)
	_flame_visual.global_transform = Transform3D(flame_basis, muzzle)
	var mesh_inst := _flame_visual.get_node_or_null(^"ChannelFlameMesh") as MeshInstance3D
	if mesh_inst != null:
		mesh_inst.scale = Vector3(range_m, range_m, 1.0)


# ── Remote channel-flame replication ────────────────────────────────────────
# Local player's _start_channel / _stop_channel call these RPCs to tell
# every other peer's copy of THIS player node to show/hide a flame
# attached to its avatar. Authority routes the call: only the firing
# player sends; every other peer receives. The visual orientation is
# updated each frame by _update_remote_flame_visual using the remote
# player's facing direction (the cursor isn't replicated).

var _remote_flame_active: bool = false
var _remote_flame_range: float = FLAME_DEFAULT_RANGE
# Cached ray query for the flame's wall-clip raycast. Built once and
# reused every channel tick — _apply_flame_transform runs every physics
# frame while a flame channel is held, and PhysicsRayQueryParameters3D
# is heavier than re-setting from/to/mask on an existing instance.
# Same pattern as prototype_projectile.gd._ray_query.
var _flame_ray_query: PhysicsRayQueryParameters3D = null


@rpc("authority", "call_remote", "reliable")
func _rpc_channel_flame_start(damage_type: StringName, weapon_range: float) -> void:
	_remote_flame_active = true
	_remote_flame_range = weapon_range if weapon_range > 0.0 else FLAME_DEFAULT_RANGE
	_ensure_flame_visual()
	var elem_color := Color(1.0, 0.5, 0.1, 1.0)
	if damage_type != &"":
		elem_color = Item.damage_type_color(damage_type)
	_flame_material.set_shader_parameter(&"flame_color", Vector3(elem_color.r, elem_color.g, elem_color.b))
	var core := elem_color.lerp(Color(1.0, 0.95, 0.7, 1.0), 0.65)
	_flame_material.set_shader_parameter(&"inner_color", Vector3(core.r, core.g, core.b))
	_flame_material.set_shader_parameter(&"intensity", 1.5)
	_flame_visual.visible = true


@rpc("authority", "call_remote", "reliable")
func _rpc_channel_flame_stop() -> void:
	_remote_flame_active = false
	if _flame_visual != null:
		_flame_visual.visible = false


# Look up the skill currently bound to the channel's input action so we
# can detect weapon swaps mid-hold. LMB = main weapon's fire_skill, RMB
# follows the same resolve_skill(1) path used by the cast loop.
func _resolve_channel_skill_for_input() -> Skill:
	if _channel_input_action == &"fire":
		var weapon: Item = InventoryState.get_equipped(&"weapon")
		return weapon.fire_skill if weapon != null else null
	if _channel_input_action == &"alt_fire":
		return resolve_skill(1)
	return null


func _tick_reload(delta: float) -> void:
	if _reload_remain <= 0.0:
		return
	_reload_remain -= delta
	if _reload_remain > 0.0:
		return
	_reload_remain = 0.0
	_reload_total = 0.0
	# Refill the magazine on the slot we started the reload on. If the
	# player swapped weapons mid-reload, the slot may be empty or carry
	# a different item — bail rather than fill the wrong magazine.
	if _reload_target != &"":
		var w: Item = InventoryState.get_equipped(_reload_target)
		if w != null and w.is_bullet_weapon():
			w.ammo_current = w.ammo_max
	_reload_target = &""
	weapon_ammo_changed.emit()

# Resource-cost gating for bullet vs energy weapons. Returns true when
# the skill can fire RIGHT NOW given the item's ammo state and the
# player's resource pool. Used by the LMB multi-fire path AND the
# single-skill cast path so both gates apply consistently.
func _skill_can_fire(item: Item, skill: Skill, is_main: bool) -> bool:
	if not is_main:
		return true  # extra arms always fire free (existing behaviour)
	if item != null and item.is_bullet_weapon():
		# Skill.ammo_cost defaults to 1; shotgun's double-barrel sets it
		# to 2 so the gate refuses to fire without a full pair available.
		var cost: int = maxi(1, skill.ammo_cost)
		return item.ammo_current >= cost and not is_reloading()
	if skill.resource_cost <= 0:
		return true
	var infinite_resource := DebugState.config != null and DebugState.config.infinite_resource
	return infinite_resource or _resource_current >= float(skill.resource_cost)

# Pay the cost of firing — either decrement ammo (bullet weapons) or
# spend resource (energy weapons). Auto-triggers reload when the magazine
# can no longer afford the next shot's ammo_cost (so a 2-cost double-
# barrel reload trips when 1 round remains, not 0).
func _skill_pay_cost(item: Item, skill: Skill, is_main: bool) -> void:
	if not is_main:
		return
	if item != null and item.is_bullet_weapon():
		var cost: int = maxi(1, skill.ammo_cost)
		item.ammo_current = maxi(0, item.ammo_current - cost)
		weapon_ammo_changed.emit()
		# Reload trigger looks at NEXT-shot affordability rather than
		# strict empty: a shotgun with 1 round can't fire double-barrel,
		# so we kick a reload pre-emptively in that case too. Uses the
		# fire skill (LMB primary) as the cost-floor reference; if the
		# main weapon's primary fire is single-cost, this collapses to
		# the prior "reload at empty" behaviour.
		var min_next_cost: int = 1
		if item.fire_skill != null:
			min_next_cost = maxi(1, item.fire_skill.ammo_cost)
		if item.ammo_current < min_next_cost:
			start_reload()
		return
	if skill.resource_cost <= 0:
		return
	var infinite_resource := DebugState.config != null and DebugState.config.infinite_resource
	if not infinite_resource:
		_spend_resource(skill.resource_cost)


# ── Effective-stat readers (UI display) ──────────────────────────────────────
# These combine the equipped main weapon's rolled stats with the gear-wide
# bonus aggregates in _gear_* fields. The character panel reads these so
# what the player sees matches what combat actually computes — accuracy
# and crit in particular are mostly weapon-driven, with gear contributing
# small offsets.

## True when a main-hand weapon is equipped. Used by the character panel
## to decide whether to render weapon-derived stats as concrete values
## or as "—".
func has_main_weapon() -> bool:
	var w: Item = InventoryState.get_equipped(&"weapon")
	return w != null and w.damage_max > 0


## Effective accuracy as a percentage (0–100). Pure weapon stat times
## (1 + gear_hit_chance_bonus); returns -1 when no weapon is equipped so
## the UI can render a dash.
func get_effective_accuracy_pct() -> int:
	var w: Item = InventoryState.get_equipped(&"weapon")
	if w == null or w.damage_max <= 0:
		return -1
	var acc := w.effective_accuracy() * (1.0 + _gear_hit_chance_bonus)
	return int(round(clampf(acc, 0.0, 1.0) * 100.0))


## Effective crit-chance as a percentage. Weapon's effective_crit_chance
## (which is non-zero only if the weapon rolls crit) plus the gear-wide
## crit_chance_bonus aggregate. Returns -1 when no weapon is equipped.
func get_effective_crit_pct() -> int:
	var w: Item = InventoryState.get_equipped(&"weapon")
	if w == null or w.damage_max <= 0:
		return -1
	var crit := w.effective_crit_chance() + _gear_crit_chance_bonus
	return int(round(maxf(crit, 0.0) * 100.0))


## Effective attack-speed multiplier as a percentage delta from 1.0.
## "+15%" means the player attacks 15% faster than the skill's base
## cooldown. Returns -1 when no weapon is equipped.
func get_effective_atk_speed_delta_pct() -> int:
	var w: Item = InventoryState.get_equipped(&"weapon")
	if w == null or w.damage_max <= 0:
		return -1
	var atk := w.effective_attack_speed() * (1.0 + _gear_attack_speed_bonus)
	return int(round((atk - 1.0) * 100.0))

func get_effective_cdr_pct() -> int:
	return int(round(_gear_cooldown_reduction * 100.0))


## Move-speed bonus percentage from gear (additive to base 100%).
func get_effective_move_speed_pct() -> int:
	return _gear_move_speed_bonus


## Damage reduction (armor) percentage from gear (0–40).
func get_effective_armor() -> float:
	return _gear_damage_reduction

# ── Unarmed glove modifiers ──────────────────────────────────────────────────
# Reads stat_modifiers from equipped gloves so unarmed strikes benefit
# from "Spiked Gloves" etc. Returns 0 when no gloves equipped.

func get_unarmed_damage_bonus() -> int:
	var gloves: Item = InventoryState.get_equipped(&"hands")
	if gloves == null:
		return 0
	return gloves.get_effective_modifier(&"unarmed_damage_bonus")

func get_unarmed_stun_chance() -> float:
	var gloves: Item = InventoryState.get_equipped(&"hands")
	if gloves == null:
		return 0.0
	return float(gloves.get_effective_modifier(&"unarmed_stun_chance")) * 0.01

func get_unarmed_aoe_radius() -> float:
	var gloves: Item = InventoryState.get_equipped(&"hands")
	if gloves == null:
		return 0.0
	return float(gloves.get_effective_modifier(&"unarmed_aoe_radius"))

func get_cooldown_ratio(skill: Skill) -> float:
	if skill != null and _shield != null and _shield.is_shield_skill(skill):
		return _shield.get_cooldown_ratio(skill)
	if skill != null and _grenade != null and _grenade.is_grenade_skill(skill):
		return _grenade.get_cooldown_ratio(skill)
	if skill != null and _recovery != null and _recovery.is_recovery_skill(skill):
		return _recovery.get_cooldown_ratio(skill)
	if _combat == null:
		return 0.0
	return _combat.get_cooldown_ratio(skill)


func get_cooldown_remain(skill: Skill) -> float:
	if skill == null:
		return 0.0
	if _shield != null and _shield.is_shield_skill(skill):
		return _shield.get_cooldown_remain(skill)
	if _grenade != null and _grenade.is_grenade_skill(skill):
		return _grenade.get_cooldown_remain(skill)
	if _recovery != null and _recovery.is_recovery_skill(skill):
		return _recovery.get_cooldown_remain(skill)
	if _combat == null:
		return 0.0
	return _combat.get_cooldown_remain(skill)

# Public entry for the Count Exile expire callback. PrototypeEnemy._tick_curse
# calls this when the curse timer drains; we forward to PlayerCombat where
# the shot's damage / VFX live. Thin proxy so the enemy doesn't reach into
# the player's private _combat field.
func fire_exile_shot(target: Node3D) -> void:
	if _combat == null:
		return
	_combat.fire_exile_shot(target)

func _die() -> void:
	if _is_remote_player():
		return
	_alive = false
	died.emit()
	_sprinting = false
	if _chromatic != null:
		_chromatic.set_active(false)
	_drone_swarm.cleanup()
	_ied.cleanup()
	_doomsayer.cleanup()
	_shield.cleanup()
	_grenade.cleanup()
	# Drop the upper-body aim/swing overlay so the death animation drives
	# the full spine+arms+legs chain. Without this the modifier keeps
	# applying its sampled fire/swing pose to the upper body each frame
	# and the death clip only reads on the legs.
	if _aim_modifier != null and is_instance_valid(_aim_modifier):
		_aim_modifier.active = false
	# XBotAnimations exposes deaths as xbot/death_0..N, not the generic
	# xbot/death. Pick a random one via the library helper and fall back
	# to the legacy candidate list (Quaternius / older meshes) if the
	# library isn't installed on this mesh.
	var death_anim: StringName = XBotAnimations.random_death_anim()
	var played := _play_anim([death_anim] as Array[StringName], 1.0)
	if not played:
		played = _play_anim(ANIM_DEATH, 1.0)
	if not played and anim_player != null:
		anim_player.pause()
	if visual != null:
		_death_tween = create_tween()
		_death_tween.tween_property(visual, "scale:y", 0.15, 0.5)
	await get_tree().create_timer(DEATH_HOLD).timeout
	_show_death_screen()

# Update both the player's current position and the respawn anchor used by
# respawn() / NG+. Called by PrototypeRoot._move_player_to_spawn() after the
# level builder has placed a player_spawn marker — without this, the player
# would respawn at its scene-defined transform after death.
func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos
	global_position = pos


## Called by environmental kill paths (PitBuilder, future DoT/explosion
## causes) just before take_damage so the death screen can pick a
## cause-specific snarky message. Cleared on respawn.
func set_death_cause(cause: StringName) -> void:
	_death_cause = cause


func _show_death_screen() -> void:
	var screen := DeathScreen.new()
	screen.continue_pressed.connect(respawn)
	add_child(screen)
	screen.show_death(PlayerState.hardcore, _death_cause)


func respawn() -> void:
	if _is_remote_player():
		return
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
		_death_tween = null
	_death_cause = &""
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_knockback_remain = 0.0
	_lmb_busy = false
	_skill_busy = false
	_recompute_stat_bonuses()
	_health = max_health
	_alive = true
	_combat.clear_cooldowns()
	_drone_swarm.reconcile()
	_doomsayer.reconcile()
	if visual != null:
		visual.scale = Vector3.ONE
	if resource_pool != null:
		_resource_current = float(resource_pool.max_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)
	health_changed.emit(_health, max_health)
	respawned.emit()
	_play_anim(ANIM_IDLE)

## World position of the cursor on the player's Y plane. Used by
## chain lightning's magnet-target picker to find the enemy nearest
## the cursor rather than the enemy nearest the aim ray. Returns the
## player's own position when the cursor isn't projectable (FPS mode,
## camera missing, etc.) so callers don't have to special-case ZERO.
func cursor_world_position() -> Vector3:
	var offset := _cursor_offset()
	if offset.length_squared() < 0.0001:
		return global_position
	return global_position + offset


func _cursor_offset() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var mouse_pos := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var dir := _camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.001:
		return Vector3.ZERO
	var t: float = (global_position.y - from.y) / dir.y
	if t < 0.0:
		return Vector3.ZERO
	var flat := (from + dir * t) - global_position
	flat.y = 0.0
	return flat


# Grenade throw target relative to the player. Iso uses the cursor on the
# ground plane (existing behaviour); FPS throws straight forward along the
# camera's horizontal direction at ~3/4 of MAX_THROW_RANGE — far enough
# to clear the player's near-camera blind spot, short enough to feel like
# an aimed lob rather than a pitch.
const _GRENADE_FPS_THROW_DISTANCE: float = 9.0

func _grenade_throw_offset() -> Vector3:
	if not _fps_mode:
		return _cursor_offset()
	if _fps_camera == null:
		return Vector3.ZERO
	var fwd := -_fps_camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return Vector3.ZERO
	return fwd.normalized() * _GRENADE_FPS_THROW_DISTANCE

func _aim_direction() -> Vector3:
	if _fps_mode:
		var forward := -_fps_camera.global_transform.basis.z
		return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.ZERO
	if _lock_target != null:
		# 3D aim from player chest to target chest — angles up toward lifted
		# enemies (telekinesis grab) instead of firing flat underneath them.
		var chest := Vector3(0.0, 1.0, 0.0)
		var to_target := (_lock_target.global_position + Vector3(0.0, 0.9, 0.0)) - (global_position + chest)
		if to_target.length_squared() > 0.0001:
			return to_target.normalized()
	var offset := _cursor_offset()
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	return offset.normalized()

# Engages on LMB-press over a hovered enemy; releases on LMB-up or when the
# target dies / leaves the enemies group. FPS mode uses its own raycast hover
# and skips lock-on entirely.
func _update_lock_target() -> void:
	if _fps_mode:
		_lock_target = null
		return
	if not Input.is_action_pressed(SKILL_INPUTS[0]):
		_lock_target = null
		return
	if _lock_target != null:
		if not is_instance_valid(_lock_target) or not _lock_target.is_in_group(&"enemies"):
			_lock_target = null
	if _lock_target == null and Input.is_action_just_pressed(SKILL_INPUTS[0]):
		for n in get_tree().get_nodes_in_group(&"tooltip_target"):
			if not is_instance_valid(n):
				continue
			if n is Node3D and n.is_in_group(&"enemies"):
				_lock_target = n
				break

# Three-state V-key cycler:
#   - in FPS                           → exit FPS (back to iso default)
#   - in iso with tilted pitch         → reset iso pitch to default
#   - in iso already at default pitch  → enter FPS
# Lets a single key both undo a debug tilt and toggle between camera modes.
func _handle_toggle_view() -> void:
	if _fps_mode:
		_toggle_fps()
		return
	var iso_cam := _camera as PrototypeCamera
	if iso_cam != null and not iso_cam.is_at_default_pitch():
		iso_cam.reset_pitch()
		return
	_toggle_fps()


func _toggle_fps() -> void:
	if _fps_transitioning:
		return
	_fps_transitioning = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, 0.1).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func() -> void:
		_fps_mode = not _fps_mode
		if _fps_mode:
			_fps_camera.rotation.y = visual.rotation.y
			_fps_pitch = 0.0
			_fps_camera.rotation.x = 0.0
			_fps_camera.position = FPS_CROUCH_OFFSET if _crouching else FPS_HEAD_OFFSET
			_fps_camera.current = true
			_set_meshes_visible(visual, false)
			_set_group_cast_shadow(&"fps_ceiling", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
			_set_fps_fog(true)
			if _crosshair_root != null:
				_crosshair_root.visible = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			_clear_fps_hover()
			_fps_camera.current = false
			_camera.current = true
			_fps_camera.position = FPS_HEAD_OFFSET
			_set_fps_fog(false)
			_set_group_cast_shadow(&"fps_ceiling", GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
			_set_meshes_visible(visual, true)
			if _crosshair_root != null:
				_crosshair_root.visible = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	)
	tween.tween_property(_fade_rect, "color:a", 0.0, 0.15).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func() -> void:
		_fps_transitioning = false
	)

func _set_meshes_visible(node: Node, make_visible: bool) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = make_visible
	for child in node.get_children():
		_set_meshes_visible(child, make_visible)

func _set_group_cast_shadow(group: StringName, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	for node: Node in get_tree().get_nodes_in_group(group):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).cast_shadow = mode

func _set_fps_fog(enabled: bool) -> void:
	if _fps_fill_light != null:
		_fps_fill_light.visible = enabled
	if _world_env != null:
		_world_env.fog_enabled = enabled

func _build_light_mount() -> void:
	if visual == null:
		return
	InventoryState.equipment_changed.connect(_on_equipment_changed)
	InventoryState.items_overflowed.connect(_on_items_overflowed)
	_apply_light_item()

func _on_equipment_changed(slot: StringName) -> void:
	_recompute_stat_bonuses()
	if slot == &"head":
		_apply_light_item()
	elif slot == &"weapon":
		light_changed.emit(_light_on)
		# Cancel any in-flight reload — the new weapon has its own
		# magazine state. HUD repaints via the same signal it listens to
		# for shots/finishes.
		_reload_remain = 0.0
		_reload_total = 0.0
		_reload_target = &""
		weapon_ammo_changed.emit()
		# Swap the visible weapon model on the hand bone to match.
		_apply_weapon_model()
	elif slot == &"offhand":
		# No stacking: removing the offhand drops every effect it
		# granted. Re-equipping a different shield offhand requires
		# the player to re-press RMB to activate.
		_shield.cleanup()
	elif slot == &"consumable":
		_recovery.sync_consumable()

func _on_items_overflowed(overflow: Array[Item]) -> void:
	for displaced_item in overflow:
		drop_item(displaced_item)


func get_shield_buff_kind() -> Skill.ActiveKind:
	if _shield == null:
		return Skill.ActiveKind.NONE
	return _shield.get_shield_buff_kind()


func get_shield_buff_state() -> Dictionary:
	if _shield == null:
		return {}
	return _shield.get_shield_buff_state()


# Translucent white sphere parented to the player; toggled by the
# shield_buff_changed signal. Built once in _ready and reused across
# activations so we don't churn on rapid HOLD on/off cycles.
var _shield_visual: MeshInstance3D = null

const SHIELD_VISUAL_RADIUS: float = 1.05
const SHIELD_VISUAL_HEIGHT_OFFSET: float = 1.0
const SHIELD_VISUAL_ALPHA: float = 0.06

func _build_shield_visual() -> void:
	var mesh_inst := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = SHIELD_VISUAL_RADIUS
	# SphereMesh.height is the FULL diameter — must be 2×radius or the mesh
	# pinches into a lemon shape.
	sph.height = SHIELD_VISUAL_RADIUS * 2.0
	sph.radial_segments = 24
	sph.rings = 12
	mesh_inst.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, SHIELD_VISUAL_ALPHA)
	# Faint emissive so the bubble reads against a black corridor without
	# adding meaningful illumination to the scene.
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.92, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.4
	# Render both faces so the player inside still sees the bubble's far
	# wall — cull_back would leave the camera looking through an open hole.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Don't write depth — the player's body should remain visible THROUGH
	# the bubble. With depth-write on, the alpha sphere occludes itself and
	# the model behind it inconsistently.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lift to chest height so the sphere encloses the model from feet to
	# slightly above head rather than centering on the floor.
	mesh_inst.position = Vector3(0.0, SHIELD_VISUAL_HEIGHT_OFFSET, 0.0)
	mesh_inst.visible = false
	add_child(mesh_inst)
	_shield_visual = mesh_inst


func _on_shield_buff_changed_visual(active: bool, _pool: int, _pool_max: int, _reduction: float, _cd_remain: float, _cd_total: float, _dur_remain: float) -> void:
	if _shield_visual != null:
		_shield_visual.visible = active


func drop_item(item: Item) -> void:
	var drop_pos := global_position + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
	# Manual drops have no owner — anyone can pick them up.
	var container := get_tree().get_first_node_in_group(&"pickups_container") as PickupsContainer
	if container != null:
		if NetState.is_in_lobby() and NetState.is_client():
			# Client: ask host to spawn the drop for us.
			_request_drop_item.rpc_id(1, item.to_dict(), drop_pos.x, drop_pos.z)
			return
		container.spawn_item(item, drop_pos)
		return
	# Fallback: direct instantiate (no PickupsContainer in scene).
	var parent := get_parent()
	if parent == null:
		return
	var pickup := ITEM_PICKUP_SCENE.instantiate() as Node3D
	pickup.configure(item)
	parent.add_child(pickup)
	pickup.global_position = drop_pos


@rpc("any_peer", "call_remote", "reliable")
func _request_drop_item(item_data: Dictionary, pos_x: float, pos_z: float) -> void:
	if not multiplayer.is_server():
		return
	var dropped_item := Item.from_dict(item_data)
	var container := get_tree().get_first_node_in_group(&"pickups_container") as PickupsContainer
	if container != null:
		container.spawn_item(dropped_item, Vector3(pos_x, 0.0, pos_z))

func _apply_light_item() -> void:
	if visual == null:
		return
	if _equipped_light != null:
		_equipped_light.queue_free()
		_equipped_light = null
	if _tactical_overlay != null:
		_tactical_overlay.queue_free()
		_tactical_overlay = null
	var head: Item = InventoryState.get_equipped(&"head")
	if head == null or head.light_mod == Item.LightMod.NONE:
		_light_on = false
		light_changed.emit(false)
		return
	# RADIANT lamps are an ambient bubble around the player — an
	# omnidirectional light that lives at the chest, no cursor tracking.
	# Everything else (FLASHLIGHT / UV / SCANNER) is a SpotLight3D that
	# the aim helpers point at the cursor each frame.
	var light: Light3D
	if head.light_mod == Item.LightMod.RADIANT:
		var omni := OmniLight3D.new()
		omni.omni_range = head.light_range
		omni.omni_attenuation = 1.4
		omni.shadow_enabled = true
		# Tight bias / normal_bias to keep the player's helmet light from
		# bleeding through wall geometry onto the outer faces of walls —
		# was 0.05 (looser than Godot's 0.02 default), which produced a
		# visible halo on the outside of any wall the player stood near.
		# Matches the ceiling fluorescent values in lighting_builder.
		omni.shadow_bias = 0.005
		omni.shadow_normal_bias = 0.5
		# Match the ceiling fluorescent fix — Godot's default of 1.0 for
		# this property let the headlight scatter into volumetric fog and
		# produce a screen-space V-halo through walls / past the void cover.
		omni.light_volumetric_fog_energy = 0.0
		omni.light_color = head.light_color
		omni.light_energy = head.light_energy
		light = omni
	else:
		var spot := SpotLight3D.new()
		spot.spot_angle = 50.0
		spot.spot_attenuation = 1.0
		spot.spot_angle_attenuation = 0.6
		spot.shadow_enabled = true
		spot.shadow_bias = 0.005
		spot.shadow_normal_bias = 0.5
		spot.light_volumetric_fog_energy = 0.0
		spot.light_color = head.light_color
		spot.light_energy = head.light_energy
		spot.spot_range = head.light_range
		match head.light_mod:
			Item.LightMod.FLASHLIGHT:
				spot.light_energy *= 1.5
				spot.spot_range *= 1.2
			Item.LightMod.UV:
				spot.spot_angle = 45.0
			Item.LightMod.SCANNER:
				spot.spot_angle = 60.0
		light = spot
	# Keep the player layer in light_cull_mask (player is lit) but remove
	# it from shadow_caster_mask so the player model doesn't cast a shadow
	# from their own headlamp.
	light.shadow_caster_mask &= ~(1 << (PLAYER_VISUAL_LAYER - 1))
	light.position = FLASHLIGHT_OFFSET
	_light_on = true
	light.visible = true
	_equipped_light = light
	visual.add_child(light)
	_update_flashlight_pitch(0.0)
	# SCANNER mod projects a tactical range overlay on the ground.
	if head.light_mod == Item.LightMod.SCANNER:
		_tactical_overlay = TacticalOverlay.new()
		add_child(_tactical_overlay)
		_tactical_overlay.set_active(true)
	light_changed.emit(_light_on)


func is_scanner_active() -> bool:
	var head: Item = InventoryState.get_equipped(&"head")
	return head != null and head.light_mod == Item.LightMod.SCANNER and _light_on


# Number of slow-pool Area3Ds the player currently overlaps. Counted (not
# bool) so overlapping puddles + corner cases where two body_entered fire
# before any body_exited don't desync the slow.
var _slow_pool_count: int = 0

## Increments the slow-pool overlap count. Called by DecalBuilder's
## puddle Area3D when the player walks in. Emits slow_pool_changed only
## on the 0→1 transition so HUD listeners don't churn entries when the
## player walks across overlapping pools.
func enter_slow_pool() -> void:
	var was_in := _slow_pool_count > 0
	_slow_pool_count += 1
	if not was_in:
		slow_pool_changed.emit(true)

## Decrements the slow-pool overlap count. Called on body_exited. Emits
## slow_pool_changed only on the N→0 transition.
func exit_slow_pool() -> void:
	if _slow_pool_count <= 0:
		return
	_slow_pool_count -= 1
	if _slow_pool_count == 0:
		slow_pool_changed.emit(false)

func _slow_pool_factor() -> float:
	if _slow_pool_count <= 0:
		return 1.0
	return Traction.slow_factor_for_surface(&"water")


# ── Blood pool ground effect ─────────────────────────────────────────
# Distinct from oil/water slow_pool because blood has TWO effects:
# a mild slow AND a slip-friction model (less decel = skid). Plus a
# stumble-chance roll on entry. All gated by Traction:
#   T0  — full slip + stumble + mild slow
#   T1  — stumble immunity, slip-friction stops, slow still applies
#   T2+ — slow immune too (mirrors oil/water)
# Counted (not bool) for the same overlapping-pools rationale as
# _slow_pool_count. Future ground types (frozen, fire) plug in here
# with their own _X_pool_count + _X_pool_factor() pair.
var _blood_pool_count: int = 0
var _blood_stumble_remaining: float = 0.0


## Increments the blood-pool overlap count. Called by the slip-zone
## Area3D under each pool (see PrototypeAttackIndicator
## .spawn_blood_slip_zone). Rolls the stumble chance on the
## 0→1 transition only, so walking from one pool into an overlapping
## one doesn't keep re-rolling.
func enter_blood_pool() -> void:
	var was_in := _blood_pool_count > 0
	_blood_pool_count += 1
	if not was_in:
		blood_pool_changed.emit(true)
		var chance: float = Traction.stumble_chance_for_surface(&"blood")
		if chance > 0.0 and randf() < chance:
			_blood_stumble_remaining = Traction.stumble_duration_for_surface(&"blood")


## Decrements the blood-pool overlap count. Emits blood_pool_changed
## only on the N→0 transition.
func exit_blood_pool() -> void:
	if _blood_pool_count <= 0:
		return
	_blood_pool_count -= 1
	if _blood_pool_count == 0:
		blood_pool_changed.emit(false)

func _blood_pool_factor() -> float:
	if _blood_pool_count <= 0:
		return 1.0
	return Traction.slow_factor_for_surface(&"blood")


## Decel-friction multiplier on blood. < 1.0 means LESS friction →
## skid past stop. Asymptotically restored to ~1.0 by traction.
func _blood_friction_factor() -> float:
	if _blood_pool_count <= 0:
		return 1.0
	return Traction.friction_factor_for_surface(&"blood")


## Currently stumbling from a slip-chance roll? Movement code zeroes
## wish_dir while this is true so the player can't input new accel
## during the brief stumble window.
func is_stumbling() -> bool:
	return _blood_stumble_remaining > 0.0


## Returns the EFFECTS the player is currently subject to from
## overlapping ground surfaces, keyed by effect id. Each value is the
## list of contributing surface_ids. Used by the HUD to render one
## debuff entry per effect (not per surface) so the player learns
## "Slippery" / "Poor Traction" once and recognizes them across
## causes. Future surface-specific effects (Burning from fire,
## Corroding from acid, Frozen from ice) plug in the same way —
## append to the appropriate effect's source list when their
## surface is overlapped.
##
## Effect ids:
##   &"slippery"      — any surface with friction loss OR stumble chance
##   &"poor_traction" — any surface with move-speed slow
##
## Below-threshold effects are excluded so a surface that's been
## fully mitigated by traction doesn't trigger a debuff icon.
func get_active_ground_effects() -> Dictionary:
	var effects: Dictionary = {}
	for surface_id in _active_ground_surfaces():
		if Traction.slow_factor_for_surface(surface_id) < 0.99:
			if not effects.has(&"poor_traction"):
				effects[&"poor_traction"] = []
			(effects[&"poor_traction"] as Array).append(surface_id)
		var has_slip := Traction.friction_factor_for_surface(surface_id) < 0.99
		var has_stumble := Traction.stumble_chance_for_surface(surface_id) > 0.0
		if has_slip or has_stumble:
			if not effects.has(&"slippery"):
				effects[&"slippery"] = []
			(effects[&"slippery"] as Array).append(surface_id)
	return effects


# Currently-overlapped ground surfaces, by surface_id. Per-pool
# counters (_slow_pool_count, _blood_pool_count) stay as the
# source-of-truth for "am I overlapping X"; this just translates
# them into the surface_id namespace used by Traction. Future ground
# types add their counter + a line here.
func _active_ground_surfaces() -> Array[StringName]:
	var out: Array[StringName] = []
	if _slow_pool_count > 0:
		out.append(&"water")
	# Blood counts as an active surface either while the player is
	# physically in a slip-zone pool OR while they still have blood
	# on their shoes (bloody_steps_remaining is the same counter that
	# drives the visual footprint trail — set by Footsteps when the
	# player steps in blood and decremented each subsequent step).
	# Tying the debuff lifetime to the trail count means the player
	# slips for as long as they're visibly tracking blood — the
	# debuff has the same dramatic window as the visual.
	var has_blood_residue: bool = int(get_meta(&"bloody_steps_remaining", 0)) > 0
	if _blood_pool_count > 0 or has_blood_residue:
		out.append(&"blood")
	return out

func _update_light_visibility() -> void:
	if _equipped_light != null:
		_equipped_light.visible = _light_on
	if _tactical_overlay != null:
		_tactical_overlay.set_active(_light_on)

func _update_flashlight_pitch(cursor_distance: float) -> void:
	if not _equipped_light is SpotLight3D:
		return
	var forward_offset := -FLASHLIGHT_OFFSET.z
	var d := maxf(0.01, cursor_distance - forward_offset)
	# The aim target lifts off the floor as the cursor moves away, going from
	# "floor in front of player" through the flashlight's own height (parallel)
	# and ending slightly above it (a touch of upward tilt at the far end).
	var lift_t := clampf(cursor_distance / FLASHLIGHT_LEVEL_DISTANCE, 0.0, 1.0)
	var vertical := FLASHLIGHT_OFFSET.y - lift_t * (FLASHLIGHT_OFFSET.y + FLASHLIGHT_OVER_LIFT)
	var pitch := atan2(vertical, d)
	pitch = clampf(pitch, -deg_to_rad(FLASHLIGHT_MAX_UP_DEG), deg_to_rad(FLASHLIGHT_MAX_PITCH_DEG))
	_equipped_light.rotation.x = -pitch

# Top-down aim: set the flashlight's world rotation directly so its yaw follows
# the cursor instead of the player visual. Pitch reuses the same lift curve as
# the FPS path (target Y derived from cursor distance).
func _aim_flashlight_at_cursor() -> void:
	if not _equipped_light is SpotLight3D:
		return
	var offset := _cursor_offset()
	var cursor_distance := offset.length()
	var horiz_dir: Vector3
	if cursor_distance > 0.0001:
		horiz_dir = offset / cursor_distance
	elif visual != null:
		horiz_dir = -visual.global_transform.basis.z
		horiz_dir.y = 0.0
		if horiz_dir.length_squared() < 0.0001:
			return
		horiz_dir = horiz_dir.normalized()
	else:
		return
	var forward_offset := -FLASHLIGHT_OFFSET.z
	var d := maxf(0.01, cursor_distance - forward_offset)
	var lift_t := clampf(cursor_distance / FLASHLIGHT_LEVEL_DISTANCE, 0.0, 1.0)
	var vertical := FLASHLIGHT_OFFSET.y - lift_t * (FLASHLIGHT_OFFSET.y + FLASHLIGHT_OVER_LIFT)
	var pitch := atan2(vertical, d)
	pitch = clampf(pitch, -deg_to_rad(FLASHLIGHT_MAX_UP_DEG), deg_to_rad(FLASHLIGHT_MAX_PITCH_DEG))
	var clamped_vertical := tan(pitch) * d
	var fl_pos := _equipped_light.global_position
	var target := fl_pos + horiz_dir * d + Vector3(0.0, -clamped_vertical, 0.0)
	_equipped_light.look_at(target, Vector3.UP)

# Slight lunge toward the nearest enemy to the cursor when attacking
# with a blade (melee_1h). Search radius is centered on the cursor —
# not on the player — so the player aims by mouse direction and the
# lunge tracks whatever the cursor was over. Duration is set to half
# the effective attack interval so the slide ARRIVES at the target
# right when the swing's impact frame lands, syncing the geometry
# with the visual hit.
func _try_blade_lunge(weapon: Item, atk_spd: float) -> void:
	if weapon == null or weapon.weapon_base_id != &"melee_1h":
		return
	if weapon.fire_skill == null or weapon.fire_skill.cooldown <= 0.0:
		return
	var cursor_pos := cursor_world_position()
	if cursor_pos.distance_squared_to(global_position) < 0.01:
		return
	# Closest enemy within search radius of the cursor.
	var enemies: Array = SpatialGrid.query_radius(cursor_pos, BLADE_LUNGE_SEARCH_RADIUS, &"enemies")
	if enemies.is_empty():
		return
	var target: Node3D = null
	var best_dist: float = INF
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d: float = cursor_pos.distance_to((e as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			target = e as Node3D
	if target == null:
		return
	# Lunge vector — flat (XZ only), capped at MAX_DISTANCE, stops
	# short by STOP_GAP so we don't bury ourselves in the target's
	# collision capsule.
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist <= BLADE_LUNGE_STOP_GAP:
		return
	var lunge_distance: float = minf(dist - BLADE_LUNGE_STOP_GAP, BLADE_LUNGE_MAX_DISTANCE)
	if lunge_distance < BLADE_LUNGE_MIN_DISTANCE:
		return
	var direction: Vector3 = to_target.normalized()
	# Sync arrival with the swing's mid-anim impact frame. effective
	# cooldown × 0.5 mirrors the damage delay computed in the LMB
	# fire path.
	var effective_atk_spd: float = atk_spd if atk_spd > 0.0 else 1.0
	var duration: float = (weapon.fire_skill.cooldown / effective_atk_spd) * 0.5
	if duration <= 0.0:
		duration = 0.2
	# Quadratic ease-out integral = max_vel × duration / 3, so to cover
	# `lunge_distance` over `duration` we need this peak velocity.
	var max_vel: float = 3.0 * lunge_distance / duration
	_lunge_vel = direction * max_vel
	_lunge_remain = duration
	_lunge_duration = duration


func _face_direction(dir: Vector3) -> void:
	if visual == null:
		return
	# Flatten to the XZ plane before look_at. The character only ever
	# yaws — we never want X/Z tilt on the visual. Crucially, this
	# also guards against the look_at "aligned" failure mode: when the
	# player is mid-jump and the cursor world-pos is below them, the
	# raw aim vector points near-vertical. Passing that to look_at
	# with Vector3.UP as the up hint left the basis degenerate, which
	# rendered as the character lying on its side (seen rarely after
	# jumps + the per-tick face calls added for RMB aim-hold).
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	visual.look_at(visual.global_position + flat, Vector3.UP)

func _smooth_face(dir: Vector3, turn_rate: float, delta: float) -> void:
	# Rotate the visual yaw toward `dir` at most `turn_rate` rad/sec, taking
	# the shortest angular path. Only modifies the Y axis so animation tilt
	# (e.g. crouch lean) is preserved.
	if visual == null or dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	var current_yaw := visual.rotation.y
	var diff := wrapf(target_yaw - current_yaw, -PI, PI)
	var step := turn_rate * delta
	visual.rotation.y = current_yaw + clampf(diff, -step, step)

func _is_aim_input_held() -> bool:
	for action in SKILL_INPUTS:
		if not Input.is_action_pressed(action):
			continue
		# Holding RMB on a SHIELD_HOLD offhand isn't an aim — it's a
		# passive block. Movement-facing should win so the player
		# walks normally (just slower) instead of pinning to the
		# cursor. Same logic would apply to any future "hold to do
		# something non-aimed" RMB skill.
		if action == &"alt_fire":
			var rmb_skill := resolve_skill(1)
			if rmb_skill != null and (
				rmb_skill.active_kind == Skill.ActiveKind.SHIELD_HOLD
				or rmb_skill.active_kind == Skill.ActiveKind.AIM_HOLD
			):
				continue
		return true
	return false

# Picks the right firing pose for the current movement state so every
# ranged-fire trigger site agrees with the per-tick anim picker. Without
# this, an explicit _play_anim(ANIM_FIRE) at shot time would alternate
# against the picker's _play_anim(ANIM_FIRE_MOVE) and restart the loop
# every shot.
func _ranged_fire_anim() -> Array[StringName]:
	if _want_dir.length_squared() > 0.01:
		# Strafe-fire stays universal — Mixamo Strafing.fbx works for
		# both pistol and rifle (legs strafe, upper body holds the
		# weapon). A dedicated pistol-strafe-fire would be polish.
		return ANIM_FIRE_MOVE
	# Stationary fire — pistol-class plays the 1H snap-fire pose;
	# rifle stays on the wide-stance xbot/fire. Class lookup makes
	# SMG read as 1H instead of inheriting the rifle pose.
	return XBotAnimations.fire_anim_for_class(_equipped_weapon_class())


# Effective seconds between shots for the currently-equipped weapon.
# Used by the per-tick fire-pose picker to scale the looping fire
# animation so one anim cycle == one shot, eliminating the recoil
# wobble that happens when anim_length and fire_interval drift.
# Returns 1.0 as a safe fallback for melee or no-skill weapons (the
# fire branch only runs for bullet weapons anyway).
func _held_weapon_fire_interval() -> float:
	var w: Item = InventoryState.get_equipped(&"weapon")
	if w == null or w.fire_skill == null or w.fire_skill.cooldown <= 0.0:
		return 1.0
	var eff_atk: float = w.effective_attack_speed() * (1.0 + _gear_attack_speed_bonus)
	return w.fire_skill.cooldown / maxf(eff_atk, 0.1)


# True only for weapons whose attack is a melee SWING (full-body one-shot).
# Pistol/rifle classes — including the energy guns (laser pistol, plasma
# rifle, accelerator, taser) that aren't ammo-based and so report
# is_bullet_weapon() == false — are ranged and aim through the overlay.
func _attack_is_melee(item: Item) -> bool:
	if item == null:
		return false
	var cls := XBotAnimations.weapon_class_for_id(item.weapon_base_id)
	return cls == &"melee_1h" or cls == &"melee_2h" or cls == &"unarmed"


# ── Upper-body aim overlay ────────────────────────────────────────────────
# Layers the ranged-fire pose onto the upper body (spine→arms) while the legs
# keep whatever the locomotion picker chose, via UpperBodyAimModifier. Fixes
# the floated feet (legs stay on grounded clips), keeps the legs moving while
# firing, and ramps the influence so the aim-in is smooth instead of a snap.
func _drive_aim_overlay(delta: float) -> void:
	# Dead player has no upper-body overlay — the death anim owns the
	# whole rig. Belt-and-suspenders with the modifier.active=false set
	# in _die() so a late tick can't reactivate the overlay.
	if not _alive:
		return
	var modifier := _ensure_aim_modifier()
	if modifier == null:
		return
	# Overlay engages only while firing. The authored jog / strafe clips
	# already pose the upper body in a rifle-stance facing forward, so
	# applying the recoil overlay during locomotion would just make the
	# arms cycle noticeably while moving. The clip stack stays clean —
	# strafe drives both legs and upper body, recoil only kicks in
	# when LMB is actually held. Reload uses a separate play_swing
	# overlay (see start_reload).
	var aiming := false
	if _is_aim_input_held() and not is_reloading():
		var w: Item = InventoryState.get_equipped(&"weapon")
		aiming = w != null and not _attack_is_melee(w)
	if aiming:
		# Point the overlay at the class-appropriate fire clip so SMG/pistol
		# read 1H and rifle/shotgun read 2H. configure() early-outs when the
		# clip is unchanged, so this is cheap to call every tick.
		var skel := _find_player_skeleton()
		for key in XBotAnimations.fire_anim_for_class(_equipped_weapon_class()):
			if anim_player != null and anim_player.has_animation(key):
				modifier.configure(skel, anim_player, key)
				break
	modifier.tick(delta, aiming)


# Lazily build the aim modifier under the current skeleton. Re-creates it if a
# gender swap rebuilt the skeleton subtree (the old modifier goes with it).
func _ensure_aim_modifier() -> UpperBodyAimModifier:
	var skel := _find_player_skeleton()
	if skel == null or anim_player == null:
		return null
	if _aim_modifier != null and is_instance_valid(_aim_modifier) and _aim_modifier.get_parent() == skel:
		return _aim_modifier
	if _aim_modifier != null and is_instance_valid(_aim_modifier):
		_aim_modifier.queue_free()
	var m := UpperBodyAimModifier.new()
	m.name = &"UpperBodyAim"
	skel.add_child(m)
	_aim_modifier = m
	return m


# Kick the upper-body overlay through a fresh recoil cycle on a shot event.
func _pulse_fire_recoil() -> void:
	if _aim_modifier != null and is_instance_valid(_aim_modifier):
		_aim_modifier.pulse_recoil()


# Moving melee swing: play the swing on the UPPER body via the aim modifier so
# the legs keep locomoting (you can swing while moving). Returns true if it
# fired — player is moving and a swing clip resolved — in which case the caller
# skips the full-body _play_anim_stretched swing. Stationary swings stay
# full-body (planted legs read fine when you're standing still).
func _swing_overlay_if_moving(combo_step: int, duration: float) -> bool:
	if _want_dir.length_squared() <= 0.01:
		return false
	var modifier := _ensure_aim_modifier()
	if modifier == null:
		return false
	var skel := _find_player_skeleton()
	for key in XBotAnimations.combo_attack_anim_for_class(_equipped_weapon_class(), combo_step):
		if anim_player != null and anim_player.has_animation(key):
			modifier.play_swing(skel, anim_player, key, duration)
			return true
	return false


# Stationary firing pose with two modes:
#
#  * FAST weapons (fire_interval < clip.length): continuous LOOP at
#    a speed scaled by anim.length / fire_interval, clamped so it
#    doesn't spaz/freeze.
#
#  * SLOW weapons (fire_interval ≥ clip.length, e.g. sniper): HOLD
#    mode — anim plays once at 1.0× per shot, then freezes on the
#    last frame until the next shot. Looping a slow weapon at sub-
#    1.0× speed read as wobble because the loop boundary drifted
#    against the shot timing.
#
# No-op when MOVING — locomotion picker takes over (same flow that
# arc taser gets implicitly via is_bullet_weapon() = false).
#
# `restart` is true when called from a fire EVENT (per-shot) and
# false when called from the per-tick picker. In HOLD mode the fire
# event restarts from frame 0 (visible recoil per shot) while the
# tick picker leaves the anim alone (lets it play through and hold).
func _play_fire_pose(blend: float = 0.15, restart: bool = false) -> void:
	if anim_player == null:
		return
	if _want_dir.length_squared() > 0.01:
		return
	var candidates: Array[StringName] = _ranged_fire_anim()
	var chosen: StringName = &""
	for key in candidates:
		if anim_player.has_animation(key):
			chosen = key
			break
	if chosen == &"":
		return
	var clip: Animation = anim_player.get_animation(chosen)
	if clip == null or clip.length <= 0.0:
		_play_anim([chosen], 1.0, blend)
		return
	var fire_int: float = _held_weapon_fire_interval()
	if fire_int <= 0.0:
		_play_anim([chosen], 1.0, blend)
		return
	# Margin so weapons right at the boundary land in LOOP mode where
	# the clamp can still produce a reasonable visual.
	var is_slow_weapon: bool = fire_int > clip.length * 1.05
	var name_str: String = String(chosen)
	if is_slow_weapon:
		# HOLD MODE — play once, freeze at end frame.
		clip.loop_mode = Animation.LOOP_NONE
		# `assigned_animation` stays = the last anim we asked to play,
		# even after a non-looping anim finishes (where
		# `current_animation` resets to ""). That gap is exactly what
		# we need to distinguish "fire anim played out and is now
		# holding its end frame" (assigned = fire anim) from "RUN took
		# over while the player was moving" (assigned = run anim).
		var assigned: String = anim_player.assigned_animation
		var current: String = anim_player.current_animation
		if restart:
			# Per-shot event: visible recoil cycle from frame 0.
			_fire_pose_holding = false
			anim_player.speed_scale = 1.0
			anim_player.play(name_str, blend, 1.0, false)
			_anim_reverse = false
		elif _fire_pose_holding and assigned == name_str:
			# Anim played through and is sitting on its last frame.
			# assigned == fire anim → nothing else has been started
			# over it → leave the held pose alone.
			pass
		elif current == name_str and anim_player.is_playing():
			# Mid-cycle on the fire anim — leave it alone.
			pass
		else:
			# Either just transitioned back from movement (RUN had
			# taken over, assigned/current points to it), or first
			# frame after LMB press before any shot has fired. Start
			# the fire pose fresh.
			_fire_pose_holding = false
			anim_player.speed_scale = 1.0
			anim_player.play(name_str, blend, 1.0, false)
			_anim_reverse = false
	else:
		# LOOP MODE — continuous cycle scaled to fire_interval.
		clip.loop_mode = Animation.LOOP_LINEAR
		_fire_pose_holding = false
		var speed: float = clip.length / fire_int
		speed = clampf(speed, 0.6, 1.3)
		_play_anim([chosen], speed, blend)


# Returns the stance class of the currently-equipped main weapon
# (&"pistol" / &"rifle" / &"melee_1h" / &"melee_2h" / &"unarmed"). The
# locomotion picker (idle/walk/run) and the attack dispatch both
# branch on this so swapping weapons swaps the visible stance. Cheap
# enough to call every physics tick — single InventoryState lookup
# + dict get inside XBotAnimations.weapon_class_for_id.
# True when a non-looping animation is currently playing and hasn't yet
# reached its end. Used by the locomotion picker to avoid stomping on
# in-flight attack / cast / grenade / hit-reaction clips with the next
# tick's idle/run anim. Loop-mode is the discriminator — looping clips
# (idle, jog, fire) can always be overridden; one-shots (swings, casts,
# throws) need to play through. The -0.05s margin tolerates the picker
# firing inside the final frame of an anim that's about to finish.
# Plays a one-shot animation stretched to complete in exactly `duration`
# seconds. Picks the first available key from `candidates` (same fallback
# chain pattern as _play_anim), reads its native length, and computes a
# speed_scale that makes the full clip play within the duration window.
#
# Universal principle: the length of any action — attack, cast, throw,
# interact — should drive the length of its animation. Attack speed
# increases → animation speeds up to match (since duration shrinks);
# slower interactions → animation slows down. No more hardcoded 1.8× /
# 1.5× / 1.4× multipliers that clip the tail of every motion.
#
# Falls back to native-speed (1.0×) playback when:
#   - duration is non-positive (caller bug)
#   - no candidate animation resolves
#   - the animation's length is non-positive
#
# Speed floor of 0.3× — slow weighty swings on heavy melee (cooldown
# 1.5s × atk_spd 0.4 = 3.75s/swing vs clip 1.5s native) need to play
# at ~0.4× to stretch fully into the action window. The previous 0.5×
# floor clamped them halfway and broke sync between the visible strike
# frame and the damage timer (which uses the un-clamped duration).
# 0.3× still reads as legible motion rather than broken slow-mo.
# Picks the first clip in `candidates` that's loaded, sets the
# AnimationPlayer's speed_scale so the clip's authored ground travel
# matches the player's current horizontal velocity, and plays it.
# Centralises the "feet match real speed" logic so every locomotion
# branch (jog / strafe / walk_back / crouch_move) uses the same rule.
func _play_anim_with_synced_speed(candidates: Array[StringName], actual_speed: float) -> void:
	if anim_player == null:
		return
	var primary: StringName = &""
	for c in candidates:
		if anim_player.has_animation(c):
			primary = c
			break
	# Fallback to the first candidate even if it's not loaded — _play_anim
	# handles the no-op case.
	if primary == &"" and not candidates.is_empty():
		primary = candidates[0]
	var authored: float = _CLIP_AUTHORED_SPEED.get(primary, maxf(move_speed, 0.01))
	var rate: float = (actual_speed / maxf(authored, 0.01)) * LOCOMOTION_ANIM_SPEED_FACTOR
	# Pass the rate as _play_anim's `speed` arg — it sets speed_scale =
	# absf(speed) every call, so setting speed_scale here and then calling
	# _play_anim(... 1.0 ...) would just get clobbered back to 1.0.
	_play_anim(candidates, clampf(rate, RUN_ANIM_SPEED_MIN, RUN_ANIM_SPEED_MAX), 0.15)


func _play_anim_stretched(candidates: Array[StringName], duration: float, blend: float = 0.0) -> void:
	if anim_player == null:
		return
	if duration <= 0.0:
		_play_anim(candidates, 1.0, blend)
		return
	# Find the first candidate the player actually has loaded.
	var chosen: StringName = &""
	for key in candidates:
		if anim_player.has_animation(key):
			chosen = key
			break
	if chosen == &"":
		return
	var anim: Animation = anim_player.get_animation(chosen)
	if anim == null or anim.length <= 0.0:
		_play_anim(candidates, 1.0, blend)
		return
	var speed: float = anim.length / duration
	# Floor lets weighty 1.5s-cooldown melee swings stretch fully into
	# their action window. See header comment for the 0.3× rationale.
	speed = maxf(speed, 0.3)
	_play_anim([chosen], speed, blend)


func _is_oneshot_anim_playing() -> bool:
	if anim_player == null or not anim_player.is_playing():
		return false
	var current: StringName = anim_player.current_animation
	if current == &"":
		return false
	var anim: Animation = anim_player.get_animation(current)
	if anim == null:
		return false
	if anim.loop_mode != Animation.LOOP_NONE:
		return false
	return anim_player.current_animation_position < anim_player.current_animation_length - 0.05


func _equipped_weapon_class() -> StringName:
	var w: Item = InventoryState.get_equipped(&"weapon")
	if w == null:
		return &"unarmed"
	return XBotAnimations.weapon_class_for_id(w.weapon_base_id)


# Mounts the visible weapon model on the player's right-hand bone so it
# matches the equipped weapon. Called after every gender swap (which
# rebuilds the skeleton, dropping the old mount) and on weapon equip
# changes. Bare hands → model cleared.
#
# MP note: for remote avatars this reads the local InventoryState, the
# same known limitation _equipped_weapon_class() already has — remote
# peers' equipped weapons aren't replicated, so a remote avatar shows
# whatever the local player holds. Consistent with the existing stance-
# animation behaviour; full fix waits on weapon-loadout replication.
func _apply_weapon_model() -> void:
	var skel := _find_player_skeleton()
	if skel == null:
		return
	var w: Item = InventoryState.get_equipped(&"weapon")
	var base_id: StringName = w.weapon_base_id if w != null else &""
	WeaponAttachment.set_weapon(skel, base_id)
	# A freshly-mounted model defaults to render layer 1 (the floor-blood
	# decal cull layer) and would self-shadow under equipped lights. Walk
	# it onto the same layers as the player body — layer 2 + blood layer,
	# then OR in the player visual layer for shadow exclusion.
	var mount := WeaponAttachment.get_mount(skel)
	if mount != null:
		_walk_player_visual_layers(mount, 2 | PrototypeAttackIndicator.CHARACTER_BLOOD_LAYER)
		_apply_player_visual_layer_recursive(mount)


func _play_anim(candidates: Array[StringName], speed: float = 1.0, blend: float = 0.0) -> bool:
	if anim_player == null:
		return false
	var reverse := speed < 0.0
	for anim_name in candidates:
		if not anim_player.has_animation(anim_name):
			continue
		var name_str := String(anim_name)
		# Same-anim, same-direction → early-out, BUT sync speed_scale
		# first so a previously-elevated speed (e.g. melee swing at
		# 1.6×) doesn't persist into a subsequent idle loop request.
		# Without this, anim_player.play(name, blend, speed, reverse)
		# only takes effect when we DON'T early-out; same-anim calls
		# inherit the old speed and the loop visibly wobbles.
		#
		# Use speed_scale for ALL speed control; pass 1.0 as
		# play()'s custom_speed. Effective playback speed is
		# `speed_scale × custom_speed`, so setting both to `speed`
		# made stretched anims play at speed² — unarmed punches
		# completed in 0.43s instead of 0.65s and de-synced from the
		# impact_delay damage fire.
		anim_player.speed_scale = absf(speed)
		if anim_player.current_animation == name_str and anim_player.is_playing() and _anim_reverse == reverse:
			return true
		_anim_reverse = reverse
		anim_player.play(name_str, blend, 1.0, reverse)
		return true
	push_warning("[player] _play_anim: no match found for candidates %s (current: %s)" % [str(candidates), anim_player.current_animation])
	return false

func _ensure_loop(candidates: Array[StringName]) -> void:
	if anim_player == null:
		return
	for anim_name in candidates:
		if not anim_player.has_animation(anim_name):
			continue
		var anim := anim_player.get_animation(anim_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		return

func _build_crosshair() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 99
	add_child(canvas)
	_crosshair_root = Control.new()
	_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair_root.visible = false
	canvas.add_child(_crosshair_root)
	var a := CROSSHAIR_ARM
	var g := CROSSHAIR_GAP
	var h := CROSSHAIR_THICK * 0.5
	_crosshair_bars.append(_make_crosshair_bar(-(a + g), -h, -g, h))
	_crosshair_bars.append(_make_crosshair_bar(g, -h, a + g, h))
	_crosshair_bars.append(_make_crosshair_bar(-h, -(a + g), h, -g))
	_crosshair_bars.append(_make_crosshair_bar(-h, g, h, a + g))
	for bar in _crosshair_bars:
		_crosshair_root.add_child(bar)

func _make_crosshair_bar(ol: float, ot: float, or_: float, ob: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = Color.WHITE
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 0.5
	bar.anchor_bottom = 0.5
	bar.offset_left = ol
	bar.offset_top = ot
	bar.offset_right = or_
	bar.offset_bottom = ob
	return bar

func _update_fps_hover() -> void:
	var space := get_world_3d().direct_space_state
	var from := _fps_camera.global_position
	var forward := -_fps_camera.global_transform.basis.z
	var to := from + forward * sqrt(INTERACT_RANGE_SQ)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [get_rid()]
	var result := space.intersect_ray(params)
	var hit: Node3D = null
	if result.size() > 0:
		var col = result.get("collider")
		if col is Node3D and (col as Node3D).is_in_group(&"interactables"):
			hit = col as Node3D
	if hit == _fps_hovered:
		return
	if _fps_hovered != null and is_instance_valid(_fps_hovered):
		_fps_hovered.call(&"_on_mouse_exited")
	_fps_hovered = hit
	if _fps_hovered != null:
		_fps_hovered.call(&"_on_mouse_entered")
		_set_crosshair_color(UIThemeState.palette.accent)
	else:
		_set_crosshair_color(Color.WHITE)

func _clear_fps_hover() -> void:
	if _fps_hovered != null and is_instance_valid(_fps_hovered):
		_fps_hovered.call(&"_on_mouse_exited")
	_fps_hovered = null
	_set_crosshair_color(Color.WHITE)

func _set_crosshair_color(color: Color) -> void:
	for bar in _crosshair_bars:
		bar.color = color

func _try_interact_with(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.is_in_group(&"pickups") and not _is_airborne:
		_interacting = true
		_play_anim_stretched(ANIM_INTERACT, INTERACT_ANIM_DURATION, 0.1)
	if node.has_method(&"interact"):
		node.interact(self)

func _update_interact_cursor() -> void:
	if not _alive or _is_any_modal_open():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var hovered := _hovered_clickable()
	if hovered != null and _within_interact_range(hovered):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_anim_finished(anim_name: String) -> void:
	if anim_name == "Interact":
		_interacting = false
	# HOLD-mode fire pose just finished — mark held so the per-tick
	# picker doesn't restart it. The next fire event will clear this
	# flag and replay from frame 0.
	var name_sn: StringName = StringName(anim_name)
	if name_sn in ANIM_FIRE or name_sn in XBotAnimations.fire_anim_for_class(&"pistol"):
		_fire_pose_holding = true

func _would_hit_ceiling_if_standing() -> bool:
	if _stand_test_shape == null:
		return false
	var space := get_world_3d().direct_space_state
	# Threaded physics: direct_space_state is null when accessed outside the
	# physics step. Callers reach this from input contexts via _set_crouch,
	# so we have to fail-open here. The auto-uncrouch path in _physics_process
	# re-tests every tick, so a "stood up under a ceiling" state immediately
	# self-corrects on the next physics frame.
	if space == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_test_shape
	# Centre the slab probe between the top of the crouch capsule and
	# the top of the stand capsule, so it covers exactly the headroom
	# the player needs to clear to stand.
	var slab_center_y := CROUCH_HEIGHT + (STAND_HEIGHT - CROUCH_HEIGHT) * 0.5
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, slab_center_y, 0.0))
	query.exclude = [get_rid()]
	# Probe ONLY the world layer — without this the default mask (all
	# layers) catches charmed pets hugging the player at layer 16, plus
	# any hostile enemy at layer 2 standing close, and reports "ceiling
	# blocked" even in a wide-open room. Crouch then locks on until the
	# offending body wanders away. World-only matches the enemy crouch
	# probe and is the right semantics: only solid architecture should
	# prevent standing.
	query.collision_mask = 1
	return space.intersect_shape(query, 1).size() > 0

func is_crouching() -> bool:
	return _crouching


func _set_crouch(value: bool) -> void:
	if not value and _would_hit_ceiling_if_standing():
		return
	_crouching = value
	crouch_changed.emit(_crouching)
	if _collision != null and _collision.shape is CapsuleShape3D:
		var shape := _collision.shape as CapsuleShape3D
		shape.height = CROUCH_HEIGHT if value else STAND_HEIGHT
		_collision.position.y = shape.height * 0.5
	if _fps_mode and not _fps_transitioning:
		var target := FPS_CROUCH_OFFSET if value else FPS_HEAD_OFFSET
		create_tween().tween_property(_fps_camera, "position", target, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _flatten(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized()


# Layer bit for cover / destructible clutter. Matches
# enemy_afflictions.gd's _LAYER_PILLAR constant. Inlined as a local
# const so the player file doesn't have to import the enemy module.
const _LAYER_PILLAR_BIT: int = 128

func _apply_airborne_collision_mask() -> void:
	collision_mask &= ~_LAYER_PILLAR_BIT

func _restore_ground_collision_mask() -> void:
	collision_mask |= _LAYER_PILLAR_BIT


# ── Behavior mod helpers ────────────────────────────────────────────────────

# Shock Discharge AoE: knockback every enemy in radius, no damage. The
# point of the pulse is creating breathing room when you're crit-HP, not
# adding to your damage output. Visual: reuse the explosion VFX at the
# player's feet so the pulse reads instantly.
func _fire_shock_discharge_pulse(radius: float) -> void:
	var kb_strength := 14.0
	for enode: Node3D in SpatialGrid.query_radius(global_position, radius, &"enemies"):
		if not is_instance_valid(enode) or not enode.has_method(&"take_damage"):
			continue
		# Zero-damage knockback. PrototypeEnemy.take_damage with amount=0
		# still applies the knockback impulse via the same path the AoE
		# explosions use; the death/hit-flash branches skip because the
		# absorbed amount is 0.
		PrototypeEnemy.deal_damage(enode, 0, global_position, kb_strength, 1, false, &"")
	# VFX + sound — same explosion as RMB AoE so the pulse reads as a
	# clear "shockwave from me." Pass a small radius and a custom color
	# tint so it's visually distinct from a weapon explosion.
	PrototypeAttackIndicator.spawn_explosion(self, global_position + Vector3(0, 0.5, 0), radius, Color(0.4, 0.8, 1.0))


# Recoil Soles landing: fire a damage shockwave scaled by fall distance,
# armed by the airborne-peak tracking in _physics_process. Always sets
# the landed-slow timer (the trade fires even on short hops so the cost
# is felt, not just when the shockwave triggers).
const _RECOIL_FALL_THRESHOLD_M: float = 2.0  # min fall to fire shockwave
const _RECOIL_LANDED_SLOW_SEC: float = 1.0   # trade timer (matches tres comment)
func _recoil_soles_on_land() -> void:
	var radius := BehaviorModRegistry.get_active_param(&"feet", &"recoil_soles", &"shockwave_radius_m", 0.0)
	if radius <= 0.0:
		return
	_recoil_landed_slow_remain = _RECOIL_LANDED_SLOW_SEC
	var fall_dist := maxf(0.0, _airborne_peak_y - global_position.y)
	_airborne_peak_y = global_position.y
	if fall_dist < _RECOIL_FALL_THRESHOLD_M:
		return
	# damage_pct_of_fall_distance is "% of fall_distance becomes damage"
	# (e.g. 50% at 4m fall = 2 damage points × scaling factor). Multiply
	# by 10 so a 4m fall at 50% lands ~20 damage — readable as "noticeable
	# bonus on a real drop, trivial on a hop."
	var dmg_pct := BehaviorModRegistry.get_active_param(&"feet", &"recoil_soles", &"damage_pct_of_fall_distance", 0.0)
	var dmg := int(round(fall_dist * dmg_pct * 0.1))
	if dmg <= 0:
		return
	var kb_strength := 8.0 + fall_dist * 2.0
	for enode: Node3D in SpatialGrid.query_radius(global_position, radius, &"enemies"):
		if not is_instance_valid(enode) or not enode.has_method(&"take_damage"):
			continue
		PrototypeEnemy.deal_damage(enode, dmg, global_position, kb_strength, 1, false, &"")
	PrototypeAttackIndicator.spawn_explosion(self, global_position + Vector3(0, 0.2, 0), radius, Color(0.9, 0.6, 0.2))


# Outgoing damage multiplier from active behavior mods. Single aggregate
# read by PlayerCombat._deal_damage so adding new offensive-buff mods
# means appending to this function, not patching every call site.
# Composes multiplicatively across mods (only Pain Compiler currently
# contributes).
func behavior_mod_damage_mult() -> float:
	var m: float = 1.0
	if _pain_compiler_remain > 0.0 and _pain_compiler_mult > 1.0:
		m *= _pain_compiler_mult
	# Reflex Loader trade: -X% damage when resource is empty. Penalty only
	# applies at strictly zero resource; partial pool = full damage.
	if _resource_current <= 0.0:
		var penalty := BehaviorModRegistry.get_active_param(&"hands", &"reflex_loader", &"empty_damage_penalty_pct", 0.0)
		if penalty > 0.0:
			m *= maxf(0.1, 1.0 - penalty * 0.01)
	return m


# Camera-relative world-space input direction for the current frame.
# Returns Vector3.ZERO when no movement is held or chat is typing. Used
# in two places: the jump-check (line ~1249) needs the live direction
# because _want_dir is only assigned later in the same frame, and the
# main movement block reuses it as the canonical wish_dir.
func _input_wish_dir() -> Vector3:
	if GameplayChatState.typing:
		return Vector3.ZERO
	var input_vec := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
	)
	if input_vec.length_squared() <= 0.0:
		return Vector3.ZERO
	var ref_cam: Camera3D = _fps_camera if _fps_mode else _camera
	var cam_forward := _flatten(-ref_cam.global_transform.basis.z)
	if cam_forward.is_zero_approx():
		cam_forward = _flatten(ref_cam.global_transform.basis.y)
	var cam_right := _flatten(ref_cam.global_transform.basis.x)
	return (cam_right * input_vec.x - cam_forward * input_vec.y).normalized()
