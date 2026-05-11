---
name: SaveManager schema must mirror Item schema
description: SaveManager._serialize_item / _deserialize_item have their own field list; adding a field to Item.gd without also adding it here silently strips that field on save/load
type: feedback
---

`SaveManager._serialize_item` and `_deserialize_item` (`game/scripts/systems/save_manager.gd`) have their own per-field serialization that does NOT use `Item.to_dict()` / `Item.from_dict()`. Adding a field to `Item.gd` does NOT automatically include it in save files.

**Why:** This session, items in saved characters were missing `icon_path`, `model_name`, `damage_type`, and the bullet ammo trio (`ammo_max` / `ammo_current` / `reload_time`) because those were added to `Item` over time without updating `SaveManager`. Every autosave was silently stripping them, so reloading a save reset items to glyph rendering, neutral damage type, and broken bullet weapons.

**How to apply:** When adding any field to `Item.gd`:
1. Add the field to both `_serialize_item` (write) and `_deserialize_item` (read) in `SaveManager`.
2. If the field affects gameplay or rendering for legacy saves, add a lazy migration / backfill in `_deserialize_item` (see how `icon_path` re-derives via `ItemRoller.resolve_icon_path` when empty).
3. Bonus: when reviewing PRs that touch `Item.gd`'s @export fields, always grep `save_manager.gd` to confirm the field landed in both serializer halves.

**Root cause we should eventually fix:** Two parallel serialization implementations is the bug. The MP path (`Item.to_dict` / `from_dict`) and the save path (`SaveManager._serialize_item`) should be unified. Until then, treat SaveManager as a checklist that mirrors Item.
