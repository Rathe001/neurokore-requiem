# Audit Action Plan — 2026-06-03

Sequenced fix plan from the 9-pass codebase audit. Findings live in
the [[project_audit_2026_06_03]] memory.

**Severity legend:** 🟥 critical (correctness/perf) · 🟧 medium (debt)
· 🟨 low (polish)

**Phases are independent** unless noted in the dependencies row. Each
phase can ship as its own commit/PR. Recommended order is by impact
and by "ship before next Steam deploy" gating.

---

## Phase 1a — MP player damage routing 🟥

**The highest-impact bug in the audit.** Remote co-op players are
immune to all enemy damage today.

**Files:**
- `game/scripts/prototype/prototype_player.gd`
- `game/scripts/prototype/enemy_combat.gd`
- `game/scenes/world/level_shell.tscn`
- Likely: a new `_spawnable_scenes` entry for projectiles

**Changes:**
1. Add `PrototypePlayer.apply_damage` static helper mirroring
   `PrototypeEnemy.deal_damage:1218`:
   ```gdscript
   static func apply_damage(target: Node3D, amount: int, knockback_from: Vector3, knockback_strength: float = 0.0) -> void:
       if NetState.is_in_lobby() and not target.is_multiplayer_authority():
           target.request_damage.rpc_id(target.get_multiplayer_authority(), amount, knockback_from, knockback_strength)
           return
       target.take_damage(amount, knockback_from, knockback_strength)
   ```
2. Add the paired RPC on `PrototypePlayer`:
   ```gdscript
   @rpc("any_peer", "call_remote", "reliable")
   func request_damage(amount: int, knockback_from: Vector3, knockback_strength: float) -> void:
       if not is_multiplayer_authority():
           return  # only the authority over this player applies damage
       if not is_inside_tree():
           return
       take_damage(amount, knockback_from, knockback_strength)
   ```
3. Update `enemy_combat.gd:246` (melee):
   ```gdscript
   PrototypePlayer.apply_damage(player, dmg, _host.global_position, melee_knockback())
   ```
4. Update `enemy_combat.gd:430` (skill cast target): same.
5. Audit any other `player.take_damage(...)` direct calls; route them
   through `apply_damage`.
6. Add enemy projectile scene to a `MultiplayerSpawner._spawnable_scenes`
   list so remote clients see incoming fire. Find the right container:
   either add to the existing enemies spawner or create a sibling
   `ProjectilesContainer` with its own spawner.
7. Verify enemy projectile damage path: the projectile's collision
   with a remote player should also route through `apply_damage`.

**Estimated LOC:** 60–80
**Risk:** medium. Touches damage-resolution; SP regression test
needed. MP test requires 2 peers.
**Verification:** kill an enemy in SP, take damage from melee enemy in
SP, then 2-player coop test — joiner takes melee damage, joiner sees
enemy bullets, joiner can be killed.

**Dependencies:** none.

---

## Phase 1b — LiquidLayer perf + stamp lifecycle 🟥

Two related fixes in the same files. Land together.

**Files:**
- `game/scripts/systems/liquid_layer.gd`
- `game/scripts/systems/wall_liquid_layer.gd`

**Changes:**
1. Fix `stamp()` lifecycle (liquid_layer.gd:232). Replace the
   `process_frame.connect(...)` block with the `create_timer(0.1)`
   pattern already used by `stamp_oriented()` at line 280. ~5 lines.
2. Switch both SubViewports off `UPDATE_ALWAYS` baseline:
   - In `_build_subviewport`, set
     `render_target_update_mode = SubViewport.UPDATE_DISABLED`
     (or `UPDATE_WHEN_PARENT_VISIBLE`).
   - In `stamp()` / `stamp_oriented()` / `stamp_growing()` set
     `UPDATE_ONCE` before adding the sprite; the system reverts after
     render.
   - For `stamp_growing()` specifically: the tween runs over
     multiple frames, so set `UPDATE_ALWAYS` at tween start, switch
     back to `UPDATE_DISABLED` at tween end.

