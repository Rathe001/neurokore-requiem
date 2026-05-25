---
name: project_enemy_physics_pause
description: Enemies pause _physics_process (and AnimationPlayer) when invisible AND in a pauseable state (IDLE / CHASING / RETURNING); wake via visibility_changed or external aggro/take_damage → _change_state
metadata:
  type: project
---

Mirror of the [[project_enemy_anim_pause]] pattern — `_physics_process`
follows the same pause policy as `AnimationPlayer.active`. The cost of
"active enemy AI" at horde density was the dominant phys load even after
distance throttling.

**Policy** (`_update_physics_process_active` + `_is_pauseable_state` in
`prototype_enemy.gd`):
- Pause iff `not visible AND _is_pauseable_state()` returns true
- `_is_pauseable_state()` returns true for `IDLE`, `CHASING`, `RETURNING`
- Active combat states (CASTING, ATTACKING, KNOCKBACK, STUNNED, JUMPING,
  GRABBED) are NOT pauseable — they own a timer or trajectory that must
  drain
- DEAD enemies are short-circuited at the top of the helper (the death
  path already paused them; a stray visibility flip during corpse
  cleanup mustn't revive them)

**Why CHASING/RETURNING are safe to pause despite being "active":**
LoS culling is room-gated. If the player aggros a horde and walks into
another room, the horde keeps state=CHASING but is now invisible behind
walls. Without this extension we measured 100-180ms phys spikes from
those invisible chasers running nav agent queries every frame. Pausing
them is invisible to the player — the next `visibility_changed` (entering
the same room again) resumes the chase at the snapshotted position, and
the existing LoS fade-in masks the resume snap.

**Wake-up sources** (both already wired):
- `visibility_changed` signal — LoS culler reveals the enemy → re-enable
- `_change_state(non-pauseable)` — external `aggro()` / `take_damage`
  flips state → re-enable via `_change_state → _update_physics_process_active`

**Wake-up phase randomization** (`_idle_skip_counter`):
- Re-randomized to `randi() % _IDLE_TICK_DIVISOR` on every wake transition,
  not just on `_init_enemy`. Without this, batches revealed together
  phase-lock to the same physics tick → 100-230ms wake-burst spikes.

**No-op guards on both helpers:**
Godot's `set_physics_process` and `anim_player.active` setters do
SceneTree bookkeeping on every write even when the value doesn't change.
The LoS culler fades hundreds of enemies in/out per level transition.
Both helpers `if current != desired` guard now — saved ~65ms off the
level-start proc spike alone.

Related: [[project_enemy_anim_pause]], [[project_enemy_state_machine]],
[[project_los_reveal_spikes]]
