---
name: looping-anim-hold-pattern
description: Pattern for "hold to sustain pose" animations — loop the clip + per-tick anim picker override so the pose persists across attack-commit windows instead of restarting every tick.
type: project
---

**The problem.** A held input (LMB-fire on a ranged weapon) fires repeatedly. Each fire sets `_lmb_busy = true` for the wind-up window, then releases. Without intervention, the per-frame anim state machine inside `_physics_process` flips back to idle/run between shots → next shot calls `_play_anim(ANIM_FIRE)` again → restarts the clip from frame 0 → the pose visibly "spazzes" at the fire-rate frequency.

**The fix (3 parts working together).** All three are required — partial fixes look broken in interesting ways.

1. **Loop the source clip.** In the AnimationLibrary builder, set `loop_mode = Animation.LOOP_LINEAR`. For Mixamo-imported FBXs that's a flag at extract time:
   ```gdscript
   _extract(_library, &"fire", _FIRE_FBX, true, true)  # loop=true, strip_hip=true
   ```
   With loop=false, even the first frame of the clip plays once and then holds the last pose (which for a recoil cycle is the "released" pose). With loop=true, the clip cycles forever once started — calling `_play_anim` again with the same key is a no-op (Godot AnimationPlayer.play short-circuits).

2. **Override the per-tick anim picker** to keep the pose during the held input. In `prototype_player.gd._physics_process`, BEFORE the idle/run picker block, check the held-input + equipped-weapon condition:
   ```gdscript
   var firing_held := false
   if _is_aim_input_held():
       var held_weapon: Item = InventoryState.get_equipped(&"weapon")
       firing_held = held_weapon != null and held_weapon.is_bullet_weapon()
   if firing_held:
       _play_anim(_ranged_fire_anim(), 1.0, 0.15)
   elif moving:
       _play_anim(ANIM_RUN, ...)
   else:
       _play_anim(ANIM_IDLE, ...)
   ```
   Critical: this MUST run on the per-tick path that's gated by `_is_attack_committed() == false`. During `_lmb_busy` the per-tick picker doesn't run, but it doesn't NEED to — the explicit `_play_anim(ANIM_FIRE)` at fire time keeps the pose; once busy releases, the per-tick override takes over and keeps it playing.

3. **Single source of truth for "which fire variant".** The explicit per-shot call and the per-tick picker MUST agree on which animation key to use. If they disagree (e.g. picker plays `xbot/fire_move` while the shot calls `xbot/fire`), every shot still resets the loop because the key flips back-and-forth.
   ```gdscript
   func _ranged_fire_anim() -> Array[StringName]:
       if _want_dir.length_squared() > 0.01:
           return ANIM_FIRE_MOVE
       return ANIM_FIRE
   ```
   Both the per-shot site (LMB volley fire, generic skill cast) and the per-tick override call this helper. As long as they're calling the same function, they're consistent.

**Generalization.** Same pattern applies to any sustained pose triggered by a held input:
- Aim-down-sights (would need an ADS pose clip).
- Charge-up beam weapons (already partially done by Accelerator Resonance).
- Active shield "block" stance.
- Channel-cast skills.

**The user-visible test:** while LMB is held, the loop animates smoothly (no per-shot restart twitch). Released LMB → picker swaps to idle/run with 0.15s blend. Re-press LMB → smooth swap back to fire pose, NOT a frame-0 restart.

**Where the ranged-fire example lives:**
- `xbot_animations.gd:75` — `fire` clip extracted with loop=true.
- `combat_constants.gd:ANIM_FIRE` / `ANIM_FIRE_MOVE` — candidate arrays.
- `prototype_player.gd:_ranged_fire_anim()` — the helper that picks between them.
- Three call sites: per-tick picker (in `_physics_process`), LMB volley fire, generic skill cast — all three call `_ranged_fire_anim()`.
