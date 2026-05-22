extends Node

# Traction — boots-only stat with NO upper cap. Endgame boots can
# reach 500+ from the level-scaled base roll in ItemRoller (high-ilvl
# uniques range ~225-750 before flat-bonus affixes stack on top).
# `k` values for tougher ground types are tuned to that range — ice
# at k=200 still leaves a noticeable 29% effect at T=500, so even
# endgame players feel something underfoot.
#
# Mitigation formula: effect_factor(surface) = k / (k + traction)
#   - traction = 0     → effect_factor = 1.0  (full effect)
#   - traction = k     → effect_factor = 0.5  (half mitigated)
#   - traction = ∞     → effect_factor → 0     (asymptotic, never zero)
#
# Surface identity = `k` (the "half-mit" point):
#   - blood k=5   → entry-level. T=50 = 91% mit. Boots in the first
#                   couple hours trivialize blood underfoot.
#   - water k=8   → procgen oil/water puddles. Slightly tougher than
#                   blood but still mostly mitigated by mid-game.
#   - oil  k=50   → planned. T=200 = 80% mit. Mid-tier.
#   - fire k=120  → planned (DoT-focused, no slip). T=500 = 81% mit.
#   - acid k=150  → planned (DoT + mild slow). T=500 = 77% mit.
#   - ice  k=200  → planned (heaviest mundane). T=500 = 71% mit.
#     Even endgame players still feel ice — full immunity requires
#     a `negates_ice` override flag.
#
# Override flag: a boot with `negates_<surface>` modifier > 0
# (e.g. an "Ice Walker" perk setting `negates_ice`) returns
# effect_factor = 0 for that surface regardless of traction.
# Use for binary "ignore one ground type entirely" effects; the
# curve handles the gradient.
#
# Traction is single-source by design — only boots roll it.

# InventoryState slot key for the boots slot. The user-facing main_type
# is "Boots" but SlotRegistry maps it to the body-part key &"feet" (same
# convention as gloves → &"hands"). Using &"boots" here silently
# returned null and made traction stuck at 0 — boots could roll +500
# traction and the player wouldn't slip any less. Fixed 2026-05-22.
const BOOTS_SLOT: StringName = &"feet"

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
