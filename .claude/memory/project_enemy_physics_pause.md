---
name: project_enemy_physics_pause
description: Enemies pause _physics_process when invisible+IDLE; wake via visibility_changed or external aggro/take_damage → _change_state
metadata:
  type: project
---

Mirror of the [[project_enemy_anim_pause]] pattern — `_physics_process`
follows the same pause policy as `AnimationPlayer.active`. With 155 awake
enemies in a packed room, even the distance-throttled IDLE ticks (10Hz)
cost ~0.2ms × 155 = 30+ms of phys per frame. Pausing entirely on
invisible+IDLE drops that to zero for off-screen enemies.

**Policy** (`_update_physics_process_active` in `prototype_enemy.gd`):
- Pause iff `not visible AND _state == State.IDLE`
- Skip the update for DEAD enemies (death path already paused them
  explicitly; a stray visibility flip during corpse cleanup mustn't
  revive them)

**Wake-up sources** (both already wired):
- `visibility_changed` signal — LoS culler reveals the enemy → re-enable
- `_change_state(non-IDLE)` — external `aggro()` / `take_damage` flip
  the state → re-enable via `_change_state → _update_physics_process_active`

**Why it's safe even when the player is wall-adjacent to a paused enemy:**
LoS culling is room-gated. If the player enters the enemy's room, the
culler reveals → visibility_changed fires → physics resumes. The "wall-
between-us, same world distance" case stays paused intentionally —
aggro shouldn't fire through walls.

Related: [[project_enemy_anim_pause]], [[project_enemy_state_machine]],
[[project_los_reveal_spikes]]
