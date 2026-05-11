---
name: Point-blank ranged accuracy penalty
description: Ranged attacks (hitscan + projectile) against targets within 2.5m of the fire origin have accuracy halved. Encourages disengage-and-shoot. Count "Point Blank" talent waives the penalty for player-fired ranged attacks.
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
**Rule:** Player and enemy ranged attacks (hitscan and projectile targeting modes) check distance from fire origin to the impact target. If within `MELEE_RANGE_THRESHOLD = 2.5m`, accuracy is multiplied by `MELEE_RANGE_ACCURACY_MULT = 0.5`. Cone and AoE skills are exempt.

**Implementation:**
- `PlayerCombat._resolve_hitscan` computes `target_dist` and passes the multiplier to `_roll_hit(weapon, mult)`.
- `PrototypeProjectile._roll_hit(target_pos)` does the equivalent at impact time, using `source_position.distance_to(target_pos)`. Constants are duplicated in both files (small enough to drift-detect; comments say to keep in sync).
- Enemy-fired projectiles also obey this — charging into a ranged enemy is a viable counter (their bolts miss more often).

**Count "Point Blank" talent** (`ort.tres` T1, node 0): grants `ignore_point_blank_penalty` aggregate via `Effects.get_aggregate(...)`. When non-zero AND projectile is player-fired (`target_group == &"enemies"`), the penalty is skipped. Enemy projectiles still suffer the penalty regardless of player class.

**Stacking with the talent:** Equipping a high-`hit_chance_bonus` weapon and stacking accuracy into the 1.0+ range can effectively cancel the 50% penalty even without Point Blank — `_roll_hit` clamps `acc *= mult` and returns true if `acc >= 1.0`. So there's a build path to mitigate the penalty without spending the talent point, but it costs gear roll budget.

**Why:** Pushes the player toward the design pillar of "deliberate, weighted, build-dependent combat" — sprinting to gain distance becomes a tactical choice, not optional. Also gives the Survivalist + Count classes natural counter-play differentiation (Survivalist sprints; Count can spec into Point Blank).

**How to apply:**
- New ranged skill types (charged shots, beams, etc.) should route through `_roll_hit(weapon, mult)` with the same distance-based multiplier.
- Tuning lever: lower the multiplier (0.5 → 0.7) to soften the penalty, or shrink the threshold (2.5 → 1.5) to only catch true point-blank.
- The penalty is documented in `prototype_player.gd` and `prototype_projectile.gd` comments; if changing the rule, update both.
