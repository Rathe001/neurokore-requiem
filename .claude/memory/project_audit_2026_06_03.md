---
name: codebase-audit-2026-06-03
description: "9-pass audit + all 13 findings shipped 2026-06-03 across 6 phases. 4 🟥 bugs fixed, ~1100 LOC net removed. Commit range 1c7cc4c..9339c96. Action plan history at docs/audit-2026-06-03-action-plan.md."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**SHIPPED 2026-06-03.** All 13 findings closed across 6 phases. Reference
[[audit-action-plan]] for the original sequencing; this memory now
records the as-shipped state.

## Phase shipping log

| Phase | Commit | What |
|---|---|---|
| 1c | `1c7cc4c` | Item.to_dict + from_dict gained max_charges, recharge_time. MP consumable drops preserve charges. |
| 1b | `4729bae` | LiquidLayer stamp() race fixed; both SubViewports UPDATE_DISABLED baseline with `_begin/_end_render_window` counter. |
| 1a | `8880d59` | PrototypePlayer.apply_damage + request_damage RPC; 5 enemy → player call sites routed. Remote co-op players now take enemy damage. |
| 2a | `284cf67` | -790 lines of orphaned decal-ring system from prototype_attack_indicator.gd. File 4307 → 3517. Zero remaining orphans. |
| 2b | `31882ff` | -176 lines / 16 designed-not-adopted orphans across 6 files. |
| 3 | `9339c96` | Defensive: enemy MP _state side-effect mirror; player _exit_tree disconnect pattern; apply_heal helper; behavior_mod_registry inline condition_checks stub. |

