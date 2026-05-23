---
name: melee-impact-ratio
description: "Per-weapon-base impact frame ratio — fraction of stretched swing where damage / SFX fire"
metadata:
  type: project
---

Player melee damage + strike SFX fire at `melee_interval * _melee_impact_ratio(weapon_base_id)` from LMB-press, not at a hardcoded 50%. The dial lives in `_MELEE_IMPACT_RATIO` in `prototype_player.gd` next to `MELEE_BASE_IDS`.

**Why per-weapon:** Mixamo source clips don't all land their impact frame at 50% of the clip. `axe_swing` (sledgehammer) front-loads the windup — visible contact at ~40%. `sword_slash` (1H) is closer to 50%. Damage timed to a single hardcoded 50% felt slightly off on the sledge during LMB-hold combos.

**How to tune:** if a weapon's hits feel desynced from the visible swing,
- Damage fires BEFORE visual contact → ratio TOO LOW, raise it
- Damage fires AFTER visual contact → ratio TOO HIGH, lower it

Default for unknown weapon ids is 0.5. Add an entry when a new melee base lands.

**Current values:** `melee_1h: 0.5`, `melee_2h: 0.4`.

**Animation duration handling:** the swing anim is stretched via `_play_anim_stretched` to fit `melee_interval = skill.cooldown / atk_spd`. So the impact ratio is fraction-through-the-stretched-clip, which equals fraction-through-the-cooldown regardless of source clip length. Same ratio works at every attack_speed.

Related: [[anim-stretch-pattern]] for the stretch helper, [[crater-vfx]] for the LMB-hold context where this fix landed.
