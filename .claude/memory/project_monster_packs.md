---
name: Rare monster packs (MonsterAffix)
description: Rare-pack modifiers live in res://resources/enemies/affixes/{id}.tres; EnemySpawner rolls per spawn point, leader + companions inherit the same affix list
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
Shipped 2026-05-02. Diablo-2-style rare packs — chance per spawn point that a regular trash spawn becomes a leader with 1-2 modifier prefixes, plus 1-3 companions inheriting the same modifiers.

**Schema (`game/scripts/enemies/monster_affix.gd`):**
- `id`, `label` — identity + display prefix.
- Stat multipliers: `health_mult`, `damage_mult`, `attack_cooldown_mult` (< 1.0 = faster), `move_speed_mult`.
- Visual: `ring_tint` overrides the level-based floor-ring color when this affix is the leader's first one.
- Roll: `weight`, `min_level` for the weighted picker.
- Effect hooks: `effects: Array[StringName]` — reserved labels (`lifesteal`, `thorns`, `ignite`) inert until the damage-type / status-effect framework lands. Author them now so data is forward-compatible.

**Where affixes live:** `res://resources/enemies/affixes/{id}.tres`. `MonsterAffixTable` autoload scans the directory at `_ready` — adding a new affix is a drop-in `.tres`, no code edit. Currently shipped: frenzied, tough, jagged, vampiric, quickfoot, burning.

**Spawn flow (`game/scripts/level/build/enemy_spawner.gd`):**
1. Each spawn point rolls against `PACK_CHANCE` (6%).
2. On hit: `MonsterAffixTable.roll_affixes(1-2, level, rng)` — distinct picks (no `Tough Tough`).
3. Leader spawns at the rolled position with the affix list set BEFORE `reset()`.
4. 1-3 companions spawn on a ring around the leader (`PACK_COMPANION_RADIUS = 2.5`), all sharing the same affix list. Companions get clamped to piece bounds so they don't punch into walls.
5. The pack counts against the piece's enemy budget — a 4-pack in a 6-enemy room leaves room for 2 more solo spawns.

**Application in PrototypeEnemy:**
- `affixes: Array[MonsterAffix]` exported field — set by spawner before `reset()`.
- `_apply_level_stats` compounds `health_mult` and `damage_mult` onto the level-rolled values.
- `_attack_cooldown()` and the chase / backpedal / return speed computations multiply by `_affix_attack_cooldown_mult()` and `_affix_move_speed_mult()`.
- First affix's `ring_tint` overrides the level tint on the floor ring (no blending — players need to learn one-color-per-affix, blended muds wouldn't read).
- `display_name` gets the affix labels prepended ("Frenzied Tough Husk").

**Affix-leak gotcha:** the pool reuses bodies; if a pack member dies, its corpse-recycled instance still carries the affix list when a new spawner picks it up. EnemySpawner ALWAYS sets `enemy.affixes = ...` before `reset()` (empty list for solo spawns) so leaks can't happen via the standard path. **Boss spawns and wave spawns must do the same** — `prototype_boss_spawn.gd` and `prototype_root.gd` (`_spawn_wave`, `_spawn_boss`) explicitly set `affixes = []` for this reason. New spawn paths must follow.

**Don't:**
- Stack affixes additively for the same stat — `roll_affixes` returns distinct entries on purpose. Two `Tough` would be confusing visually (single ring tint) and balance-wise (4× HP).
- Author `effect` IDs that don't have a corresponding consumer planned. They're inert today; adding them with no plan is dead data.
- Mix the boss `is_boss` boost path with affix application — the boss ring tint and stat scaling come from `_apply_boss_stats`, not affixes.