**Estimated LOC:** 30–40
**Risk:** low. Visual-only changes; if anything breaks, blood just
doesn't deposit. Easy to spot.
**Verification:** kill enemies, confirm pools spawn. Profile a quiet
room: SubViewport draw call should be 0 when idle. Walk into combat,
confirm pools accumulate normally.

**Dependencies:** none.

---

## Phase 1c — Item schema drift 🟥

Smallest critical fix. Land independently.

**Files:**
- `game/scripts/items/item.gd`

**Changes:**
1. Add `max_charges` + `recharge_time` to `to_dict` (line 321–362).
2. Add the matching reads in `from_dict` (line 365+).

Reference `SaveManager._serialize_item` (line 348+) for exact format.

**Estimated LOC:** 4–6
**Risk:** trivial. MP-side only; SP save path is unchanged.
**Verification:** in MP, drop a Stimpack/Battery; another peer picks
it up; charges are preserved.

**Dependencies:** none.

---

## Phase 2a — Decal ring dead code purge 🟧

The biggest deletion in the audit. ~400 lines.

**Files:**
- `game/scripts/prototype/prototype_attack_indicator.gd`
- `.claude/memory/project_blood_decal_ring.md` (delete or mark
  deprecated)

**Changes — delete:**
- Functions:
  - `_apply_wall_clamp_deferred` (~1143)
  - `_track_blood_decal` (~2030) + eviction logic
  - `_get_blood_bootprint_texture` (~2226) + cache vars
  - `_get_blood_splatter_texture` (~2307) + cache vars
  - `_get_blood_wall_splatter_variant` (~2370) + cache vars
  - `_decal_color_jitter` (~2767) — replaced by `_dark_blood_decal_color`
  - `_spawn_energy_explosion` (~3206) — verify with @joshtummel
    first; might be a future API he wants kept
- Constants/state:
  - `BLOOD_DECAL_MAX`, `BLOOD_PRIORITY_FLOOR`, `BLOOD_PRIORITY_WALL`,
    `_blood_decal_ring`, `_blood_sort_counter`, `_BLOOD_SORT_STEP`
  - `BLOOD_DECAL_CULL_LAYER` — 0 external refs, confirmed orphan
  - `BLOOD_DECAL_ALBEDO_MIX` — 0 external refs
  - `OBJECT_BLOOD_LAYER`, `OBJECT_BLOOD_ALBEDO_MIX`,
    `OBJECT_BLOOD_FADE_DURATION` — 0 external refs
  - `CHARACTER_BLOOD_MAX_PER_CHAR`, `CHARACTER_BLOOD_FADE_DURATION`
    — 0 external refs
  - Note: `CHARACTER_BLOOD_LAYER` has 5 external refs — keep
- Delete `fit_collision_to_visual` (1766) only if confirmed never
  needed
- Update or delete `.claude/memory/project_blood_decal_ring.md`

**Estimated LOC:** ~400 deletions, ~0 additions
**Risk:** low. Pure deletion. Verify via headless parse + a play
session.
**Verification:** parse-check passes, kill enemies in-game, confirm
blood still spawns (it should — all this code was already
unreachable).

**Dependencies:**
- Land AFTER Phase 1b so the `stamp()` fix doesn't get clobbered.

---

## Phase 2b — Designed-not-adopted orphans + small dead code 🟧

Batch of small, independent deletions across multiple files.

**Files:**
- `game/scripts/prototype/prototype_player.gd` (8 getters)
- `game/scripts/audio/weapon_sounds.gd` (3 helpers)
- `game/scripts/items/item_roller.gd` (1 helper)
- `game/scripts/systems/save_manager.gd` (1 helper)
- `game/scripts/prototype/prototype_root.gd` (2 helpers)
- `game/scripts/level/build/wall_builder.gd` (1 helper)
- `game/scripts/level/graph/graph_solver.gd` (1 helper)

**Changes:**
- Player orphan getters: `consume_click`, `_is_near_world_interactable`,
  `is_aim_holding`, `is_channeling`, `get_effective_damage_range`,
  `_set_group_visible`, `is_in_slow_pool`, `is_in_blood_pool`
