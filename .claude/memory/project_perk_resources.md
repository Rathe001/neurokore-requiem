---
name: Perk system — Resource-driven ladders
description: Perks live in .tres files at res://resources/perks/{stat_id}.tres; PerkState auto-loads them. Adding a new perk is editor work, not code
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
Refactored 2026-05-02. Tier perks moved out of `perk_state.gd`'s `STAT_PERKS` dict into editor-authored Resource subclasses.

**Schema (`game/scripts/perks/`):**
- `PerkEffect` — `kind: StringName`, `magnitude: float`. One contribution to a `PerkState` aggregate.
- `Perk` — `id: StringName`, `label: String`, `description: String`, `effects: Array[PerkEffect]`.
- `PerkLadder` — `perks: Array[Perk]`, exactly 3 entries (`perks[0]` = T1, `perks[1]` = T2, `perks[2]` = T3). Empty array = "no perks defined yet"; PerkState skips silently.

**Where ladders live:** `res://resources/perks/{stat_id}.tres`. PerkState scans `AttributeState.ROLLABLE_STATS` on `_ready` and tries to load each — naming convention is the contract. Currently shipped:
- `dev.tres` — Forged multistrike ladder, fully populated
- `ort.tres`, `ing.tres`, `amb.tres`, `opt.tres`, `cla.tres` — empty stubs with design-direction comments at the top of each `.tres`

**Adding a new perk:** open `resources/perks/{stat_id}.tres` in the Godot editor, set `perks[i]` to a new `Perk` subresource, fill in label / description / effects. No code edit required. Reload the game.

**Effect-kind discoverability:** the consuming code (player_combat.gd, prototype_projectile.gd) reads aggregates by string key (`PerkState.get_aggregate(&"crit_chance_pct")`). The list of currently-consumed kinds is documented at the top of `perk_state.gd`. Adding a NEW effect kind requires:
1. Add the kind to a perk's effects (in editor).
2. Add a consumer that reads `get_aggregate(kind)` somewhere meaningful.
Without step 2, the aggregate accumulates but does nothing — silent no-op, by design.

**Signal change:** `PerkState.perk_gained(perk)` now emits `Perk` (was `Dictionary`). Consumers use typed access (`perk.label`, not `perk.get("label", "")`). Same for `perk_lost`.

**Don't:**
- Re-introduce a `STAT_PERKS` dict in code.
- Bypass `PerkLadder.perks` ordering — index 0 is always T1, index 1 is T2, index 2 is T3. PerkState reads `perks[0..unlocked_tier-1]`.
- Author Perk dicts in GDScript and stuff them into a ladder at runtime — use the editor.
