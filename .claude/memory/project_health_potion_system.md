---
name: Health potion system
description: Consumable slot, both Stimpack/Battery roll in any game with origin gate at equip time, 3 charges, 30s recharge, Q key, %-based HoT, heal preview on HP bar
type: project
---

Health potion system. Key details:

- **Slot**: `&"consumable"` registered in SlotRegistry, top-right of character panel (row 0, col 2)
- **Item type**: `main_type = "Consumable"`, sub_type "Stimpack" or "Battery". Both types roll 50/50 in `_apply_consumable_base()` regardless of player origin — origin gating is enforced at equip time, not at roll time, so a Cyborg can pick up a Stimpack and trade/sell it freely.
- **Origin gate**: `Item.origin_restriction` field (`&"analog"` for Stimpack, `&"cyborg"` for Battery). Enforced in `InventoryState.set_equipped` and `ItemSlot.can_accept_item`. Tooltip shows red "Requires {Origin} origin" line when mismatched (dim "Origin: {Origin}" when matched). `Item.origin_matches_player()` is the canonical check; `Item.player_origin()` resolves spec→origin (or class_id when no spec yet).
- **Stats**: `heal_pct` (10-30%, % of max HP) and `heal_duration` (3-6s) in stat_modifiers. Was `heal_total` (flat), renamed — SaveManager migration in `_deserialize_stat_modifiers` floors migrated potions at 10% + 3s (NOT clamps raw value, which would silently buff old playtest potions).
- **Runtime**: `PlayerPotion` class (like PlayerGrenade pattern), 3 charges, 30s recharge per charge, 1s per-use cooldown, HoT ticks every 0.5s. HoT uses fractional-HP carry (`_hot_carry`) so 0.5/tick still delivers the full heal across ticks instead of round()-ing to zero.
- **Activation**: Q key → `resolve_skill(6)` → health_potion.tres (ActiveKind.POTION) → `_potion.activate(skill)`
- **HUD**: Q skill slot shows consumable's TextureRect icon + charge badge; hover shows item tooltip (not skill tooltip). HP bar has green heal preview overlay showing projected HP after HoT completes.
- **Icons**: `game/assets/ui/items/consumable/stimpack.png` and `battery.png`

**Why:** Diablo 3 potion model — simple, always available, charges prevent spam. Origin gate at equip time (not roll time) keeps the trading economy honest.
**How to apply:** New consumable features extend PlayerPotion; stat changes need SaveManager migration if renaming keys. New origin-gated items (class-specific weapons later?) reuse `Item.origin_restriction` + `origin_matches_player()` — don't reinvent the gate.
