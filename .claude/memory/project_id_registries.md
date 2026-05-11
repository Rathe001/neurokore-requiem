---
name: ID registries — single source of truth for slots / classes / stats
description: Adding a slot, class, or stat is a one-file edit; do not duplicate ID metadata in callers
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
Consolidated 2026-05-02. Each ID space has exactly one home. Adding a new ID is a one-file edit there; consuming systems read via the registry instead of hardcoding parallel dicts.

**Equipment slots + item main_types: `SlotRegistry` autoload** (`game/scripts/systems/slot_registry.gd`)
- `SlotRegistry.SLOTS: Array[StringName]` — canonical slot ID list (`&"head"`, `&"weapon"`, `&"backpack"`, etc.)
- `SlotRegistry.MAIN_TYPES: Array[String]` — random-roll pool (`"1H Weapon"`, `"Backpack"`, etc.)
- `SlotRegistry.MAIN_TYPE_TO_SLOT: Dictionary` — main_type → slot ID
- `SlotRegistry.MAIN_TYPE_GLYPH: Dictionary` — placeholder display glyph per type
- Helpers: `slot_for_type(main_type)`, `glyph_for_type(main_type)`
- ItemRoller, InventoryState, CharacterPanel, tooltips all read from here. Don't recreate these dicts elsewhere.

**Class IDs + presentational metadata: `AttributeState.CLASS_DEFINITIONS` and `ORIGIN_DEFINITIONS`** (`game/scripts/systems/attribute_state.gd`)
- `CLASS_DEFINITIONS[spec_id]` — `{stat, origin, glyph, label_key, backstory_key}` for the 6 specialised classes
- `ORIGIN_DEFINITIONS[origin_id]` — same shape minus `stat` for analog/cyborg
- Read via the static helpers on `SpecSelectOverlay`: `get_class_label`, `get_class_glyph`, `get_class_backstory`. (These also handle the `count` → `countess` gendered label exception in one place.)
- Don't add a new dict in a UI panel mapping `&"forged" → "F"`, etc. — extend the metadata fields on the existing definitions instead.

**Stat IDs: `AttributeState`** (`ROLLABLE_STATS`, `STAT_COLORS`, `STAT_I18N`, `STAT_SHORT`, `NEMESIS_STAT`, `ANALOG_STATS`, `CYBORG_STATS`)
- Already centralised. Adding a 7th stat is one edit (these consts) plus a perk-ladder entry in `PerkState.STAT_PERKS` (which is its own concern, slated for Resource extraction).
- `TalentsPanel.STAT_ROWS` is presentation order — leave it; it doesn't duplicate stat IDs, it just orders them.

**Rarity IDs** stay inside `ItemRoller` (`RARITY_WEIGHTS`, `RARITY_COLOR`, etc.) — only ItemRoller and `Item.rarity` reference them; not worth a registry until a third caller appears.

**Don't:**
- Re-create a `TYPE_TO_SLOT` or `MAIN_TYPES` dict in a new file. Use SlotRegistry.
- Add `SPEC_GLYPHS` / `SPEC_BACKSTORIES` / `SPEC_LABELS` parallel dicts to a new UI panel. Add the field to CLASS_DEFINITIONS / ORIGIN_DEFINITIONS instead.
- Reach into autoload constants from a top-level `const X = Autoload.OTHER_CONST`. Cross-autoload const references at parse time are fragile; do the lookup at runtime via a function call.