- weapon_sounds orphans: `play_miss`, `play_alt_fire`,
  `update_channel_position`
- item_roller: `_rarity_rolli_inv`
- save_manager: `has_any_saves`
- prototype_root: `_get_pickup_parent`, `corpse_count`
- wall_builder: `_hquad_top`
- graph_solver: `_snap_vec`

**Estimated LOC:** ~100 deletions
**Risk:** trivial. Multiple files, no inter-dependencies.
**Verification:** parse-check + smoke playtest.

**Dependencies:** none.

---

## Phase 3 — Defensive + polish 🟨

Tiny defensive adds. Can batch into one commit.

**Files:**
- `game/scripts/prototype/prototype_enemy.gd` (line 1877)
- `game/scripts/prototype/prototype_player.gd` (add `_exit_tree`)
- `game/scripts/items/behavior_mod_registry.gd` (line 131)
- (optional) `game/scripts/prototype/prototype_player.gd` —
  proactive `apply_heal` static helper if Phase 1a's pattern was
  adopted

**Changes:**
1. `prototype_enemy.gd:1877`: add a `_update_anim_player_active()`
   call after the direct `_state = State.DEAD` assignment, plus a
   comment noting "mirror any new `_change_state(DEAD)` side effects
   here too."
2. `prototype_player.gd`: add `_exit_tree()` matching `prototype_hud.gd`'s
   pattern (33 connects, 12 disconnects with `is_connected()` guards).
   Walk the 14 connects in the player file and add the disconnect for
   each, guarded with `is_connected`.
3. `behavior_mod_registry.gd:131`: change
   `const _CONDITION_CHECKS: Dictionary = {}`
   to include one commented example:
   ```gdscript
   const _CONDITION_CHECKS: Dictionary = {
       # &"wielding_laser_pistol": func() -> bool:
       #     var w: Item = InventoryState.get_equipped(&"weapon")
       #     return w != null and w.weapon_base_id == &"laser_pistol",
   }
   ```
4. (optional, defensive) Add `PrototypePlayer.apply_heal` static
   helper mirroring `apply_damage` so future remote-heal callers don't
   silently no-op.

**Estimated LOC:** ~40
**Risk:** none. Pure defensive code.
**Verification:** parse-check; smoke playtest; in MP confirm no
console errors on player scene tree exit.

**Dependencies:** the heal helper depends on Phase 1a landing.

---

## Suggested merge order

Bias toward shipping critical fixes early. Cleanup can wait.

| Order | Phase | What | Why now |
|---|---|---|---|
| 1 | 1c | Item schema drift | 6 LOC, ships fastest, unblocks MP consumable use |
| 2 | 1b | LiquidLayer perf + lifecycle | Independent perf win, low risk |
| 3 | 1a | MP player damage routing | Biggest impact; gate next Steam deploy on this |
| 4 | 2a | Decal ring dead code purge | Pure deletion after 1b lands; reduce file by ~400 LOC |
| 5 | 2b | Designed-not-adopted orphans | Pure deletion across multiple files |
| 6 | 3 | Defensive + polish | Closes out audit; sets up the codebase to age well |

After all phases:
- File count unchanged
- ~675 LOC removed
- 4 correctness bugs fixed
- MP coop actually playable
- Future audits faster (less dead code to wade through)

## Skip list

These were considered but explicitly NOT in the action plan:

- **Splitting `prototype_player.gd` into smaller files.** 5111 lines is
  big but well-organized. Splitting would touch every other file that
  type-references PrototypePlayer. Not worth the diff unless it gets
  unmaintainable.
- **FluidProfile resource consolidation.** 23 + 25 shader uniforms is
  approaching a refactor threshold but works today. Defer until
  multi-fluid (task #112 follow-up) actually wants different colors.
- **LoS culler perf rework.** Documented in [[project_los_reveal_spikes]]
  as the dominant remaining spike. Separate project; not in this
  audit's scope.
