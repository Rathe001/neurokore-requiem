---
name: behavior-mods-system
description: Identity-layer gear modifiers — 24 mods designed across 6 armor slots, rollable params, implemented/preview flag, condition_id gating. Tooltip flips green/gray on active state. MVP shipped 2026-05-20.
type: project
---

**Status (2026-05-20): MVP shipped (tasks 62-66 in CHANGELOG `[Unreleased]`).** Foundation + 24 designed mods + ItemRoller integration + tooltip + 2 reference effects (Servo Stride, Ammo Reclamator). Tasks 67 (drop-weight tuning soak) and 68 (wire remaining ready-to-build mods) are long-tail.

**Design pillars** (from `docs/systems.md` "Behavior mods"):
- Each non-weapon/non-offhand slot rolls ONE mod (head, chest, hands, legs, feet, backpack).
- Mods change BEHAVIOR, not just numbers — identity layer.
- Every mod has a TRADEOFF (jetpack = inventory slot loss).
- Mods are ROLLABLE with their own params (jetpack 18 vs 26 res/sec).
- ~4 mods per slot.
- Mods exempt from ilvl effectiveness curve — a jetpack works as a jetpack regardless of player-level gap.

**File layout:**
- `res://resources/behavior_mods/{slot}/{id}.tres` — one file per mod, 24 total. Slot dirs: `head/`, `chest/`, `hands/`, `legs/`, `feet/`, `back/` (note: "back" dir but slot id is `&"backpack"` to match SlotRegistry).
- `game/scripts/items/behavior_mod.gd` — BehaviorMod Resource class. Fields: id, display_name, slot, description, param_ranges (Dict of key → [min, max]), is_implemented, condition_id (optional), class_restriction.
- `game/scripts/items/behavior_mod_registry.gd` — autoload (`BehaviorModRegistry`). Loads all 24 at startup from a hard-coded `_MOD_PATHS` array (DirAccess fails silently in exported builds per project_resource_loader_gotcha). API: `get_mod(id)`, `mods_for_slot(slot)`, `implemented_mods_for_slot(slot)`, `is_active(id)`, `get_equipped_mod(slot)`, `is_mod_equipped_and_active(slot, id)`, `get_active_param(slot, id, key, default)`.
- `game/scripts/items/item_roller.gd` `_roll_behavior_mod()` — rolls a mod onto armor pieces. Chance per rarity: Common 0%, Uncommon 50%, Rare/Unique 100%. Within the "got a mod" roll: 85% implemented, 15% preview (the "roadmap by loot" tease).

**Item integration:**
- `Item.behavior_mod_id: StringName` — id of the rolled mod, empty if none.
- `Item.mod_params: Dictionary` — rolled param values by key.
- SaveManager round-trips both fields.

**Tooltip rendering** (`prototype_tooltip.gd`):
- Three-line block: name (bold, green if active else gray) + `[preview]` tag if not implemented, then bullet-separated param values, then description.
- DO NOT use `[font_size=N]` in BBCode here — the stats label base is 7pt and `[font_size]` is ABSOLUTE not relative; bigger numbers make text LARGER. Bit me twice. See `project_godot4_runtime_gotchas` gotcha #5.
- Active check: `BehaviorModRegistry.is_active(item.behavior_mod_id)` — true when mod is implemented AND any condition_id passes.

**Adding a new mod (workflow):**
1. Create `res://resources/behavior_mods/{slot}/{id}.tres` with `is_implemented = false`.
2. Add the resource path to `BehaviorModRegistry._MOD_PATHS`.
3. Optionally add a condition_id and register a check in `_CONDITION_CHECKS` (e.g. `&"wielding_laser_pistol"`).
4. When wiring the effect: flip `is_implemented = true` on the .tres, add dispatch logic somewhere appropriate (player code reads via `get_active_param` / `is_mod_equipped_and_active`).

**Reference effects shipped:**
- Servo Stride (legs): sprint resource cost set to 0 when equipped + active. Effect lives at the sprint-drain site in `prototype_player.gd`.
- Ammo Reclamator (backpack): per-kill chance to refund a round to the current bullet weapon's magazine. Hook lives in `on_enemy_killed()`.

**Conditional mods (condition_id pattern) — not yet exercised:**
- Set `condition_id` on the .tres to a key like `&"wielding_laser_pistol"`.
- Register a check in `BehaviorModRegistry._CONDITION_CHECKS`: `&"wielding_laser_pistol": func() -> bool: return ...`.
- Tooltip flips green only when condition met; gray when implemented-but-condition-not-met (so the player sees "this mod is active for laser pistols, you're holding an SMG, so it's grey").

**Tuning constants** in `item_roller.gd`:
- `MOD_ROLL_CHANCE` (per-rarity Dictionary) — chance to roll a mod at all.
- `MOD_IMPLEMENTED_WEIGHT` (0.85) — implemented-vs-preview weighting.

Power-budget integration is **deferred** — mods cost zero budget today. The next polish pass should weight powerful mods (Ghost Field, Jetpack, Drone Bay) more heavily so they crowd out affixes/stats when they roll.
