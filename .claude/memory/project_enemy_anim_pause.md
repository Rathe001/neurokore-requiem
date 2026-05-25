---
name: project_enemy_anim_pause
description: Enemy AnimationPlayer pauses when LoS-hidden AND state=IDLE; recovers ~40ms/frame at 200+ enemy counts
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`PrototypeEnemy._update_anim_player_active()` toggles
`anim_player.active` based on `visible AND state`. Called from two
hooks: `visibility_changed` signal (LoS culler flipped us) and
`_change_state` (we transitioned IDLE → something / something → IDLE).

Policy: pause iff `not visible AND state == State.IDLE`. Active states
(CHASING, CASTING, ATTACKING, JUMPING) keep the AnimationPlayer ticking
even when invisible because the AI state machine waits on
`animation_finished` for windup/fire triggers.

Why: AnimationPlayer ticks in `_process` regardless of parent visibility.
With 200+ enemies at level start, each tick costing ~200μs, total CPU
hit was ~40ms/frame — observed as sustained 65-100ms proc at idle in
2026-05-24 perf log. Pausing 90% (idle off-screen) recovers most of it.

Pool-safe: `visibility_changed` signal is connected in `_ready` and
persists across pool release/acquire (the node isn't freed, just
reparented). State transitions re-call the helper, so a state machine
fires AI animations correctly even when the enemy is off-screen.

Risk: animations that need to fire visual events (muzzle flashes,
particle emitters) while off-screen won't fire — but they're off-screen,
so the player can't see them anyway. Game-logic events (damage
application from a windup) flow through the AI state machine which
keeps anim active in non-IDLE states.
