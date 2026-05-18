---
name: Visual meter system
description: ALL item tooltips use visual meter bars — weapons, armor, boots, grenades, consumables, offhands; MODIFIER_BAR_DEFS for affix stats; Shift comparison shows union of bars; quality % on both panels; global Power bar with divider
type: project
---

ALL item tooltips use visual meter bars instead of raw numeric stats. Bars show RAW rolled values. Color-coded quality % appears top-right of tooltip name row AND equipped panel (red→yellow→green for 30–100%, green→blue for 100–150%). No label text, just the number.

**Bar fill color:** Fixed gradient (not theme-dependent): red(0%) → yellow(50%) → green(100%).

**Decay overlay:** Pulsing red overlay on each bar showing how much effective_multiplier has reduced the stat. Only appears on combat power stats (damage-based bars, defense, HP, resource, speed, combat sig stats). Feel stats (traction, blast radius, capacity, fire rate) don't decay.

**Bar range:** Most bars are archetype+rarity scoped (0% = worst possible roll for this type, 100% = best possible). Weapon **Power** is the exception — normalized against the global DPS range across every archetype × rarity so an SMG and a Sniper compare on the same scale. MeterBar.is_global flags the global bars; StatMeterBar.has_separator renders a thin divider beneath the last global bar to telegraph "everything below is type-scoped." Minimum 2px fill for rolled stats so floor-rolls are visually distinct from unrolled empty bars.

**Weapon bars:** Power (global DPS), Fire Rate, Capacity, [Reload if ammo], then signature stat bars (Ricochet, Bleed, Headshot, etc. per archetype), then affix modifier bars. AoE meter removed — users extrapolate multi-target from weapon behavior. Zero-variance bars hidden.

**Armor bars (Head/Chest/Gloves/Legs):** Defense, HP, Resource — always shown. Plus any rolled modifier bars.

**Boots bars:** Speed, Traction, HP, Resource — always shown. Plus modifier bars.

**Grenade bars:** Damage, Blast, Crit. Plus modifier bars.

**Consumable bars:** Heal %, Duration, Charges, Recharge Time.

**Offhand/Shield bars:** Shield Pool (base + bonus), DR (SHIELD_BUFF only), Duration (SHIELD_BUFF only), Cooldown (inverse — lower is better), plus sustain bars (life/barrier on kill). Shield text display gated behind `not has_meters`.

**Modifier bars (MODIFIER_BAR_DEFS):** 28+ stat types including elemental damage, crit, attack speed, resistances, shield bonuses, unarmed stats, etc. Any `stat_modifier` key present in MODIFIER_BAR_DEFS gets a meter bar. Hidden when value is 0, visible during Shift comparison. Divider line separates meter strip from non-metered mod text lines.

**Comparison merge:** When Shift held, both hovered and equipped items show the UNION of all bar IDs from both. Missing bars show as empty placeholders. `ItemMeterData.merge_for_comparison()` handles this.

**Rolling:** All rollable stats use centralized helpers (`_rarity_rollf/_rolli/_rollf_inv/_rolli_inv`) that apply power-curve bias AND rarity budget multiplier. Universal bonuses (HP, resource, sustain) scale with ilvl.

**Bar layout:** Half-size (4px bar, 8px row, font size 5). MAX_BARS = 20. Comparison (equipped) panel has its own meter strip.

**Architecture:** ItemMeterData.compute(item) is the single entry point. Delegates to WeaponMeterData for weapons (which appends signature stat bars), computes type-specific bars for non-weapons, then `_append_modifier_bars()` adds affix bars for all types.

**Why:** Arcade flavor, avoid number comparison paralysis, fits cyberpunk terminal aesthetic.

**Follow-up:** Character sheet meters planned (not yet designed). Bar visual design TBD — user is looking for new design examples; StatMeterBar rendering is isolated for easy swap.
