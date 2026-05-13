---
name: Health potion system
description: Consumable slot, origin-gated potions (Stimpack/Battery), 3 charges, 30s recharge, Q key, %-based HoT, heal preview on HP bar
type: project
---

Health potion system shipped. Key details:

- **Slot**: `&"consumable"` registered in SlotRegistry, top-right of character panel (row 0, col 2)
- **Item type**: `main_type = "Consumable"`, sub_type "Stimpack" (Analog) or "Battery" (Cyborg), origin-gated in `_apply_consumable_base()`
- **Stats**: `heal_pct` (10-30%, % of max HP) and `heal_duration` (3-6s) in stat_modifiers. Was `heal_total` (flat), renamed — SaveManager has migration in `_deserialize_stat_modifiers`
- **Runtime**: `PlayerPotion` class (like PlayerGrenade pattern), 3 charges, 30s recharge per charge, 1s per-use cooldown, HoT ticks every 0.5s
- **Activation**: Q key → `resolve_skill(6)` → health_potion.tres (ActiveKind.POTION) → `_potion.activate(skill)`
- **HUD**: Q skill slot shows consumable's TextureRect icon + charge badge; hover shows item tooltip (not skill tooltip). HP bar has green heal preview overlay showing projected HP after HoT completes.
- **Icons**: `game/assets/ui/items/consumable/stimpack.png` and `battery.png`

**Why:** Diablo 3 potion model — simple, always available, charges prevent spam
**How to apply:** New consumable features extend PlayerPotion; stat changes need SaveManager migration if renaming keys
