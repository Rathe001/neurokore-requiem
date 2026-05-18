---
name: kit-panel-corner-mitre-pending
description: "Kit-bash wall/floor panels now auto-normalize on import; next step is shader-based 45° mitre at panel ends so corners are clean from both inside AND outside views (arena-with-inner-room case)"
type: project
---

**Current state (as of 2026-05-18).**

Kit panel pipeline is in a clean baseline awaiting mitre work:

- `game/scripts/level/build/kit_panel_post_import.gd` — Godot `EditorScenePostImport` script that auto-normalizes `.glb`s whose path contains `wall_panel` or `floor_panel`. Detects source axis orientation from the AABB, rotates to canonical, centers AABB on origin, bakes transform into vertices+normals+tangents. Wired into `wall_panel_v4.glb.import` and `floor_panel_v2.glb.import` via `import_script/path`.
- Canonical orientations:
  - **Wall:** X = length, Y = thickness, Z = height
  - **Floor:** X = long tile dim, Y = short tile dim, Z = thickness
- Quantization moved upstream to `GraphSolver.solve(graph, grid_size)` (level_builder passes the kit grid). Room positions are derived from quantized room sizes + corridor lengths, so the corridor walls never over-shoot into rooms. No more in-place mutation of shared `RoomDef`/`CorridorDef` resources.
- Collision wall span matches visual wall span (`rd.size`, not `rd.size + thick`).
- Panel thickness is **kept at native scale** (~2.5cm) — earlier experiments stretched it to `wall_thickness` (0.4m) which blew up the kit's decorative belt relief 16× into a shelf. Don't go back to that.

**Why:** Quantization slop was making corridors extend `thick/2` past room boundaries, producing an X-cross at corners. Native-thickness panels eliminate the belt-distortion side effect. Auto-normalization means new Blenderkit kits don't need per-asset orientation hacks.

**How to apply (adding a new kit panel from Blenderkit):**

1. Drop the `.glb` and its textures into `game/assets/models/objects/wall_panel_v<N>/` or `floor_panel_v<N>/` (the path-prefix is the type signal).
2. In the inspector, set `import_script/path` to `res://scripts/level/build/kit_panel_post_import.gd` on the new `.glb.import`.
3. Reimport. Asset arrives in canonical orientation with AABB centered.
4. Point the relevant theme `.tres` (`amber_theme`, `dim_theme`, `tech_theme`) at the new model and reload the level.

No more manual rotation chains. The `WallBuilder`/`FloorBuilder` `height_in_y` auto-detection still works as a safety net but should never fire on a properly imported asset.

---

**Pending work: shader-based mitre at panel ends.**

The remaining visual issue: with thin native-thickness panels at the wall centerline, perpendicular walls meet at a corner line but the panel **bodies** don't fill the wall-thickness corner cube. Two symptoms:

- Inside corners look slightly gappy from some angles
- Outside corners can't be cleaned up at all — relevant for the planned **"room inside an arena"** case where outer walls become visible to the player

The procedural fallback at `wall_builder.gd:471-477` already mitres correctly (`build_room_mesh` → `_add_mitred_wall` → trapezoidal footprints with a 45° diagonal seam at each corner). The kit path should do the equivalent.

**Why:** Mitring is the standard solution. It works regardless of panel thickness (so we can author panels at any thickness without overlap or gap concerns), and it cleans up both inside and outside corners uniformly.

**Implementation plan (shader-based, preserves single-MultiMesh batching):**

1. Add a `ShaderMaterial` to the kit panel material with a fragment-stage 45° clip plane controlled by `INSTANCE_CUSTOM`.
2. Pack per-instance mitre flags into the 4-component custom data: `(mitre_left, mitre_right, _, _)` as 0.0/1.0 floats.
3. In `WallBuilder._add_tiled_wall_segment` (and the floor equivalent), decide which end of each panel needs a mitre. For a multi-panel wall, only the **leftmost** panel gets mitre_left, only the **rightmost** gets mitre_right.
4. The shader discards fragments that fall outside the 45° plane at the mitred end. Clip plane math is in model-local space: at the right end, discard if `vertex.x > (half_length - half_thickness) + abs(vertex.z)`.
5. Verify the shader runs against the kit's existing materials (likely needs material extension or a global wall shader override).

**How to apply when resuming:**

- Pair this work with re-authoring (or re-importing) at least one kit panel at `wall_thickness`-thick native dimensions, so we can also remove the thin-panel/centerline visual gap entirely (full-thickness panels with mitred ends will sit flush against the collision plane on both faces).
- Keep the existing thin-panel path working in parallel until the mitre shader is verified — flip themes between thin and thick assets to A/B compare.

**Files to revisit:**

- `game/scripts/level/build/wall_builder.gd` (placement + new shader uniform setup)
- `game/scripts/level/build/floor_builder.gd` (mitre may not be needed for floors but the import script is shared)
- `game/scripts/level/build/kit_panel_post_import.gd` (already canonical; no changes expected)
- New: `game/scripts/level/build/kit_panel.gdshader` (or wherever the shader lives)
