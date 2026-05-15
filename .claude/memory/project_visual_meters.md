---
name: Visual meter system
description: ALL item tooltips use visual meter bars with stat bars + sig bars + decay overlay; color-coded quality % top-right
type: project
---

ALL item tooltips use visual meter bars instead of raw numeric stats. Bars show RAW rolled values. Color-coded quality % appears top-right of tooltip name row (red→yellow→green for 30–100%, green→blue for 100–150%). No label text, just the number.

**Bar fill color:** Fixed gradient (not theme-dependent): red(0%) → yellow(50%) → green(100%).

**Decay overlay:** Pulsing red overlay on each bar showing how much effective_multiplier has reduced the stat. Only appears on combat power stats (damage-based bars, defense, HP, resource, speed, combat sig stats). Feel stats (traction, blast radius, capacity, fire rate) don't decay.

**Bar range:** Most bars are archetype+rarity scoped (0% = worst possible roll for this type, 100% = best possible). Weapon **Power** is the exception — normalized against the global DPS range across every archetype × rarity so an SMG and a Sniper compare on the same scale. MeterBar.is_global flags the global bars; StatMeterBar.has_separator renders a thin divider beneath the last global bar to telegraph "everything below is type-scoped." Minimum 2px fill for rolled stats so floor-rolls are visually distinct from unrolled empty bars.

**Weapon bars:** Power (Single), Power (AoE), Fire Rate, Capacity, [Reload if ammo], then signature stat bars (Ricochet, Bleed, Headshot, etc. per archetype). Zero-variance bars hidden.

**Armor bars (Head/Chest/Gloves/Legs):** Defense, HP, Resource — always shown for consistent comparison. Unrolled stats show empty bars.

**Boots bars:** Speed, Traction, HP, Resource — always shown.

**Grenade bars:** Damage, Blast, Crit.

**Consumable bars:** Heal %.

**Backpack/Offhand:** No meters.

**Bar layout:** Half-size (4px bar, 8px row, font size 5). Comparison (equipped) panel has its own meter strip. Shift overlays exact numbers on both panels.

**Architecture:** ItemMeterData.compute(item) is the single entry point. Delegates to WeaponMeterData for weapons (which appends signature stat bars), computes type-specific bars for non-weapons.

**Why:** Arcade flavor, avoid number comparison paralysis, fits cyberpunk terminal aesthetic.

**Follow-up:** Character sheet meters planned (not yet designed). Bar visual design TBD — user is looking for new design examples; StatMeterBar rendering is isolated for easy swap.
