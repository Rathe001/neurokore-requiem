---
name: Traction stat (boots stat domain)
description: Single 0–100 stat on boots that governs both movement immunities and ground-DoT damage reduction via shared staircase breakpoints. Single-source by design — only boots roll it.
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
**Domain:** Boots-only stat. No other slot rolls `traction_bonus`. Total = whatever's on the equipped boots.

**Breakpoints** at 25 / 50 / 75 / 100. Same staircase for both axes:

| Traction | Movement immunity unlocked | DoT damage reduction |
|----------|---------------------------|----------------------|
| < 25 | — | 0% |
| 25 | Slip-down chance | 25% |
| 50 | + Movement slow on hostile ground | 50% |
| 75 | + Knockdown on cracked floor / spike pads | 75% |
| 100 | + Full stride, immune to all ground effects | 100% |

**API** (`game/scripts/systems/traction.gd` — autoload `Traction`):
- `Traction.get_player_traction()` — reads only equipped boots
- `Traction.tier_for(value)` → 0–4
- `Traction.dot_reduction_pct(value)` → 0/25/50/75/100
- `Traction.reduce_ground_damage(amount, traction)` — apply to fire pools, acid, etc.
- `Traction.has_immunity(TIER_SLIP|TIER_SLOW|TIER_KNOCKDOWN|TIER_IMMUNE)` — boolean check

**Affixes** (boots-only, in `AffixTable`): Surefooted (+25, ilvl 1), Iron-Soled (+50, ilvl 25), Mag-Plated (+75, ilvl 50). Tuned to land on breakpoints exactly.

**Why single-source:** Stacking from gloves/chest/back would dilute the "feet matter" commitment and make the stat reach 100 too easily. Forcing it onto boots makes traction a slot decision — players who want it commit to it.

**How to apply:**
- New ground hazards (acid pools, electric floors, fire patches) should call `Traction.reduce_ground_damage(amount, traction)` for damage AND check `Traction.has_immunity(...)` for movement effects.
- Layered with per-element resistance: a fire pool reduces damage via BOTH `fire_resistance` (general fire damage) AND traction (ground-source modifier). They stack.
- Boots may eventually get a behavior-mod slot (Mag-Boots, Silent Step, etc.) per `docs/design/itemization.md`. Those are the *identity* layer; traction is the *stat domain*.
