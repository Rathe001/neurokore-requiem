---
name: kit-panel-corner-mitre
description: "Kit-bash wall panels mitre at 45° via per-instance INSTANCE_CUSTOM shader clip. System is complete and dormant — production themes use procedural walls; activate by pointing a theme's wall_model at a kit panel .glb."
type: project
---

**Status: done** (committed in `cbd1640`, paired with the quantization fixes in `c04edfd`). The system is fully wired but inactive because every production theme has `wall_model = null` and falls through to procedural walls. To see it run, set `wall_model = ExtResource("...wall_panel_v4.glb")` (or any imported kit panel) on a theme and reload.

**How it works end-to-end:**

1. `kit_panel_post_import.gd` runs on any `.glb` whose path contains `wall_panel` or `floor_panel`. For walls it:
   - Rotates the mesh to canonical orientation (X = length, Y = thickness, Z = height)
   - Symmetrically thickens to `WALL_THICKNESS_TARGET = 0.4` along Y so the panel fills the wall thickness corner cube
   - Swaps each surface's `BaseMaterial3D` for a `ShaderMaterial` running `kit_panel.gdshader`, copying albedo/normal/roughness textures across (with white / flat-normal fallbacks for unbound channels)
   - Sets `half_length` and `half_thickness` on the material from the post-bake AABB
2. `WallBuilder.build_room_walls_kit` / `build_corridor_walls_kit` builds the MMI:
   - Spans extend by `thick` past nominal so adjacent perpendicular walls overlap in a corner cube
   - Per-instance `custom_data` packed as `(mitre_left, mitre_right, scale_w, 0)`: first horizontal tile gets `mitre_left = 1.0`, last gets `mitre_right = 1.0`, scale_w is the per-instance X stretch
3. `_commit_kit_mmi` sets `MultiMesh.use_custom_data = true` and writes each instance's custom data
4. `kit_panel.gdshader` fragment stage reads `INSTANCE_CUSTOM` (passed through a varying from vertex), computes a world-space 45° clip plane against the panel's local X (scaled by `scale_w`) ± its local Y, and `discard`s fragments outside. Result: each corner-cube overlap gets split diagonally, no inside-corner gap and no outside-corner overhang.

**Files:**

- `game/scripts/level/build/kit_panel.gdshader` — the clip + PBR shader
- `game/scripts/level/build/kit_panel_post_import.gd` — the EditorScenePostImport hook (set as `import_script/path` on each kit `.glb.import`)
- `game/scripts/level/build/wall_builder.gd` — `_add_tiled_wall_segment`, `_commit_kit_mmi`, `build_*_walls_kit`

**Why thin panels at native scale were rejected:** earlier prototype kept panels at their authored ~2.5cm thickness. Looked correct from above but left the wall thickness corner cube empty, and there was no way to fill it without overlap into adjacent rooms. Symmetric thickening to `wall_thickness` makes panels fill the cube; the mitre clip then resolves the overlap with the perpendicular wall diagonally. (Side effect: any decorative belt relief authored in the Y direction gets stretched ~16× — author kit panels with their detail in X/Z, never Y.)

**When adding a new kit panel:** drop the `.glb` + textures into `game/assets/models/objects/wall_panel_v<N>/`, set `import_script/path = res://scripts/level/build/kit_panel_post_import.gd` on the `.glb.import`, reimport. Asset arrives in canonical orientation with the mitre shader already attached.
