---
name: Forged Amalgamation — perk-gated extra weapon slots
description: dev tier perks grant extra 1H weapon slots that all fire on LMB; pattern for any future perk that adds equipment slots
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
Shipped 2026-05-02. Forged class signature: each Amalgamation tier grows another arm. Player ends up wielding 2-4 weapons at once; LMB fires every equipped weapon's `fire_skill` on its own per-slot cooldown with a small stagger.

**Perk effect:** `&"extra_weapon_slots"` (PerkEffect kind). Aggregates to 0..3. Documented in `perk_state.gd`'s effect-kind comment list. Adding more granters elsewhere just adds to the aggregate — clamped against `SlotRegistry.EXTRA_WEAPON_SLOTS.size()` so future perk overlap can't exceed the engine-supported arm count.

**Slot scaffolding:**
- `SlotRegistry.EXTRA_WEAPON_SLOTS` = `[&"weapon_2", &"weapon_3", &"weapon_4"]`. Helper `is_extra_weapon_slot(slot)` for the per-slot rules.
- `InventoryState.set_equipped` rejects 2H weapons in extras (each extra arm is 1H by design) AND rejects equipping into slots whose perk isn't yet unlocked.
- `InventoryState.get_extra_weapon_slot_count()` reads `PerkState.get_aggregate(&"extra_weapon_slots")` and clamps.
- `InventoryState.get_active_weapon_slots()` returns `[&"weapon", weapon_2, ...]` up to the unlocked count — combat fan-out reads from this.
- `InventoryState.reconcile_extra_weapon_slots()` evicts now-locked slots back to the inventory; wired to `PerkState.perks_changed` so a respec-out automatically returns gear.

**UI (CharacterPanel):**
- `EXTRA_WEAPON_SLOTS_LAYOUT` defines row 3 layout. ItemSlot nodes are built once in `_build_layout`; `_refresh_extra_weapon_slot_visibility` toggles them on the perks_changed signal.
- i18n keys `EQUIP_WEAPON_2/3/4` ("Arm 2/3/4") for empty-slot labels.

**Combat (PlayerCombat + PrototypePlayer):**
- New `_slot_cooldowns: Dictionary` on `PlayerCombat` keyed by slot StringName. `is_slot_on_cooldown(slot)`, `start_slot_cooldown(slot, skill, atk_spd)`. Two identical weapons in different slots have independent timers.
- New `_cast_lmb_combat()` on PrototypePlayer routes from `_handle_skill_input` when input index == 0 (LMB).
- For each active weapon slot whose cooldown is ready: starts the slot cooldown, spends resource (main only), schedules the hit-resolution at `i * stagger` via `create_timer.timeout.connect`.
- **Stagger is dynamic**, not a fixed constant: `stagger = main_weapon_effective_interval / ready_fires.size()`. A 1s-interval main with 3 extras fires at 0 / 0.25 / 0.5 / 0.75; a 0.5s main with 1 extra fires at 0 / 0.25. The main weapon's interval is read directly from `InventoryState.get_equipped(&"weapon")` so the cadence stays stable even when main is on cooldown and only extras are firing. Falls back to `LMB_MULTI_STAGGER_FALLBACK` (1.0s) when no main weapon is equipped.
- `_attacking` blocks input for `max_fire_delay` (the LAST staggered fire) so a re-click can't sneak in before the volley resolves.
- The MAIN weapon also writes the skill-keyed `_cooldowns` so the HUD slot's progress ring continues to display correctly (HUD binds to skills, not slots).
- **Resource cost is paid by the MAIN weapon only.** Extras fire free — gating each arm on resource_cost would let a 4-arm Forged drain the pool in one click. Extras also don't gate on `_resource_current`; only the main weapon checks availability before firing.
- **Per-arm spawn offset** for projectile / hitscan damage AND visuals. weapon_2 fires from the player's right (aim-relative), weapon_3 from the left, weapon_4 from above. Computed via `_arm_offset_for_slot(slot, aim_right)` in `_cast_lmb_combat`, threaded through `PlayerCombat.resolve_skill_hit` → `_spawn_projectile` / `_resolve_hitscan` and `PrototypeAttackIndicator.spawn_beam` so the visual and the cone query origin match. Cone / AOE skills don't get offset (radial blasts read better centered on the player).

**Pattern for future "equipment slot" perks** (utility belt expansions, augment slots, etc.):
1. Add the effect kind to `perk_state.gd`'s comment list AND author it in the relevant ladder.
2. Register slot IDs in `SlotRegistry` + a helper for the slot-class check.
3. Add `InventoryState` accessors for "how many unlocked" + "is slot active" + "reconcile on perk change".
4. Listen to `PerkState.perks_changed` from anything that needs to react.
5. Don't bypass `set_equipped` to write to gated slots — the rejection rules live there.

**Don't:**
- Read `_slot_cooldowns` directly from outside `PlayerCombat`. Use the `is_slot_on_cooldown` / `start_slot_cooldown` API.
- Add new weapon slot IDs without updating `EXTRA_WEAPON_SLOTS` order — the unlock-in-order rule depends on the array index matching the perk count.
- Stack multiple LMB casts manually; `_cast_lmb_combat` already handles parallel weapon firing.
