---
name: project_melee_tuning_rationale
description: Why basic_attack cooldown is 1.5s, melee weapon attack_speed is 0.3-0.55, _play_anim_stretched speed floor is 0.3 — three knobs that have to move together to keep anim peak synced with damage timing on heavy weighty swings
metadata:
  type: project
---

A user feedback pass on 2026-05-25 walked melee from "feels like a fast
knife" to "weighty deliberate swings." Three knobs cooperate; flipping
one back to a more "normal" value will break the sync between the
visible strike frame and the damage event.

**The knobs (all in three different files):**

1. **`basic_attack.tres` cooldown = 1.5** (melee_1h fire_skill)
2. **`melee_2h_attack.tres` cooldown = 0.7** (was always 0.7)
3. **Weapon base attack_speed_range:**
   - `melee_1h.tres`: `(0.4, 0.55)`  (was 0.8-1.1, was 1.4-1.8)
   - `melee_2h.tres`: `(0.3, 0.4)`   (was 0.6-0.85)
4. **`_play_anim_stretched` speed floor = 0.3** (was 0.5)
5. **`_MELEE_IMPACT_RATIO` in prototype_player.gd:**
   - `melee_1h: 0.15`  (was 0.5 — matches the actual sword_attack
     clip's early-strike profile; commit 22b07a7 swapped slash→attack
     clips, which begin with the strong sweep at ~15% in)
   - `melee_2h: 0.3`   (was 0.4)

**Resulting swing durations:**
- melee_1h: `1.5s / [0.4..0.55] = 2.73..3.75s per swing`
  - Anim plays clip stretched to that duration → real-time speed
    `~clip_length / 3s ≈ 0.5` (hence the 0.3 floor needs to be
    below 0.5 to avoid clamping)
  - Damage fires at `duration × 0.15 ≈ 0.4-0.56s` — aligned with the
    visible strike frame
- melee_2h: `0.7s / [0.3..0.4] = 1.75..2.33s per swing`
  - Damage at `duration × 0.3 ≈ 0.53-0.7s`

**The trap:**
If anyone raises `attack_speed_range` "to make it feel snappier" without
also lowering the cooldown, the math still works (the anim speeds up
proportionally). But if they raise `attack_speed_range` AND restore
cooldown to ~0.7s independently, swings become too rapid AND too short
to read the strike — exactly what we just spent a session fixing.

If anyone restores `_MELEE_IMPACT_RATIO[melee_1h]` to 0.5, damage fires
at half-swing but the visible strike is at ~15% — desync returns.

If anyone restores `_play_anim_stretched` floor to 0.5, the 2H swing
(target speed ~0.4) clamps to 0.5× and the anim finishes BEFORE the
damage timer.

**For future damage rebalances, prefer:**
- Bump `damage_max_range` on the weapon base (keeps timing intact)
- Don't touch attack_speed_range unless you also adjust cooldown to
  keep the swing duration the same
- Don't touch impact_ratio unless the underlying anim clip was swapped

Related: [[project_attack_speed_model]], [[project_anim_stretch_pattern]],
[[project_weapon_quirks]]
