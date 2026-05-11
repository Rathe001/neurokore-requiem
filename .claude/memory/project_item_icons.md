---
name: Item icon system
description: Items render via image icons (icon_path) with glyph fallback; resolver in ItemRoller drives slots, drag preview, world pickup, and held cursor
type: project
---

Items have an `icon_path: String` field on `Item` that points to a texture in `game/assets/ui/items/`. When set, the icon is used everywhere; when empty, the legacy unicode glyph is the fallback.

**Resolver (single source of truth):** `ItemRoller.resolve_icon_path(item)` derives the path from `weapon_base_id` / `sub_type` / `model_name`.
- Accelerator routes through `ACCELERATOR_ICON_BY_MODEL` (5 model variants, each its own icon).
- Weapons (`main_type == "1H Weapon" | "2H Weapon"`) look in `assets/ui/items/weapons/` keyed by slugged `sub_type`.
- Everything else (armor pieces, offhands, grenades, backpacks) looks in `assets/ui/items/armor/` keyed by slugged `sub_type`.
- Slug rule: lowercase, spaces and underscores → hyphens. "Cargo Pants" → `cargo-pants1.png`.

**Call sites:**
- `ItemRoller.roll()` / `roll_from_base()` call `_apply_icon_path` after sub_type/model_name are set.
- `SaveManager._deserialize_item` calls `ItemRoller.resolve_icon_path(item)` to backfill legacy saves that predate `icon_path`.
- `ItemSlot._refresh` renders icon when `icon_path != ""` else glyph label.
- `ItemSlot._get_drag_data` builds drag preview as TextureRect (32×32, `EXPAND_IGNORE_SIZE` so the texture doesn't inflate the rect) when icon available.
- `CharacterPanel._show_held_cursor` does the same for the click-to-move floating cursor (28×28).
- `ItemVisuals.build` builds a billboarded textured quad (0.7×0.7 world units, rarity tint) when icon available, else falls back to procedural primitives.

**Why:** Replaced the unicode-glyph rendering across the whole pickup→inventory→equip flow this session. Procedural ItemVisuals primitives are still the fallback for archetypes with no art.

**How to apply:** When new icons land, just drop the PNG into the right folder with the slugged name — the resolver picks them up automatically. To extend to a new item category, add a folder branch in `resolve_icon_path`.

**Important gotcha:** `TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL` makes the rect grow to the texture's aspect ratio, which inflates icons way past intended sizes. Use `EXPAND_IGNORE_SIZE` + `STRETCH_KEEP_ASPECT_CENTERED` instead.
