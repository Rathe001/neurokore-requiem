---
name: EnemyClass — Resource-driven enemy archetypes
description: Enemy combat profile (melee / ranged + optional support overlay) lives in res://resources/enemies/classes/{id}.tres; EnemyClassTable autoload owns the default spawn pool registry
type: project
---
Started 2026-05-02. Following the same pattern used for perks, optics, and item modifiers — enemy behaviour is data, not code.

**Schema (`game/scripts/enemies/enemy_class.gd`):**
- `weapon_id: StringName` — identifies the weapon archetype (e.g., `&"smg"`, `&"blade"`). Used for VFX routing and future visual attachment.
- `attack_mode: AttackMode` — `MELEE` or `RANGED`.
- `basic_attack: EnemySkill` — supplies burst/spread/blast/projectile params that have no class-level counterpart (`burst_count`, `burst_delay`, `projectile_count`, `projectile_spread_deg`, `damage_mult`, `projectile_blast_radius`). For the five "attack profile" fields below the **class wins** — see the precedence note.
- Attack tuning: `attack_range`, `attack_cooldown`, `attack_windup`, `attack_damage_mult`.
- Melee fields: `melee_cone_deg`, `melee_knockback`.
- Ranged fields: `projectile_scene`, `projectile_speed`, `projectile_max_range`, `projectile_is_bullet` (kinetic vs energy visual), `ranged_kite_distance`, `accuracy`.
- Support overlay (orthogonal to attack mode): `support_role` (`NONE` / `HEAL` / `DAMAGE_BUFF`), `support_radius`, `support_interval`, `support_magnitude`.

**Class beats skill for the attack profile (since 2026-05-13):** `enemy_combat.attack_range / attack_cooldown / attack_windup / melee_cone_deg / melee_knockback` read the class fields, ignoring `basic_attack.*`. Variant classes that share a `basic_attack` resource (4 share `laser_pistol_attack.tres`, 2 share `blade_attack.tres`) used to cadence identically because the shared skill won — flipped so each class can have its own per-archetype timing. **When tuning enemy cadence / damage_mult / cone / knockback, edit the class `.tres` — the skill's matching fields are now ignored.**

**Registry (`EnemyClassTable` autoload):**
- `CLASS_FILES` array in `game/scripts/enemies/enemy_class_table.gd` — explicit file list (DirAccess fails in exports).
- `get_all()` returns the loaded pool. `EnemySpawner._get_default_class_pool()` delegates to it.
- Adding a new weapon class: drop `.tres` in `CLASS_DIR` + add filename to `CLASS_FILES`. Spawner picks it up automatically.

**Where classes live:** `res://resources/enemies/classes/{id}.tres`.

**Read pattern (in `EnemyCombat`, extracted from `PrototypeEnemy` per the v0.2.1 modularization):**
```gdscript
var range_now := _combat.attack_range()  # accessor: enemy_class → DEFAULT_*
```
Don't read `enemy_class.attack_range` directly — use the helper so the null-fallback stays consistent.

**Melee VFX routing** (in `_cast_melee_attack`): uses `weapon_id` to pick player-matching visuals — blade → `spawn_blade_slash`, sledgehammer → `spawn_hit_cone` + `spawn_hammer_impact`, other → generic `spawn_hit_cone`.

**Don't:**
- Add a new boolean export like `is_ranged: bool` on PrototypeEnemy. Extend EnemyClass instead.
- Read `enemy_class.X` directly — use `_attack_range()` / `_attack_cooldown()` / etc. accessors so fallbacks stay centralised.
- Hardcode per-archetype tuning in `prototype_enemy.gd` (e.g., "if archer, range = 12"). That data lives in the .tres.
- Hardcode class paths in the spawner — they belong in `EnemyClassTable.CLASS_FILES`.
