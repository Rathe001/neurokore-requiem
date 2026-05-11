---
name: Enemy state machine pattern
description: prototype_enemy uses an enum State (not boolean flags) — extend the enum, do not introduce new flags
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
The enemy AI in `game/scripts/prototype/prototype_enemy.gd` was refactored 2026-05-02 from a 6-boolean tangle (`_aggroed`, `_casting`, `_jumping`, `_returning_to_spawn`, `_alive`, plus `_knockback_remain` as a soft-flag) into an explicit `enum State` with a single `_state` variable.

**The states are mutually exclusive:** `IDLE`, `CHASING`, `CASTING`, `JUMPING`, `RETURNING`, `KNOCKBACK`, `DEAD`. Exactly one is active at any time. The crouching modifier (`_crouching: bool`) is intentionally orthogonal — it changes capsule height + speed multiplier but does not change *what* the enemy is doing.

**How to add a new behaviour:**
1. Extend the `State` enum.
2. Add a `match _state:` branch in `_physics_process` for the per-tick behaviour.
3. Add transitions via `_change_state(State.NEW)` from the appropriate places — never set `_state` directly outside `_change_state`.
4. If the state needs entry/exit setup (e.g. clearing velocity, killing a tween), put the hook at the call site for now. If hook count grows past two per state, lift them into a dispatch table inside `_change_state`.

**Why this matters:** booleans don't compose. `_jumping && _crouching` could silently happen with the old model; with the enum, it's a parse-level impossibility. Adding crowd-control overlays (stun, fear, charm, berserk) is now a one-state-per-effect addition rather than a flag-multiplication.

**Public API stays the same:** `aggro(depth)` and `take_damage(...)` are unchanged externally. Internal callers should use `_is_alive()` (returns `_state != State.DEAD`) rather than checking `_state` directly when they only care about the dead/alive distinction.

**Async work pattern:** `_cast_attack` shows the right way to handle awaitable behaviours that can be preempted — it sets `_state = CASTING`, awaits, then checks `if _state != State.CASTING: return` after resume. Anything that can interrupt (knockback, death, leash trip) just calls `_change_state` and the awaiter bails on resume. Apply this pattern to any new awaited behaviour (channelled abilities, charge attacks, ritual interactions).

**Don't:**
- Add a new boolean state flag on the enemy.
- Read `_state == State.X` from outside `prototype_enemy.gd` — expose a helper instead.
- Mutate `_state` outside `_change_state`.
