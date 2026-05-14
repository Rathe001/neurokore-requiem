extends RefCounted
class_name HitStop
## Brief Engine.time_scale dip on crits and kills for single-hit weapons.
## Rapid-fire archetypes (SMG, LMG, taser, accelerator) are excluded so
## sustained fire doesn't stutter. Melee hitstop is handled separately by
## PrototypePlayer.trigger_melee_hitstop() (animation speed_scale pause).

# Durations (seconds of real time, not game time).
const CRIT_DURATION: float = 0.04
const KILL_DURATION: float = 0.06
const CRIT_KILL_DURATION: float = 0.08

# Time scale during the freeze. 0.0 = full stop; a tiny value keeps
# physics from desyncing and lets tweens crawl forward visibly.
const FREEZE_SCALE: float = 0.05

# Rapid-fire weapons skip crit hitstop — their per-shot cadence is too
# high and the repeated freezes feel like lag, not impact.
# Excluded archetypes: rapid-fire weapons whose per-shot cadence makes
# repeated freezes feel like lag, plus melee which has its own dedicated
# animation-pause hitstop in PrototypePlayer.trigger_melee_hitstop().
const _EXCLUDED: Dictionary = {
	&"smg_1h": true,
	&"lmg_2h": true,
	&"taser_2h": true,
	&"accelerator_2h": true,
	&"melee_1h": true,
	&"melee_2h": true,
}

static var _active: bool = false


## Call from damage paths when a player-fired hit crits.
## `weapon_base_id` gates out rapid-fire archetypes.
static func on_crit(weapon_base_id: StringName) -> void:
	if _EXCLUDED.has(weapon_base_id):
		return
	_apply(CRIT_DURATION)


## Call from enemy _die() — any kill gets a brief stop.
## `weapon_base_id` gates out rapid-fire archetypes.
static func on_kill(weapon_base_id: StringName) -> void:
	if _EXCLUDED.has(weapon_base_id):
		return
	_apply(KILL_DURATION)


## Crit + kill in the same hit — longest freeze.
static func on_crit_kill(weapon_base_id: StringName) -> void:
	if _EXCLUDED.has(weapon_base_id):
		return
	_apply(CRIT_KILL_DURATION)


static func _apply(duration: float) -> void:
	if _active:
		return
	_active = true
	Engine.time_scale = FREEZE_SCALE
	# SceneTreeTimer uses real time when process_always = true,
	# so the callback fires after `duration` wall-clock seconds
	# regardless of the slowed time_scale.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		Engine.time_scale = 1.0
		_active = false
		return
	tree.create_timer(duration, true, false, true).timeout.connect(_release)


static func _release() -> void:
	Engine.time_scale = 1.0
	_active = false
