---
name: Weapon DPS balance model
description: 3-tier DPS normalization by multi-target capability; damage scales by RARITY_BUDGET_MULT
type: project
---

Weapon DPS normalized across archetypes with rarity scaling. Shipped 2026-05-13.

**3-tier system** (common midpoint DPS):
- **Single-target (~26 DPS)**: Sniper, Laser Pistol, LMG — premium for no AoE
- **Limited multi (~23 DPS)**: Assault Rifle (penetration), SMG (ricochet)
- **Multi-target (~20 DPS)**: Melee 1H/2H, RPG, Shotgun, Taser, Accelerator

**Rarity scaling**: `_roll_damage()` now applies `RARITY_BUDGET_MULT` (common 1.0, magic 1.15, rare 1.3, unique 1.5) — same as other stat rolls. Combined with the power curve, higher rarity meaningfully increases DPS ceiling with overlap at edges.

**Key DPS formula**: `avg_dmg * attack_speed / skill_cooldown` for normal weapons; `avg_dmg / tick_interval` for channels (taser/accelerator ignore attack_speed for tick rate).

**Why:** Accelerator was at 68.8 DPS (3.4x baseline), shotgun 32.7. User wanted rarity to matter for DPS and all weapons to be comparable, with single-target weapons getting a premium.
**How to apply:** When adding new weapons, compute effective DPS against the tier targets. Channel weapons need damage balanced against tick_interval, not attack_speed.
