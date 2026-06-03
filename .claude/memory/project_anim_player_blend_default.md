---
name: anim-player-blend-default
description: "AnimationPlayer.play(name) with no custom_blend defaults to the per-pair blend-time table — which is never populated in this project, so unspecified blends = instant snap. Always pass explicit blend."
type: project
---

`anim_player.play(name)` accepts `custom_blend` as 2nd arg, default `-1.0`. The `-1` means "look up `set_blend_time(from, to, t)` for this transition." We never populate that table — so `-1` resolves to **0s blend = instant snap.**

**Symptom that bit me twice:**
- Enemy run → attack windup pose snapped instantly (no transition)
- Enemy HOLD-mode fire pose restart on shot didn't actually restart because `_play_anim`'s same-anim early-out skipped it AND we'd have wanted a tiny blend anyway

**Fix pattern:** always pass an explicit `blend` value. 0.15s is the project default (matches player). 0.05s for "restart this loop NOW" (visible recoil snap on per-shot fire). 0s for cases where you genuinely want a snap (single-frame hit-react flicker, etc).

**Enemy `_play_anim` signature** now defaults blend to 0.15:
```gdscript
func _play_anim(candidates: Array[StringName], speed: float = 1.0,
        blend: float = 0.15) -> bool:
    ...
    anim_player.play(name_str, blend)
```

**Direct `anim_player.play(name)` calls** outside `_play_anim` (e.g. inside `_play_fire_pose`'s HOLD/LOOP branches) must also pass a blend explicitly — they bypass the helper.

**`_play_anim`'s same-anim early-out vs restart:** the helper skips `play()` when `current_animation == name AND is_playing()`. For a true "restart this loop from frame 0" intent (e.g. on per-shot fire), call `anim_player.play(name, blend)` directly instead of going through `_play_anim` — the early-out would otherwise drop the restart silently.

Related: [[looping_anim_hold]], [[looping-anim-hold]].
