---
name: EnemyClass — Resource-driven enemy archetypes
description: Enemy combat profile (melee / ranged + optional support overlay) lives in res://resources/enemies/classes/{id}.tres; PrototypeEnemy reads it via accessor helpers
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
Started 2026-05-02. Following the same pattern used for perks, optics, and item modifiers — enemy behaviour is data, not code.

**Schema (`game/scripts/enemies/enemy_class.gd`):**
- `attack_mode: AttackMode` — `MELEE` (current behaviour) or `RANGED` (kite + projectile, planned).
- Attack tuning: `attack_range`, `attack_cooldown`, `attack_windup`, `attack_damage_mult`.
- Melee fields: `melee_cone_deg`, `melee_knockback`.
- Ranged fields: `projectile_scene`, `projectile_speed`, `projectile_max_range`, `ranged_kite_distance`.
- Support overlay (orthogonal to attack mode): `support_role` (`NONE` / `HEAL` / `DAMAGE_BUFF`), `support_radius`, `support_interval`, `support_magnitude`. A class can be melee+heal, ranged+buff, etc. — combinations are first-class.

**Where classes live:** `res://resources/enemies/classes/{id}.tres`. Each scene assigns one via the `enemy_class` `@export` on `PrototypeEnemy`.

**Currently shipped:**
- `basic_melee.tres` — mirrors the pre-EnemyClass DEFAULT_ATTACK_* constants exactly. Assigned to `prototype_enemy.tscn`.
- `basic_ranged.tres` — kite at 8m, 2s cooldown, 0.85× damage. Assigned to `prototype_ranged_enemy.tscn`.
- `melee_healer.tres` — basic_melee + 8% HP heal aura on a 3s tick.
- `ranged_buffer.tres` — basic_ranged + 25% damage buff aura on a 4s tick.
- All three behaviour layers (melee, ranged, support) are wired into `PrototypeEnemy`.

**Read pattern in PrototypeEnemy:**
```gdscript
var range_now := _attack_range()  # accessor returns enemy_class.attack_range or DEFAULT_*
```
Don't read `enemy_class.attack_range` directly — use the helper so the null-fallback stays consistent. The DEFAULT_* constants exist for unconfigured scenes (boss + future spawns) and can be deleted once every spawn has a class assigned.

**To add a new enemy archetype:**
1. New `.tres` at `resources/enemies/classes/{id}.tres`.
2. Either reuse `prototype_enemy.tscn` and assign the new class via export, OR create a new scene if the visual/model differs.
3. Spawner can set `enemy_class` before `reset()` runs to override per-instance (same pattern as `level` / `is_boss`).

**Support overlay mechanics:**
- HEAL: support tick calls `ally.heal(round(ally.max_health * support_magnitude))`. Restores HP up to `max_health`; no-op on dead allies.
- DAMAGE_BUFF: support tick calls `ally.apply_damage_buff(magnitude, support_interval * 1.1)`. Recipients hold `_damage_buff_mult` + `_damage_buff_remain`; multiple overlapping buffers take the MAX magnitude (no additive stacking) and the LONGER duration (so a brief weak refresh doesn't shorten a strong pulse).
- Outgoing damage in melee + ranged paths goes through `_outgoing_damage_mult()` which compounds class `attack_damage_mult` × `(1 + _damage_buff_mult)`.
- The buffer benefits from its own aura (self-included in the `SpatialGrid.query_radius` result).
- Support tick is staggered per enemy at spawn (random fraction of `support_interval`) so a roomful doesn't tick on the same physics frame.

**Outstanding polish (not blocking content):**
- Visual telegraph for active support aura (glowing secondary floor ring or pulsed particles). Currently the buff is invisible to the player — they'll feel it via heavier hits but won't see WHICH enemy is the buffer.
- Distinct projectile visual / mesh for enemy-fired bolts (currently reuses player projectile scene).

**Don't:**
- Add a new boolean export like `is_ranged: bool` on PrototypeEnemy. Extend EnemyClass instead.
- Read `enemy_class.X` directly — use `_attack_range()` / `_attack_cooldown()` / etc. accessors so fallbacks stay centralised.
- Hardcode per-archetype tuning in `prototype_enemy.gd` (e.g., "if archer, range = 12"). That data lives in the .tres.
