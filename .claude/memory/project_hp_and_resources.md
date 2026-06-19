---
name: HP and resource scaling design
description: HP scales from level + contribution-weighted stats; each T1+ class tree grants its own resource bar (max 3); origin classes use Soul/Interface only. Same-origin weighting is "kore".
type: project
---

**HP** is determined by level + total combined stats, weighted by each stat's contribution ratio to the player's class (primary 1x, kore ~0.25x, opposing reduced by resistance model). Stacking primary stat yields far more HP than stacking opposing.

**Class resources** — each class with at least T1 unlocked shows its own resource bar (max 3 bars, enforced by the 3-tree mathematical cap). Skills from each class consume their respective resource pool. Pool size = that stat's total after contribution ratio is applied.

**Origin classes** (Analog/Cyborg) — Soul and Interface are the ONLY contributing factors for HP and resources. Origin classes use a single resource bar only. Players cannot unlock more than 3 class trees at any time.

**3-tree cap** is enforced mathematically by thresholds (primary 12% + kore 25% + kore 25% + opposing 40% = 102% > 100%). Build patterns: 3-0-0 (deep), 2-1-0 (moderate hybrid), 1-1-1 (wide hybrid).

**Why:** Specialist builds get fewer, larger pools (sustained power in one domain). Hybrid builds get more, smaller pools (breadth at the cost of sustain). Opposing class resources are doubly punished — hard threshold to unlock AND tiny pool.

**How to apply:** Use contribution ratio (primary/kore/opposing) as a multiplier on stat totals for both HP and resource calculations. Resource bar UI should dynamically show/hide bars based on which class trees have T1+ unlocked.

**Terminology / cross-refs:** same-origin stat weighting is **"kore"**, not the older "team" — see [[kore-terminology]]. The stat trees this draws from are the talent-point system (project_attribute_system.md). Polymath + Enculted resource models remain TBD (per CLAUDE.md open design areas). This is **design intent**; code is authoritative for the current numbers.
