---
name: Item modifier dict — single source of truth
description: All item-driven numeric bonuses live in Item.stat_modifiers (keyed by StringName); read via Item.get_modifier(). No typed @export properties for individual bonuses
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
Refactored 2026-05-02. The pattern: every numeric bonus an item grants — class stats AND non-stat modifiers — lives in `Item.stat_modifiers: Dictionary` with **StringName** keys.

**Why:** the previous mix of typed `@export` properties (`Item.inventory_bonus`) plus `stat_modifiers` dict caused a latent bug where affixes wrote `stat_modifiers["inventory_bonus"]` while capacity reads `Item.inventory_bonus` — affix-rolled bonuses silently did nothing. Same trap was waiting for ammo / magazine / augment-slot bonuses.

**Read pattern:**
```gdscript
var bonus := item.get_modifier(&"inventory_bonus")  # returns 0 if absent
```
`Item.get_modifier(key: StringName, fallback: int = 0) -> int` is the canonical accessor. Don't reach into `stat_modifiers` directly when reading a single typed value — it costs nothing extra and centralises the contract.

**Write pattern:**
```gdscript
item.stat_modifiers[&"inventory_bonus"] = 8           # base value
# Affixes use += via _apply_affix in item_roller.gd, layering on top.
```
Always use **StringName** (`&"key"`) when writing from code. `Dictionary` treats String and StringName as distinct keys — a string-keyed write would never match a StringName-keyed read.

**Affix dict literals** in `affix_table.gd` use plain `"string"` keys for readability. `AffixTable._dict_to_affix` normalises them to StringName at cache-build time, so the on-disk format stays ergonomic. New affixes can use either key type and will work.

**Currently rendered in tooltip:** `inventory_bonus` (special-cased line), then a generic loop that filters to `AttributeState.ROLLABLE_STATS` only. Other modifier keys (damage_reduction, fire_damage_bonus, range_bonus, cryo_resistance, etc.) live in `stat_modifiers` but don't render yet — each new modifier type needs an explicit display rule when its consuming system ships. Don't loosen the `ROLLABLE_STATS` filter without adding labels for the leaked-through keys.

**Don't:**
- Add a new `@export` typed property for an individual numeric bonus. It will diverge from the dict and recreate the bug.
- Read `item.stat_modifiers[key]` directly when `get_modifier(key)` would do.
- Use string literal keys when writing from GDScript code (only acceptable in static dict literals that get normalised on load).
