---
name: headless-audit-tools
description: Four headless measurement scripts in game/scripts/tools/ (characters, materials, interactable boxes, clip ground/yaw) + the SceneTree-harness gotchas. Measure before guessing — every animation/collision bug this session fell to one of these.
metadata:
  type: project
---

Run any of these with:
`Godot_console.exe --headless --path game --script scripts/tools/<tool>.gd`

- **audit_characters.gd** — tri/surface counts, shadow flags, texture
  refs per character FBX.
- **audit_material.gd** — ACTIVE material slot wiring + loaded texture
  dimensions for representative meshes. CRITICAL: read
  `get_active_material()` (override-aware) — the meshy post-import
  script applies the REAL PBR set as a surface override; the inner FBX
  material is dormant (reading it produced a false "no roughness"
  audit finding).
- **audit_interactables.gd** — measured visual AABB vs collision box
  per interactable scene. The checker for [[tscn-hash-comments]]-class
  bugs and box/visual drift.
- **audit_clip_ground.gd** — per-clip foot-contact min + hips yaw.
  Caught the ±10cm per-clip ground spread behind the floating-feet bug.

Harness gotchas (cost a round each):
- SceneTree-script `_init` runs before the tree is active — node adds
  aren't in-tree (global transforms error). Defer via
  `_measure.call_deferred()`.
- Pose sampling: `ap.stop(); ap.play(clip); ap.advance(t);
  skel.force_update_all_bone_transforms()` — seek(t, true) alone may
  not bind.
- GDScript lambdas capture ints BY VALUE — accumulate into a
  Dictionary, not bare counters.
- Headless `--headless --path game res://scene.tscn` runs a scene
  directly (the default main scene sits at the menu); errors land on
  stderr, prints on stdout — capture both files.
