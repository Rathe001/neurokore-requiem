---
name: procgen-switch-softlock
description: Procgen levels can softlock — boss room with 3+ doors over-allocates switch puzzles when the cell pool is too small. Workaround is the debug Force Unlock button; real fix is capping total switches across all boss-door puzzles.
type: project
---

**Symptom.** On a procgen level the player sees mission lines like:
- East gate switches (0/3)
- South gate switches (0/3)
- East gate switches (3/7)  ← physically impossible

The "(3/7)" puzzle has 7 required activations but only 3 switches were physically spawned. The boss-door it locks stays locked forever — the player can't proceed.

**Root cause.** In `dungeon_generator.gd:_emit_switch_puzzle`:
```gdscript
for door_conn in boss_conns:
    var n: int = mini(switch_count, pool.size() - pool_idx)
    ...  # places n switches, registers a puzzle that REQUIRES n
```
Each boss-room connection becomes its own puzzle. `switch_count` defaults to 3. If the boss room has 4 doors and the cell pool has 10 cells minus start/boss/exit = 7 usable cells, the first 2 puzzles get 3 switches each (6 used), the third gets 1 switch, the fourth gets 0. But `MissionState.register_puzzle(door, n)` records the FULL puzzle's required count from `apply()`, while the physical switches are fewer.

There's also a separate mode where `required_count` is set above 0 on the SwitchDoorPuzzle, in which case `n = required_count` regardless of how many switches actually rolled in. Either flow can produce the softlock.

**Workaround (runtime).** Debug panel has a **"Force Unlock Doors"** button (added 2026-05-20). Press F3 to open the debug panel, click the button → walks every PrototypeDoor in the `resettable` group and drains its `unlock()` counter until each is fully open. Dev/QA builds only (gated by `BuildInfo.dev_tools_enabled()`).

**Real fix (deferred).** Two angles to try in `dungeon_generator._emit_switch_puzzle`:
1. **Pre-compute the global switch budget** = `pool.size() - 3` for start/boss/exit. Divide evenly across `boss_conns.size()` puzzles. If any puzzle would get 0, skip that door (leave it as a non-puzzle direct connection).
2. **Skip puzzle creation entirely when `n <= 0`**. Currently the loop `push_warning`s and continues — the door stays locked with `unlocks_required` from whoever last touched it. Either make the door non-locked OR delete the puzzle entirely.

Option 2 is the minimum-correctness fix. Option 1 is the better-design fix (each boss-door puzzle gets roughly equal switch count instead of front-loading).

**Adjacent bug.** Even when switches DO place correctly, the MissionState's per-puzzle label is "East gate switches" derived from the door's geometric direction. Two doors leading East both get the same label, which is why two "East gate" lines can coexist with different (X/Y) counts. A cleaner label would include the door's room id or puzzle index — minor polish, not a softlock cause.
