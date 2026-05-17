---
name: los-culler-transparency-pass
description: LoS culler's lerp must snap to exactly 0/1 — non-zero transparency routes meshes through Godot's transparent rendering pipeline, causing camera-angle-dependent face dropouts on multi-surface meshes
metadata:
  type: project
---

`los_culler.gd` lerps each tracked entity's `transparency` between 0 and 1 based on player visibility. `lerp` asymptotes — it never reaches exactly 0. Even a value like 0.001 routes the `GeometryInstance3D` through Godot's transparent rendering pipeline (no depth writes, back-to-front sort).

**Why:** caused our long-running "textures look glitchy" feel across every interactable, enemy, pickup, corpse, etc. Multi-surface meshes (the Sci Fi Crate showed it worst) had faces drop in/out as the camera rotated. Once we snapped the lerp to exactly 0 once within ~0.005 of the target, every entity went back to the opaque pass and the glitching stopped completely.

**How to apply:** any time we add a new visibility-fade system that uses `lerp` toward 0 or 1, snap to the exact value once close enough. Same applies to alpha-fade tweens — finish at exactly 0 or 1, not just "close." Symptom to watch for: meshes look fine in Blender preview but fail subtly in Godot in ways that depend on camera angle. See [[project_los_culler_room_gate]].
