---
name: HUD top-right panel stack
description: WeaponQuirkPanel (Combat Effects) + MissionsPanel dock under the minimap, signal-coupled so missions auto-repositions as quirks resizes
type: project
---

Top-right HUD layout under the minimap is a vertical stack of two panels, each with the same styling language (slight black bg, gold title with thin divider, terse content).

**Panels:**
- `WeaponQuirkPanel` (title: "Combat Effects") — shows per-weapon signature quirk tips. Auto-hides when nothing equipped has a known quirk. Canonical tip table is `QUIRK_TIPS` constant. Adds itself to group `&"weapon_quirk_panel"`.
- `MissionsPanel` (title: "Missions") — placeholder content "No active missions" until the mission system is built. Finds the quirk panel via group lookup, listens to its `layout_changed` signal, and positions itself just below `bottom_edge_y + STACK_GAP`. Falls back to docking under the minimap directly when the quirk panel is hidden.

**Coupling mechanism:** quirk panel emits `layout_changed` after `_resize_to_content` (and when hiding). MissionsPanel's `_reposition_under_quirks` reads `quirk_panel.bottom_edge_y` and sets its own `offset_top`. So the stack stays glued together as either panel changes height.

**Why:** Set up this session to give the player a permanent reminder area for play hints. Mission UI lives here too even though the system isn't built — placeholder is intentional to claim the screen real estate.

**How to apply:**
- To add a third panel below missions, mirror the same pattern: anchor top-right, listen to the panel above's resize signal, set `offset_top` accordingly.
- To extend QUIRK_TIPS, edit the dictionary in `weapon_quirk_panel.gd` keyed by `weapon_base_id`.
- To wire real mission content, replace `MissionsPanel._gather_active_missions` with a read from your eventual mission state autoload; the rendering code already handles entries shaped `{header, tip}`.
