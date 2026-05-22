---
name: Traction stat (boots stat domain)
description: Single boots-only stat (0-100+, no hard cap) that drives a hyperbolic per-surface mitigation curve. Each ground type has its own half-mitigation point — blood mitigates at k=5 (entry-level), ice at k=80 (endgame). Override flags negate one surface flat-rate.
type: project
---

**Replaces the prior breakpoint-tier model** (T1/T2/T3/T4 at 25/50/75/100 unlocking
the same effects on every surface). Old model wasted traction past the first
threshold and gave every ground type identical resistance. New model gives each
surface its own identity and makes every traction point a real upgrade.

**Mitigation formula** — `effect_factor(surface) = k / (k + traction)`:
- traction = 0   → 1.0 (full effect)
- traction = k   → 0.5 (half mitigated)
- traction = ∞   → 0.0 (asymptotic; never actually reaches zero)

**Surface identity = `k` (the half-mit point):**
| Surface | k  | Mitigated at T=25 | T=50 | T=100 | T=200 |
|---------|----|-------------------|------|-------|-------|
| Blood   |  5 | 83%               | 91%  | 95%   | 98%   |
| Water   |  8 | 76%               | 86%  | 93%   | 96%   |
| Oil     | 30 | 45%               | 62%  | 77%   | 87%   |
| Acid    | 60 | 29%               | 45%  | 62%   | 77%   |
| Ice     | 80 | 24%               | 38%  | 56%   | 71%   |

Blood is intentionally the entry-level surface (the user described it as
"prevalent — should make players think 'oh, floor mechanics are a thing'"
and easy to mitigate). Ice is the endgame mundane surface — even at
traction 200, you still slide ~30%.

**Override flag** — boots with a `negates_<surface>` modifier > 0
(e.g. an "Ice Walker" perk setting `boot.stat_modifiers[&"negates_ice"] = 1`)
flat-out skip the curve and return effect_factor = 0 for that surface
only. Use for binary "ignore one ground type entirely" effects; the
asymptotic curve covers everything else.

**API** (`Traction` autoload — `game/scripts/systems/traction.gd`):
- `get_player_traction() -> int` — boots-only readout
- `effect_factor(surface_id, traction) -> float` — the hyperbolic
  multiplier (0=fully mitigated, 1=full effect at T0)
- `is_surface_negated(surface_id) -> bool` — checks the override flag
- `slow_factor_for_surface(surface_id) -> float` — live move-speed
  multiplier on that surface (1.0 = no slow)
- `friction_factor_for_surface(surface_id) -> float` — live decel
  step multiplier (1.0 = full grip; < 1.0 = skid past stop)
- `stumble_chance_for_surface(surface_id) -> float` — live stumble
  probability on entry, clamped to 0 below `STUMBLE_CHANCE_FLOOR`
  (0.5%) so high-mit players don't get "feels random" stumbles
- `stumble_duration_for_surface(surface_id) -> float` — full
  duration when a stumble fires (chance scales with traction; the
  DURATION doesn't)
- `display_name_for_surface(surface_id) -> String`

**Per-surface profile** (`GROUND_EFFECT_PROFILES` const dict at top of
traction.gd): each surface stores `half_mit_k`, the T0 base values
(`slow_factor_t0`, `friction_factor_t0`, `slip_chance_t0`), the
`stumble_duration`, and a `display_name`. Adding a new ground type
= one entry + an enter/exit pair on the player (mirror blood / water).

**Affixes & items:** Boot affixes still roll `traction_bonus`. Old
tuning (Surefooted +25, Iron-Soled +50, Mag-Plated +75) needs revisit
under the new curve — there's no "breakpoint to hit," every point
matters. Existing values are fine for the migration but rebalance
will land alongside more ground types.

**Why single-source still:** Stacking from gloves/chest would dilute
the "feet matter" commitment. Traction is the slot decision; the
per-surface profile is the design knob; the curve makes every point
of traction feel like progress.

**Tooltip UX:** Concise — current debuff entry tooltip shows
"−X% move, Y% stumble" + "Traction N — M% mitigated" + skips lines
that wouldn't add information. Override-negated surfaces collapse to
a single "boots negate this surface entirely" line. See
`PrototypeHud._format_ground_effect_tooltip`.
