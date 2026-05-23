---
name: project_neon_outline
description: "Outline compositor renders a neon-tube + glow halo (was flat 1px edge). Interactables get always-on cyan when in range, white on hover."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**Shader (`outline_compositor.gdshader`).** Same SubViewport pipeline as before (flat-color highlight pass, camera mirroring, x-ray-through-walls). Different canvas_item compositor:

- Two-tap, 8-direction sampling per pixel: one ring at `core_thickness` (≈ 1.2 px) and one at `glow_radius` (≈ 6 px). 16 texture samples total — cheap.
- `core_boost` = 5.5× — pushes HDR > 1, level Environment `glow_enabled` blooms it into the "neon tube" look.
- `glow_boost` = 1.4× — softer halo, same colour, alpha tapers off so the world view shows through.
- Tunables on `outline_compositor.gd`: `NEON_CORE_THICKNESS / GLOW_RADIUS / CORE_BOOST / GLOW_BOOST`.

**Two activation paths in `HoverableInteractable`:**
1. **Mouse hover** → white outline + tooltip (as before).
2. **Proximity** → polls player distance every 0.18s (staggered per-instance on `_ready`). When within `PROXIMITY_RANGE_SQ = 6.0` (~2.45m, just past the 2.0m INTERACT_RANGE), attaches a dim cyan outline. Lets the player see "I can interact with this" without hovering — matches the "I" key prompt.

Hover takes priority for colour: in-range + hovered = white, in-range = cyan, hovered-only (rare) = white, neither = detached. Transitions go through `OutlineCompositor.set_color(mesh, color)` rather than detach+reattach so the SubViewport doesn't churn the copy node.

**Doors deliberately bypass the compositor** — the doorway walls would occlude the silhouette halo. `prototype_door.gd._build_state_frame` builds 8 explicit emissive box bars per door (4 per face) that sit out past the door surface. `emission_energy_multiplier = 5.5` matches the compositor's neon brightness so doors and other interactables read at the same intensity.

Related: [[project_godot4_shader_gotchas]] (Godot 4 disallows `return` in canvas_item fragment + TAU is a reserved builtin — both bit me on the rewrite).
