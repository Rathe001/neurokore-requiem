---
name: Talent point system (replaced moral-stat allocation)
description: Build identity comes from talent-point allocation in stat-keyed trees, not from gear stat allocation. 5 tiers per ladder, 8 nodes per tier, point-threshold gating with class lockouts. Replaces the older 8-attribute moral-stat allocation model entirely.
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
**Status (current as of 2026-05-06):** The earlier "8 moral attributes derived from gear stat allocation" model is **gone**. Build identity now comes from a talent-point system. Gear contributes only to combat power numbers; it does not gate perks.

**Six stat-keyed talent trees, paired by origin (kore):**

| Stat ID | Class | Origin |
|---|---|---|
| `ort` | Count/Countess | Analog |
| `ing` | Survivalist | Analog |
| `amb` | Enculted | Analog |
| `dev` | Forged | Cyborg |
| `opt` | Automaton | Cyborg |
| `cla` | Polymath | Cyborg |

Soul/Interface from the old model are gone as rollable stats; if they reappear they'd be display-only averages.

**Tree shape:**
- 5 tiers per ladder (T1–T5), 8 nodes per tier. Talent panel renders this 4×2 grid per tier.
- File naming convention: `res://resources/talents/{stat_id}.tres` and `res://resources/perks/{stat_id}.tres`. Note: file basename is **stat_id** (`amb.tres`), NOT class_id (`enculted.tres`). The `TalentState` and `PerkState` loaders both walk `CLASS_DEFINITIONS` keys and resolve via `CLASS_TO_STAT` to find the right file.

**Point gating** (`PlayerState.TIER_POINT_THRESHOLDS = [0, 4, 8, 12, 16]`):
- T1 always open, no points required.
- T2 unlocks once 4 points are spent in that track. T3 at 8. T4 at 12. T5 at 16.
- Stacks on top of class lockouts (origin/spec gates).

**Class lockouts** (encoded in `PlayerState.get_unlocked_tier`):
- Specialized class on **own** stat tree: up to T5.
- Specialized class on **same-kore** stats: requires T1+ investment in own tree first.
- Specialized class on **opposing-kore** stats: locked entirely (return 0).
- Origin class (no spec): own-kore capped at **T3** (`ORIGIN_CLASS_TIER_CAP`); opposing-kore similarly capped via the point thresholds.

**Talent point grant cadence:** 1 point every 3 levels (`LEVELS_PER_TALENT_POINT`). Granted in `_do_level_up()` when `level % 3 == 0`. At level cap (100) → ~33 points.

**Perk vs. talent split:**
- **Perks** = big class-identity gains (Drone Swarm I/II/III, Doomsayer I/II/III). One per ladder tier. `PerkState._recompute()` reads `talent_allocations` directly: any allocation at tier N unlocks `ladder.perks[N]`.
- **Talents** = granular nodes (8 per tier) that contribute to effect aggregates (`doomsayer_dot_per_tick`, `ignore_point_blank_penalty`, etc.) or grant active skills via `granted_skill` + `granted_slot`. `TalentState._recompute()` reads `is_node_active`.
- Both feed `Effects.get_aggregate(kind)` (the unified reader); consumers should use that, not `PerkState`/`TalentState` directly.

**Why:** The old model made every gear swap re-roll your build because gear contributed stat values that gated tier unlocks. Decoupling lets gear stay "loot-driven power scaling" while talents stay "deliberate identity choice."

**How to apply:**
- Talent panel UI is in `scripts/ui/talents_panel.gd`. STAT_ROWS dictionary maps stat_id → class display.
- `Item.stat_modifiers` no longer feeds `get_stat_pct()` — that whole path is dead.
- When wiring a new talent: drop the `.tres` in the right place, add an `Effects.get_aggregate(kind)` consumer, no further code in TalentState/PerkState needed.
- When wiring a new perk tier: add to the `perks` array in the ladder `.tres`. PerkState._recompute reads `ladder.perks.size()` directly.
