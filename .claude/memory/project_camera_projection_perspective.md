---
name: project_camera_projection_perspective
description: Camera switched from PROJECTION_ORTHOGONAL (size=22) to fake-ortho perspective (FOV=18° at ~70m distance). F8 toggles. Several depth-based bugs got their foundation back.
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**Why we switched.** Ortho's depth buffer has fundamentally different semantics than perspective + reverse-Z. Screen-space passes that assume perspective rays diverge from a point (SSR, volumetric fog, soft particle depth comparisons, the tactical-overlay LoS clip) all collapsed or misbehaved under ortho. The fake-ortho perspective rig keeps the visually-identical D2 framing while restoring well-defined depth semantics.

**Setup.**
- `level_shell.tscn` and `prototype_3d.tscn`: `fov = 18.0`, `far = 250.0`. `size = 22.0` kept for the F8 toggle fallback.
- `PrototypeCamera` `@export var offset: Vector3 = Vector3(18.4, 64.4, 18.4)` — magnitude ≈ 69.5m, direction matches old (4, 14, 4) so pitch (22° from vertical) and bearing (45° SE) are unchanged. View height at FOV 18° × 70m ≈ 22m, identical to the legacy ortho extent.
- `_FOCAL_CHEST_OFFSET = 1.2` always lifts the focal point off the player origin; gives a centre-of-mass anchor.
- **F8** toggles between PROJECTION_PERSPECTIVE and PROJECTION_ORTHOGONAL at runtime. Both are valid; ortho ignores distance entirely so the offset works visually for either.

**Bugs the switch fixed.**
- Tactical-overlay LoS clip — 6 failed attempts under ortho all assumed reverse-Z. Now `discard if scene_depth < 0.0005 || scene_depth > FRAGCOORD.z + 0.0005` works (see `tactical_overlay.gdshader`). Rings clip to level interior.
- Explosion flipbook (`ExplosionShader.tres`) was reconstructing view-space with `depth * 2.0 - 1.0`, the old GL `[-1, 1]` convention. Godot 4 perspective uses `[0, 1]` NDC z. The wrong remapping collapsed the soft-blend factor toward zero, multiplying flipbook alpha to ~0 — read as "explosion animation lost." Fix: pass `depth` and `FRAGCOORD.z` straight through `INV_PROJECTION_MATRIX` without the `* 2.0 - 1.0`.
- Inspect-mode zoom went from "broken" (changing `_distance` did nothing under ortho's parallel projection) to functional once perspective gives distance a meaning.

**Bugs the switch introduced and we patched.**
- `Label3D.fixed_size = true` compensation lands ~5× too large under FOV=18°. Added `PrototypeCamera.label_fixed_size_scale()` (returns 0.2 in perspective, 1.0 in ortho). All `fixed_size = true` label setup sites multiply their authored `pixel_size` by this — see `prototype_item_pickup`, `prototype_credit_pickup`, `enemy_afflictions`.
- Accelerator flame `_apply_flame_transform` hardcoded the muzzle to `(0, FLAME_MUZZLE_HEIGHT, 0)` — once the camera fixed-iso assumption changed, the disconnect with the new WeaponAttachment muzzle became obvious. Now reads `WeaponAttachment.get_muzzle_position(skel, aim_norm)`.

**Camera distance is no longer "close to the player."** SDFGI cascades, light shadow culling, and proximity-distance-based effects measure from the camera position, which is now ~70m back instead of ~14m. Watch for cascade-distance issues if lighting suddenly fades or pops in differently from before.

Related: [[project_godot4_shader_gotchas]] (reverse-Z depth math), [[feedback_no_camera_lerp]] (still apply; the perspective switch didn't enable smoothing).
