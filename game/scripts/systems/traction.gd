extends Node

# Traction — boots stat domain. A single 0–100 number that governs how the
# player interacts with hostile ground (slip, slow, knockdown, ground-DoT).
# Both axes use the same staircased breakpoints so future ground-effect code
# only ever asks one question: "what tier am I at?"
#
# Movement immunity per tier (cumulative):
#   T0 (< 25)  — no immunities
#   T1 (25)    — ignore slip-down chance
#   T2 (50)    — + ignore movement slow on hostile ground
#   T3 (75)    — + ignore knockdown
#   T4 (100)   — + full stride (immune to all ground effects)
#
# DoT damage reduction (staircase, matches the same thresholds):
#   T0 → 0% reduction
#   T1 → 25% reduction
#   T2 → 50% reduction
#   T3 → 75% reduction
#   T4 → 100% reduction (immune)
#
# Traction is single-source by design — only boots roll it. Stacking from
# other slots would dilute the "feet matter" commitment, so this autoload
# reads only the equipped boots' traction_bonus modifier.

const BREAKPOINTS: Array[int] = [25, 50, 75, 100]
const BOOTS_SLOT: StringName = &"boots"

# Movement-immunity flags. Each is the index into BREAKPOINTS at which the
# immunity unlocks (0 = first breakpoint = traction 25). Constants instead
# of magic numbers so consumers read as "tier(t) >= TIER_SLIP" not
# "tier(t) >= 1".
const TIER_NONE: int = 0
const TIER_SLIP: int = 1       # ignore slip-down at traction >= 25
const TIER_SLOW: int = 2       # + ignore movement slow at traction >= 50
const TIER_KNOCKDOWN: int = 3  # + ignore knockdown at traction >= 75
const TIER_IMMUNE: int = 4     # + full stride / DoT immune at 100


## Total traction the player currently has from equipped boots. 0 when no
## boots are equipped or the boots have no traction_bonus modifier.
func get_player_traction() -> int:
	var boots: Item = InventoryState.get_equipped(BOOTS_SLOT)
	if boots == null:
		return 0
	return boots.get_modifier(&"traction_bonus")


## Tier 0–4 for a given traction value. Each step up corresponds to one
## breakpoint crossing.
func tier_for(traction: int) -> int:
	var t := 0
	for bp in BREAKPOINTS:
		if traction >= bp:
			t += 1
		else:
			break
	return t


## DoT reduction percentage applied to ground-source damage at this tier.
## Tier 0 = 0%, Tier 4 = 100%.
func dot_reduction_pct(traction: int) -> int:
	return tier_for(traction) * 25


## Apply traction's DoT reduction to an incoming ground-source damage value.
## Use this from any ground-effect tick (fire pool, acid floor, etc.) so the
## staircase rule is enforced in one place.
func reduce_ground_damage(amount: int, traction: int) -> int:
	if amount <= 0 or traction <= 0:
		return amount
	var pct := dot_reduction_pct(traction)
	if pct >= 100:
		return 0
	return int(round(float(amount) * (1.0 - float(pct) / 100.0)))


## True when the player has reached at least `tier` (one of TIER_SLIP /
## TIER_SLOW / TIER_KNOCKDOWN / TIER_IMMUNE). Sugar over tier_for + compare.
func has_immunity(tier: int) -> bool:
	return tier_for(get_player_traction()) >= tier


## Movement-speed multiplier under a slowing ground effect (e.g. liquid
## pools). Full immunity once traction reaches TIER_SLOW; otherwise the
## base 50% slow scales down step-by-step so a player part-way to the
## immunity threshold still feels their boots helping.
##   T0 (< 25)  → 0.50 (full -50% slow)
##   T1 (25)    → 0.75 (-25% slow — half mitigated by partial traction)
##   T2 (50+)   → 1.00 (immune)
func slow_factor_for(traction: int) -> float:
	var t := tier_for(traction)
	if t >= TIER_SLOW:
		return 1.0
	# T0: 0% reduction (factor = 0.5). T1: 50% reduction (factor = 0.75).
	var reduction := float(t) * 0.5
	const FULL_SLOW_FACTOR := 0.5
	return FULL_SLOW_FACTOR + (1.0 - FULL_SLOW_FACTOR) * reduction
