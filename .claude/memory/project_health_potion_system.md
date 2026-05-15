---
name: Recovery system (was Health Potion)
description: Consumable slot, both Stimpack/Battery roll in any game with origin gate at equip time, charges/recharge rolled, Q key, %-based HoT, heal preview on HP bar
type: project
---

Recovery system (renamed from "Health Potion" 2026-05-15). Key details:

- **Slot**: `&"consumable"` registered in SlotRegistry, top-right of character panel (row 0, col 2)
- **Item type**: `main_type = "Consumable"`, sub_type "Stimpack" or "Battery". Both types roll 50/50 in `_apply_consumable_base()` regardless of player origin — origin gating is enforced at equip time, not at roll time, so a Cyborg can pick up a Stimpack and trade/sell it freely.
- **Origin gate**: `Item.origin_restriction` field (`&"analog"` for Stimpack, `&"cyborg"` for Battery). Enforced in `InventoryState.set_equipped` and `ItemSlot.can_accept_item`. Tooltip shows red "Requires {Origin} origin" line when mismatched (dim "Origin: {Origin}" when matched). `Item.origin_matches_player()` is the canonical check; `Item.player_origin()` resolves spec→origin (or class_id when no spec yet).
- **Stats**: `heal_pct` (50-150%, curve + budget_mult) and `heal_duration` (0-5s) in stat_modifiers. `max_charges` (2-7) and `recharge_time` (20-45s inv) are Item fields. All rolled via rarity helpers.
- **Runtime**: `PlayerRecovery` class (`player_recovery.gd`), reads charges/recharge from equipped consumable via `sync_consumable()`. HoT ticks every 0.5s with fractional-HP carry.
- **Activation**: Q key → `resolve_skill(6)` → health_recovery.tres (ActiveKind.RECOVERY) → `_recovery.activate(skill)`
- **HUD**: Q skill slot shows consumable's TextureRect icon + charge badge; hover shows item tooltip (not skill tooltip). HP bar has green heal preview overlay showing projected HP after HoT completes.
- **Icons**: `game/assets/ui/items/consumable/stimpack.png` and `battery.png`

**Why:** Diablo 3 potion model — simple, always available, charges prevent spam. Origin gate at equip time (not roll time) keeps the trading economy honest.
**How to apply:** New consumable features extend PlayerRecovery; stat changes need SaveManager migration if renaming keys. New origin-gated items reuse `Item.origin_restriction` + `origin_matches_player()` — don't reinvent the gate.
