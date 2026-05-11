---
name: Named monsters (NamedMonster)
description: Named encounters live in res://resources/enemies/named/{id}.tres; spawner rolls 0.5% per spawn point, preempts pack roll, applies fixed identity + EnemyClass + affixes
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
Shipped 2026-05-02. Super-rare unique encounters — fixed name, fixed EnemyClass, fixed affix list, extra stat boost on top of affixes, larger model, gold (or themed) ring tint, guaranteed minimum-rarity drop.

**Schema (`game/scripts/enemies/named_monster.gd`):**
- `display_name` — replaces the rolled trash name AND skips the affix-prefix decoration ("Vex, the Sundered" not "Frenzied Jagged Vex…").
- `enemy_class: EnemyClass` — required. Defines attack mode + base tuning.
- `affixes: Array[MonsterAffix]` — fixed list. Authored not rolled.
- `health_mult`, `damage_mult` — multiplicative on top of the affix mults (compound).
- `visual_scale` — model scale boost (typically 1.25-1.35).
- `ring_tint` — overrides both affix tint and level tint (named is the headline visual).
- `weight`, `min_level` — weighted-roll filters.
- `guaranteed_drop_rarity` — kill drop is forced AT this rarity (not "or higher" — keeps reward predictable).

**Where named live:** `res://resources/enemies/named/{id}.tres`. `NamedMonsterTable` autoload scans the directory at `_ready`. Currently shipped:
- `vex_sundered.tres` — Frenzied Jagged ranged_buffer, gold ring, level 1+
- `cinder_hollowlit.tres` — Burning Tough basic_melee, deep orange, level 1+
- `mother_wreath.tres` — Vampiric Tough melee_healer, purple, level 3+

**Spawn flow (`game/scripts/level/build/enemy_spawner.gd`):**
1. Each spawn point rolls `NAMED_CHANCE` (0.5%) FIRST.
2. On hit: `NamedMonsterTable.roll_random(level, rng)` → spawn one solo named (no companions).
3. On named-pool-empty for the level: fall through to the regular pack roll.
4. Otherwise: regular `PACK_CHANCE` (6%) roll proceeds.

**Application in PrototypeEnemy.\_apply_level_stats:**
1. If `named_monster != null`, copy `named.enemy_class → enemy_class` and `named.affixes → affixes`. Both BEFORE the affix-mult pass so existing accessors (`_attack_range`, `_attack_cooldown`, etc.) pick up the named's behaviour without a separate "is named?" branch.
2. Affix mults compound onto the rolled level stats (existing path).
3. `named.health_mult` and `damage_mult` compound on top of those.
4. Tint priority: `named.ring_tint` > first affix's tint > level tint.
5. `visual.scale = ONE * named.visual_scale` when named.
6. `display_name = named.display_name` (replaces the affix-prefix path entirely).

**`_drop_item` override:** named monsters skip the level-scaled drop chance (always drop), pick a random main_type, and force the rarity to `named.guaranteed_drop_rarity`.

**Pool-leak prevention:** every spawn path that uses the trash scene must explicitly set `affixes = []` AND `named_monster = null` before `reset()` so a pool-recycled body can't inherit the previous owner's identity. Already wired in `EnemySpawner._spawn`, `prototype_boss_spawn._spawn`, `prototype_root._spawn_wave`, `prototype_root._spawn_boss`.

**Per-piece hand-placement (future):** `LevelPiece.named_monster_override: NamedMonster` would let designers put a specific named in a specific room. Not wired yet — random rolls are the only spawn path so far. When wiring it, set `enemy.named_monster = override` before reset() the same way the random-roll path does it.

**Don't:**
- Stack named + pack — named preempts pack on purpose. A "named pack" is a future feature, not a bug to fix.
- Author named monsters with no `enemy_class` — the spawn will use the scene's default class (basic_melee), which is rarely what the named author intended.
- Use `is_boss` and `named_monster` on the same enemy — boss uses `_apply_boss_stats` which exits early before named handling. Pick one path.
