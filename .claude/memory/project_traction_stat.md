---
name: Traction stat (boots stat domain)
description: Single boots-only stat with NO hard upper cap — endgame boots can reach 500+. Per-surface hyperbolic mitigation `k/(k+traction)` gives each ground type its own resistance profile. Roll range scales by item level + rarity curve, producing meaningful overlap between rarities (lucky common can beat unlucky uncommon).
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

**Roll range is OPEN-ENDED — no 0-100 cap.** Endgame characters can
reach traction 500+ from boots alone (uniques scale by item_level
× 1.5 × budget mult). `k` values are tuned for that range, not the
old 0-100 framing.

**Surface identity = `k` (the half-mit point):**
| Surface | k   | T=50  | T=200 | T=500 | T=1000 |
|---------|-----|-------|-------|-------|--------|
| Blood   |   5 | 91%   | 98%   | 99%   | 99.5%  |
| Water   |   8 | 86%   | 96%   | 98%   | 99%    |
| Oil     |  50 | 50%   | 80%   | 91%   | 95%    |
| Fire    | 120 | 29%   | 63%   | 81%   | 89%    |
| Acid    | 150 | 25%   | 57%   | 77%   | 87%    |
| Ice     | 200 | 20%   | 50%   | 71%   | 83%    |

Blood/water are entry-level — boots a player rolls in the first few
hours will trivialize them. Mid-tier (oil) requires investment by
mid-game to ignore. Late-tier (acid, ice) NEVER fully mitigate via
curve alone — at endgame T=500 you still slip 23-29% as much as a
no-traction character. The `negates_<surface>` override flag is the
only way to be 100% immune, making it a meaningful endgame perk.

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

**Item rolls** (`ItemRoller._roll_boots_stats`):
- Base traction roll range scales LINEARLY with `item_level`:
  `lo = ilvl × 0.3`, `hi = ilvl × 1.5`. Ilvl 1 commons roll ~1-6;
  ilvl 100 uniques roll ~45-225; ilvl 500 uniques roll ~225-750
  before affix bonuses.
- Rarity layer applies via `_curved_randf(lo, hi, rng, curve) × budget_mult`:
  - `RARITY_ROLL_CURVE` biases the pick within the range — common
    clusters near floor (curve=2.5), unique sits flat (curve=1.2).
  - `RARITY_BUDGET_MULT` multiplies the final value (1.0 → 1.5).
- This produces *meaningful overlap* between adjacent rarities:
  a lucky common occasionally outrolls an unlucky uncommon. Two
  rarities apart (common vs rare) very rarely overlap. The pattern
  matches the user's design intent: rarity matters but isn't a
  hard tier wall.
- Flat-bonus affixes (Surefooted +25 at min_ilvl 1, Iron-Soled +50
  at 25, Mag-Plated +75 at 50) stack on top of the base roll.
  Higher-tier affixes (e.g. +200 at min_ilvl 200) will land in a
  future affix-table pass to keep affix bonuses proportionally
  meaningful at endgame.

**Why single-source still:** Stacking from gloves/chest would dilute
the "feet matter" commitment. Traction is the slot decision; the
per-surface profile is the design knob; the curve makes every point
of traction feel like progress.

**Tooltip UX:** Concise — current debuff entry tooltip shows
"−X% move, Y% stumble" + "Traction N — M% mitigated" + skips lines
that wouldn't add information. Override-negated surfaces collapse to
a single "boots negate this surface entirely" line. See
`PrototypeHud._format_ground_effect_tooltip`.
