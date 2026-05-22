extends Node

# Traction — boots-only 0-100+ stat (no hard cap; endgame items can push
# past 100). Replaces the prior universal-breakpoint design with a
# per-surface mitigation curve so each ground type has its own
# difficulty profile.
#
# Mitigation formula: effect_factor(surface) = k / (k + traction)
#   where `k` is the surface's "half-mit" point — the traction value at
#   which the effect is exactly halved.
#   - traction = 0     → effect_factor = 1.0  (full effect)
#   - traction = k     → effect_factor = 0.5  (half mitigated)
#   - traction = 100   → effect_factor = k / (k+100)
#   - traction = ∞     → effect_factor → 0     (asymptotic, never zero)
#
# Surface identity = `k`:
#   - blood k=5   → entry-level. Walking through it should feel like a
#                   nuisance for new players and a non-issue past T20.
#   - water k=8   → procgen oil/water puddles. Slightly tougher than
#                   blood but still mostly mitigated by mid-game boots.
#   - oil k=30    → planned. Mid-tier surface.
#   - acid k=60   → planned. Late-game ground type with DoT.
#   - ice k=80    → planned. Hardest mundane surface — even endgame
#                   boots only get to ~30% effect remaining.
#
# Override flag: equip a boot with `negates_<surface>` modifier > 0
# (e.g. an "Ice Walker" perk setting `negates_ice` on the boot)
# forces effect_factor to 0 for that surface regardless of traction.
# Use this for binary "ignore one ground type" effects; everything
# else stays on the curve.
#
# Traction is single-source by design — only boots roll it. Stacking
# from other slots would dilute the "feet matter" commitment.

const BOOTS_SLOT: StringName = &"boots"

# Per-surface ground-effect profile. `half_mit_k` is the surface's
# resistance against traction. Effect-base fields are the values at
# T0 (no traction at all); code that needs the live mitigated value
# calls slow_factor_for_surface / friction_factor_for_surface /
# stumble_chance_for_surface, which apply effect_factor automatically.
const GROUND_EFFECT_PROFILES: Dictionary = {
	&"blood": {
		&"display_name": "Blood",
		&"half_mit_k": 5.0,
		&"slow_factor_t0": 0.85,     # -15% move at T0
		&"friction_factor_t0": 0.55, # heavy slip when releasing input at T0
		&"slip_chance_t0": 0.12,     # 12% stumble on entry at T0
		&"stumble_duration": 0.30,
	},
	&"water": {
		&"display_name": "Water",
		&"half_mit_k": 8.0,
		&"slow_factor_t0": 0.50,     # -50% move at T0 (procgen puddle baseline)
		&"friction_factor_t0": 1.0,  # water doesn't slip — just slows
		&"slip_chance_t0": 0.0,
		&"stumble_duration": 0.0,
	},
}

# Stumble chance below this floor clamps to zero so high-mitigation
# players don't roll a "feels random" stumble at sub-1% odds.
const STUMBLE_CHANCE_FLOOR: float = 0.005


## Total traction the player has from equipped boots. 0 when no boots
## are equipped or when boots have no `traction_bonus` modifier.
func get_player_traction() -> int:
	var boots: Item = InventoryState.get_equipped(BOOTS_SLOT)
	if boots == null:
		return 0
	return boots.get_modifier(&"traction_bonus")


## True if equipped boots carry a `negates_<surface>` override flag
## (any non-zero modifier value). For perks like "Ice Walker" that
## flat-ignore one ground type. Untouched surfaces stay on the curve.
func is_surface_negated(surface_id: StringName) -> bool:
	var boots: Item = InventoryState.get_equipped(BOOTS_SLOT)
	if boots == null:
		return false
	var key := StringName("negates_" + surface_id)
	return boots.get_modifier(key) > 0


## Hyperbolic mitigation curve. Returns 1.0 (full effect) when traction
## is 0; asymptotes toward 0 as traction grows but never reaches it
## (unless `is_surface_negated` short-circuits to 0). This is the core
## "how much of this effect still applies?" multiplier.
func effect_factor(surface_id: StringName, traction: int) -> float:
	if is_surface_negated(surface_id):
		return 0.0
	var profile: Dictionary = GROUND_EFFECT_PROFILES.get(surface_id, {})
	var k: float = float(profile.get(&"half_mit_k", 30.0))
	var t: float = float(maxi(traction, 0))
	return k / (k + t)


## Live move-speed multiplier on `surface_id` at the player's current
## traction. 1.0 = no slow; lower = slower.
func slow_factor_for_surface(surface_id: StringName) -> float:
	var profile: Dictionary = GROUND_EFFECT_PROFILES.get(surface_id, {})
	var t0: float = float(profile.get(&"slow_factor_t0", 1.0))
	var ef: float = effect_factor(surface_id, get_player_traction())
	return 1.0 - (1.0 - t0) * ef


## Live decel-friction multiplier on `surface_id`. < 1.0 = slip past
## stop. The accel step is intentionally untouched — only deceleration
## scales by this so "starting from rest" stays crisp.
func friction_factor_for_surface(surface_id: StringName) -> float:
	var profile: Dictionary = GROUND_EFFECT_PROFILES.get(surface_id, {})
	var t0: float = float(profile.get(&"friction_factor_t0", 1.0))
	var ef: float = effect_factor(surface_id, get_player_traction())
	return 1.0 - (1.0 - t0) * ef


## Live stumble probability on entry to `surface_id`. Clamps to zero
## below STUMBLE_CHANCE_FLOOR so a high-traction player doesn't get
## occasional 1% rolls that feel arbitrary.
func stumble_chance_for_surface(surface_id: StringName) -> float:
	var profile: Dictionary = GROUND_EFFECT_PROFILES.get(surface_id, {})
	var t0: float = float(profile.get(&"slip_chance_t0", 0.0))
	var ef: float = effect_factor(surface_id, get_player_traction())
	var chance := t0 * ef
	return 0.0 if chance < STUMBLE_CHANCE_FLOOR else chance


## Stumble duration when a stumble fires. The CHANCE scales with
## traction, the DURATION doesn't — getting tripped is getting tripped.
func stumble_duration_for_surface(surface_id: StringName) -> float:
	var profile: Dictionary = GROUND_EFFECT_PROFILES.get(surface_id, {})
	return float(profile.get(&"stumble_duration", 0.0))


## Display string for tooltips. Falls back to the surface id stringified
## so a typo / missing entry still produces something readable.
func display_name_for_surface(surface_id: StringName) -> String:
	var profile: Dictionary = GROUND_EFFECT_PROFILES.get(surface_id, {})
	return String(profile.get(&"display_name", String(surface_id)))