Net delta: ~+200 / -1300 = -1100 LOC. The 4 critical bugs are
documented in [[mp-damage-heal-routing]] (#1 + #2 follow-up),
[[liquid-layer-architecture]] (#3 + #4), and [[savemanager-schema-drift]] (#5).

## Scope

492 commits since v0.4.0, ~29K LOC delta across 101 .gd files. Audit
covered: attack indicator, player, enemy, combat (player + enemy),
liquid systems, items/save/mods, level builder, audio/UI/perf,
MP/host migration.

## Critical bugs (🟥) — fix before next Steam deploy

1. **Remote players immune to ALL enemy damage in MP.** Pass 4 + 9.
   - `enemy_combat.gd:246` (melee) and `:430` (skill) call
     `player.take_damage(...)` directly.
   - `PrototypePlayer.take_damage` (line 1408) early-returns on
     `_is_remote_player()`.
   - No `apply_damage` / `request_damage` RPC exists on the player —
     only `_rpc_channel_flame_start/stop` + `_request_drop_item`.
   - Enemy projectiles are also NOT in any `_spawnable_scenes` list,
     so remote players don't even see incoming bullets.
   - **Fix shape:** mirror `PrototypeEnemy.deal_damage` static helper
     pattern on the player; add projectile to MultiplayerSpawner.
   - **~80 LOC** total.

2. **`LiquidLayer.stamp()` queue_free races SubViewport render.** Pass 5.
   - Line 232 still uses `process_frame.connect` — known buggy pattern
     per [[liquid-layer-stamp-lifecycle]] memory.
   - `stamp_oriented` already uses correct `create_timer(0.1)` fix.
   - **Fix:** copy `stamp_oriented`'s pattern into `stamp`. ~5 LOC.

3. **SubViewports burn fillrate when idle.** Pass 5.
   - Both `liquid_layer.gd:367` and `wall_liquid_layer.gd:292` set
     `UPDATE_ALWAYS` and never change it.
   - 4096² SubViewport re-rendering every frame doing zero work in
     quiet rooms. Likely ~1 GB/s fillrate wasted.
   - **Fix:** baseline `UPDATE_WHEN_PARENT_VISIBLE` or `UPDATE_DISABLED`;
     flip to `UPDATE_ONCE` in `stamp()` / per-frame in `stamp_growing`.
     ~30 LOC.

4. **`Item.to_dict` missing `max_charges` + `recharge_time`.** Pass 6.
   - `to_dict` (item.gd:321) has 35 fields; `SaveManager._serialize_item`
     has 37.
   - Used by MP item drops (`_request_drop_item.rpc_id(1, item.to_dict(), ...)`).
   - Dropped consumables (Stimpacks, Batteries) lose charges in MP.
   - **Fix:** add 2 lines to `to_dict` + `from_dict`. ~6 LOC.

## Medium debt (🟧) — cleanup batches

5. **~400 lines orphan dead code in `prototype_attack_indicator.gd`.**
   Pass 1. Entire `_track_blood_decal` + decal-ring infrastructure
   orphaned by LiquidLayer migration. 8 orphan functions:
   `_apply_wall_clamp_deferred`, `fit_collision_to_visual`,
   `_track_blood_decal`, `_get_blood_bootprint_texture`,
   `_get_blood_splatter_texture`, `_get_blood_wall_splatter_variant`,
   `_decal_color_jitter`, `_spawn_energy_explosion`. Plus dead state:
   `BLOOD_DECAL_MAX`, `BLOOD_PRIORITY_FLOOR/WALL`, `_blood_decal_ring`,
   `_blood_sort_counter`, `BLOOD_DECAL_CULL_LAYER`,
   `BLOOD_DECAL_ALBEDO_MIX`, `OBJECT_BLOOD_LAYER`,
   `OBJECT_BLOOD_ALBEDO_MIX`, `OBJECT_BLOOD_FADE_DURATION`,
   `CHARACTER_BLOOD_MAX_PER_CHAR`, `CHARACTER_BLOOD_FADE_DURATION`.

6. **8 "designed-not-adopted" orphan getters in `prototype_player.gd`.**
   Pass 2. `consume_click` (323), `_is_near_world_interactable` (2335),
   `is_aim_holding` (3099), `is_channeling` (3272),
   `get_effective_damage_range` (3746), `_set_group_visible` (4048),
   `is_in_slow_pool` (4306), `is_in_blood_pool` (4359). The underlying
   state IS used internally; only the public getters are dead.

7. **`PrototypePlayer.heal` has no MP routing (latent).** Pass 9.
   Today safe because only self-callers (`player_recovery.gd`). Will
   silently fail the moment any AoE heal or "heal ally" feature lands.

8. **`BehaviorModRegistry._CONDITION_CHECKS` empty const Dictionary.**
   Pass 6. No mod can use `condition_id` until populated. Add stub
   example so the pattern is documented in-code.

9. **3 unused SFX helpers in `weapon_sounds.gd`.** Pass 8.
   `play_miss`, `play_alt_fire`, `update_channel_position`. Functions
   exist, call sites don't.

## Polish (🟨)

10. `prototype_enemy.gd:1877` direct `_state = State.DEAD` on
    remote-physics path bypasses `_change_state` side effects. Add
    defensive comment + `_update_anim_player_active()` call.

11. 2 orphan helpers in level builder: `_hquad_top` (wall_builder),
    `_snap_vec` (graph_solver).

12. 2 orphan helpers in `prototype_root.gd`: `_get_pickup_parent` (38),
    `corpse_count` (245).

13. `prototype_player.gd` has 14 connects, 0 disconnects. Should adopt
    `prototype_hud.gd`'s `_exit_tree` pattern (33 connects, 12
    disconnects with `is_connected` guards).

## Pattern observations

- **Cleanest subsystems:** level builders (Pass 7) — 2 orphans
  across 14 files. Enemy lifecycle (Pass 3) — exemplary coroutine
  hygiene with token + generation checks.
- **Reference patterns to copy elsewhere:**
  - `PrototypeEnemy.deal_damage` static helper for MP-aware damage
  - HUD `_exit_tree` for signal disconnect hygiene
  - `prototype_enemy`'s `await + is_inside_tree + generation` for
    coroutine safety
- **Where debt accumulates:** the most-churned files
  (`prototype_attack_indicator.gd`, `prototype_player.gd`) carry the
  most "designed-not-adopted" methods. Migrations left old paths in
  place rather than deleting cleanly.

## Action plan

See [[audit-action-plan]] (docs/audit-2026-06-03-action-plan.md) for
phased sequencing. Phases are designed to be independent — they can
batch into separate PRs and ship in any order, except:
- Phase 1a (MP damage routing) is the highest-impact and gates next
  Steam deploy
- Phase 2 (dead code) should land AFTER 1b (LiquidLayer fixes) to
  avoid touching `stamp()` twice

## Verification

To re-verify findings on another machine after pull:
1. `git log --oneline | grep "^c11a3b3\|^c37057b\|^bf9c0e5"` — confirm
   audit-baseline commits are present
2. Read [[audit-action-plan]] for current phase state
3. Each phase fix is independent; cross-check this memory's file:line
   refs before editing (line numbers may drift)
