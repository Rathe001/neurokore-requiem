---
name: Item ilvl effectiveness curve
description: Items carry an item_level and scale up/down based on player level via Item.effective_multiplier. Asymptotic decay below player level, linear boost above. Replaces stat-bloat treadmill — old items decay smoothly, above-cap drops become endgame chase.
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
Every `Item` has an `item_level: int` field stamped at generation. Combat power scales by a multiplier computed from `(player_level, item_level)`:

- **Below player level** (delta = player − ilvl > 0): `1 / (1 + delta * 0.05)`, clamped to a 0.30 floor. Smooth decay; never zero.
- **At player level** (delta = 0): exactly 1.00× (no scaling).
- **Above player level** (delta < 0): `1.0 + (-delta) * 0.01`, clamped to a 1.50 ceiling. Linear boost, +1% per level above. Above-cap drops from endgame content scale here.

**Scope: which stats scale.** Apply via `Item.get_effective_modifier(key)` for stat_modifier dict reads, or the typed accessors `effective_damage_min()`, `effective_damage_max()`, `effective_attack_speed()`, `effective_crit_chance()`, `effective_accuracy()` for direct fields. Combat power stats scale; storage/feel stats don't:

| Scales (use effective accessor) | Doesn't scale (use raw `get_modifier`) |
|---|---|
| damage, crit, accuracy, attack speed | inventory_bonus (storage capacity) |
| HP/resource bonuses, damage reduction | weapon_range (weapon character, not power) |
| All elemental damage / resistance | blast_radius (weapon character) |
| knockback_bonus, shield_pool_bonus | light_range / light_energy (lighting feel) |
| traction_bonus, hp_regen_bonus | Behavior mods (jetpack works as jetpack) |

**Tooltip:** Headline shows `Item Level: N (X% effective)` on every item. Stat lines render the effective value. Visibility for weapon-only stats (Speed/Crit/Accuracy/Damage rows) MUST gate on the **raw field** != default, not the effective value — otherwise non-weapon items leak `Speed: 0.95` rows whenever the multiplier ≠ 1.0.

**Starter gear:** Rolled at `item_level = 0`. Every world drop is ilvl ≥ 1, so starter gear is always strictly worse than any pickup. The 30% floor keeps it functional but unspectacular.

**Why:** Solves stat bloat (no need for squish patches — numerical ranges stay bounded), gear treadmill (favorite items stay weakly viable as you level), and endgame chase (above-cap drops become the prize). Dropped items can carry build identity even when they're "the wrong level" — a drop's mods/character matter, not just the numbers.

**How to apply:**
- Float variant `Item.get_effective_modifier_float(key)` returns unrounded values for tooltip display; gameplay uses the int rounded version.
- Equipped gear auto-rescales on level-up via `_recompute_stat_bonuses()` wired to `PlayerState.leveled_up`.
- Future "match item to player level" recipe is planned but not yet built — the system already supports it (just bump `item.item_level` to player level and the multiplier returns to 1.0).
