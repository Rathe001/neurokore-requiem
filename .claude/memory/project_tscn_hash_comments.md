---
name: tscn-hash-comments
description: "'#' comments inside .tscn resource blocks silently void the properties after them — Godot only supports ';' comments. Voided the switch collision box (1x1x1 default) through three bug reports."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**`.tscn` comments must use `;` — `#` lines inside a resource/node block
abort that block's property parse silently.** No error, no warning: the
properties after the `#` line just load as defaults.

**Why:** The switch console's authored collision (`size = Vector3(2.86,
2.2, 2.87)` + Y=1 transform) was preceded by `#` comment lines. Godot
loaded the shape as a default 1×1×1 cube at the origin — the player
walked straight inside the console. The bug was reported three separate
times (b543176 box fix, the `_set_interactive` layer fix, and again
2026-06-10) because each fix was real but the scene file itself was
voiding the box.

**How to apply:**
- Only `;` comments in `.tscn`/`.tres` files, ALWAYS.
- When a collision/size property "doesn't work" despite being authored
  correctly, run `scripts/tools/audit_interactables.gd` (headless) —
  it prints MEASURED visual AABB vs loaded collision box per
  interactable scene, catching both parse-voided properties and
  visual/box drift.
- Related: [[blenderkit-import]] models have off-center origins; never
  trust a scaled-bbox estimate over the measured AABB (exit platform
  and loot crate boxes were ~0.4m too deep from bbox estimates).
