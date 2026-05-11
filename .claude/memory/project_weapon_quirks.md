---
name: Weapon signature quirks
description: Per-archetype passive ability that fires automatically while equipped; canonical catalog and play tips live in WeaponQuirkPanel.QUIRK_TIPS
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
Every weapon archetype (1H/2H melee, 1H/2H ranged, SMG, LMG, sniper, RPG, shotgun, taser, accelerator) has **one signature quirk** — a passive that fires automatically while the weapon is equipped. Players don't have to memorize them; the HUD widget under the minimap surfaces the active weapon's tip.

**Why:** Pre-quirks the weapons differed only by stat profile (range, damage, speed). Quirks give each archetype a "thing it does" so the pickup choice is meaningful even at equal DPS.

**Where to find them:**
- **Canonical reminder strings** — `scripts/ui/weapon_quirk_panel.gd` → `QUIRK_TIPS` dict (keyed by weapon_base_id). One short imperative line per archetype.
- **Design intent + the full table** — `docs/systems.md` → "Signature quirks" section under Combat.
- **Implementation** is split across:
  - `player_combat.gd` — per-shot or per-cast quirks (LMG heat, SMG penetration, laser charged shot, knife backstab, hammer wind-up, plasma pierce, accelerator resonance, taser static build). Uses `_archetype_quirk_damage_mult(weapon)` helper for the ones that just multiply spawn-time damage.
  - `prototype_player.gd` — player-side stack trackers (`_lmg_heat_stacks`, `_smg_shot_count`, `_laser_last_fire_t`, `_accel_resonance_stacks`, `_hammer_wind_up_ready`). Each has a `consume_*` helper that returns the multiplier and advances state.
  - `prototype_enemy.gd` — per-target counters (`_sniper_last_hit_t`, `_taser_hit_count`) via `consume_sniper_first_mark()` / `consume_taser_static_build()`.
  - `prototype_projectile.gd` — bullet-level quirks (`pierce_count`, `point_blank_bonus_distance`, `point_blank_bonus_mult`, `weapon_base_id`) set at spawn, consumed during hit resolution.

**How to apply:**
- When adding a new weapon archetype, add an entry to `QUIRK_TIPS` AND wire the actual passive somewhere in the four files above. The HUD widget auto-picks it up via the dict lookup.
- When tuning, search for the archetype's `weapon_base_id` (e.g. `&"sniper_2h"`) — that string is the cross-cutting key used by every quirk's branch.
- Quirks compose with multistrike, overclock, and crit. The known compounding risk is LMG heat (+50%) × overclock (+25%) × crit (1.5×) which can spike past intent; tune individual quirk caps if balance pass needs.
