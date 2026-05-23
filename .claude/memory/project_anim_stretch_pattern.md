---
name: project_anim_stretch_pattern
description: "Action duration drives animation speed, not the other way around. `_play_anim_stretched(candidates, duration)` + impact-frame sync for melee."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

The principle the player asked for: **the length of an action drives the length of its animation**, not a hardcoded speed multiplier. Increasing attack speed shrinks the duration, the animation speeds up to match in lockstep.

**Helper.** `PrototypePlayer._play_anim_stretched(candidates, duration, blend=0.0)`:
1. Picks the first available animation key from the fallback chain.
2. Reads its native length.
3. Sets `speed_scale = anim.length / duration` so the full clip plays in exactly `duration` seconds.
4. Speed-floored at 0.5× to keep slow-motion playback from accidentally creeping in on long-cooldown weapons.

**Sync three-way (animation / SFX / damage) for melee.** Implemented in `_cast_lmb_combat` and `_fire_unarmed`:
- Animation: stretched to `effective_cooldown = skill.cooldown / atk_spd`.
- Damage: fires at `effective_cooldown * 0.5` (mid-anim, where the swing's visual impact frame lands). For ranged weapons the path still uses `skill.wind_up` directly so RPG-style audio pre-rolls keep working.
- SFX: deferred into the same `SceneTreeTimer.timeout` callback that fires the damage, so the hit sound lands on the impact frame instead of at LMB press. Ranged weapons keep SFX-at-press for pre-roll audio.

**Sites converted from hardcoded multipliers to stretched.** All one-shot one-shots:
- LMB melee swing / RMB melee skill: `cooldown / atk_spd`
- Shield cast / Second Wind / Recovery: `max(skill.wind_up, 0.5)`
- Grenade throw: `max(skill.wind_up, 0.5)`
- Interact: `INTERACT_ANIM_DURATION = 0.6`
- Unarmed: `cooldown / 1.0` (no weapon)

Looping animations (fire, idle, run, strafe, reload) NOT stretched — they don't have a "completion" to align to.

**Gate against locomotion picker.** `_is_oneshot_anim_playing()` reads `Animation.loop_mode` — `LOOP_NONE` means a one-shot is in flight and the ground-locomotion branch of the per-tick picker skips entirely. Without this gate every swing got clipped at ~22% as soon as `_lmb_busy` (the wind-up window) closed.

Related: [[project_looping_anim_hold]] (loop=true for sustained fire-hold poses); [[project_weapon_attachment]] (combo animations live there).
