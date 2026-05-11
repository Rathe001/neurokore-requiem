---
name: Attack speed weapon model
description: Combat stats (speed, damage, crit, accuracy) come from the rolled weapon Item; Skill keeps only action shape; +stat affixes layer on top
type: project
originSessionId: 3ccada6b-b909-4f94-a64f-38aa2efcfd7e
---
Combat stats live on the rolled weapon `Item`, not the `Skill` resource. The `WeaponBase` archetype defines per-stat ranges; `ItemRoller._apply_weapon_base` rolls each one at item generation and writes them onto the Item. Skill keeps only action shape (range, cone, targeting mode, base resource cost).

- **1H weapons** attack faster but hit lighter (lower damage per swing, lower crit).
- **2H weapons** attack slower but hit harder (higher damage per swing, higher crit, lock the offhand — see item-architecture.md).
- **+Attack Speed %** is a prefix/suffix affix that layers on top of the weapon base (`docs/design/item-architecture.md`).

**Why:** Builds should make tempo a meaningful axis — burst damage vs. sustain — and the weapon class is the primary signal of which tempo you've opted into. Stat affixes refine within that band.

**How to apply:**
- Skill `.tres` cooldown/wind-up are *base* values. At cast time `prototype_player._cast_skill` divides both by `weapon.attack_speed` (default 1.0 if no weapon backs the skill).
- Damage rolls in `_resolve_cone`/`_resolve_aoe` come from `randi_range(weapon.damage_min, weapon.damage_max)` when a weapon is in play; falls back to `skill.damage` for class skills.
- Crit chance prefers `weapon.crit_chance`; falls back to `PROTO_BASE_CRIT_CHANCE = 0.15` for class skills. `+crit_chance_pct` perks add on top.
- Accuracy gates per-strike via `_roll_hit`; weapon `accuracy < 1.0` rolls a miss check.
- The owning Item is captured via `_resolve_skill_source(skill)` (matches `weapon.fire_skill`/`weapon.alt_fire_skill`/offhand equivalents) and stored on `_attack_weapon` for the duration of one swing — protects against gear swap mid-attack.
- For new weapon bases, plan the (damage × attack_speed) DPS curve so 1H and 2H roughly converge at base, with the trade-offs being commitment window (2H locks longer per swing → more risk) and stat-budget overflow (1H leaves more affix room for utility).
