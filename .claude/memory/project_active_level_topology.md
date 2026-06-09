---
name: project-active-level-topology
description: Which level/layout the game actually loads — the live first level is dungeon_demo (grid rooms) via level_shell.tscn; procgen_demo etc. are NG+ rotation, not dead
metadata:
  type: project
---

The game has MANY layouts in `res://resources/level/layouts/` (14+), and it is
NOT obvious which one a fresh playthrough builds. Verified chain (2026-06-08):

- `startup_screen.gd` → `GAME_SCENE = "res://scenes/world/level_shell.tscn"`.
  This is THE scene Play loads. (`prototype_3d.tscn` exists but is legacy — not
  the entry point.)
- `level_shell.tscn` root node is `PrototypeRoot` (`prototype_root.gd`); its
  `LevelBuilder.layout` export = **`dungeon_demo.tres`** → this is the FIRST
  level every fresh run. It builds from the 15 **`proto_grid_*`** rooms
  (`proto_grid_cross`, `_straight_ns/ew`, `_corner_*`, `_t_*`, `_dead_*`),
  all 8×8, via DungeonGenerator (sparse 7×7 maze).
- On **New Game Plus**, `PrototypeRoot.LAYOUT_POOL` (`prototype_root.gd:12`)
  cycles `procgen_demo.tres → arena_hub.tres → procgen_pit_gauntlet.tres`.
  `procgen_demo` builds the asylum/facility BranchingGenerator rooms
  (`proto_mess_hall`, `proto_medical_ward`, `proto_cell_block`,
  `proto_isolation_wing`, `proto_start_room_large`, pit rooms).

**Why:** I authored room-level data (`decal_density`) onto procgen_demo's
facility rooms and burned ~6 reload round trips before realizing the running
level was dungeon_demo's grid rooms, which never carried the property. The
data was correct; it was on rooms that don't appear until NG+.

**How to apply:** When editing room/level data to verify IN the running game,
edit the **`proto_grid_*`** rooms (dungeon_demo) — that's what a fresh Play
shows. Do NOT delete procgen_demo/arena_hub/procgen_pit_gauntlet; they are
reachable NG+ content, not cruft. The other ~10 layout `.tres` (graph_demo,
test_level, open_zones_demo, prototype_layout*, procgen_grid_demo) appear
orphaned but were not audited — confirm before assuming any is live.
Related: [[project_level_architecture]], [[project_enemy_spawning_model]].
