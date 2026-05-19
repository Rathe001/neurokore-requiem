---
name: level-perf-hierarchy
description: What actually moves the needle on level-rendering perf in this game, in observed-impact order
metadata:
  type: project
---

Spent a long session tracking down a 28 FPS bottleneck in a multi-room view on a powerful machine. The hierarchy of what mattered, biggest to smallest:

**1. Triangle count per frame in the main pass.** The actual smoking gun was a single asset (`floor_panel_v2.glb`, PX Concrete Wall used as a floor) imported with no decimation = 299k tris per floor tile. With ~6 visible rooms × ~15 instances per floor MMI, that was ~27M tris/frame for floors alone. Re-imported at `--decimate 0.02` (~12k tris/tile) and `Tri/frm` dropped from 54M to 2.2M. FPS jumped from 28 to 60.

**How to apply:** Whenever the in-game perf overlay (`prototype_hud.gd`, F3-style overlay) shows `Tri/frm` in the tens of millions, the bottleneck is a single high-poly asset being instanced. Use `tools/inspect_kit_mesh.gd` to enumerate tri counts per kit mesh. Native Blenderkit assets are usually 30-500k tris; the `tools/import_blenderkit.py --decimate` flag is the standard mitigation.

**2. Shadow-casting lights × visible offscreen rooms.** Each room places a `FluorescentFlicker` with a shadow-casting `OmniLight3D` (cubemap = 6 face renders per frame per light). 30+ rooms × shadow-casting fluorescent = ~30 cubemap renders even when one room is visible, because the lights weren't in any culling group. Fix: add lights, particles, and fill lights to `&"room_geometry"` group so `LosCuller` toggles their `.visible` when the player isn't adjacent.

**How to apply:** Anything new that contributes per-frame cost and is room-scoped (lights, particles, fog volumes, post-process triggers) needs `add_to_group(&"room_geometry")` at build time.

**3. Kit-bash MMIs lose Godot's auto-generated shadow mesh.** Post-import scripts that replace the mesh with a new ArrayMesh discard the LOD shadow mesh `meshes/create_shadow_meshes=true` would have built. Each shadow cubemap face then renders the full-detail panel mesh. Fix: set `mmi.cast_shadow = SHADOW_CASTING_SETTING_OFF` on the kit MMI; add an invisible `BoxMesh` shadow caster (12 tris) to the wall collision body. ~500x reduction in shadow-pass tris on the kit walls.

**How to apply:** Currently the procedural shader path doesn't use kit MMIs, so this fix is dormant. If kit-panel walls come back (a future wall-authored asset), the `_add_shadow_caster` pattern in `wall_builder.gd` is the template.

**4. WorldEnvironment volumetric fog with no light feeders.** `volumetric_fog_enabled = true` runs the volumetric pass every frame even when no Light3D feeds it (every Light3D in this scene has `light_volumetric_fog_energy = 0.0`). The pass renders nothing visible but still costs frame time per FogVolume. Fix: `volumetric_fog_enabled = false` in `level_shell.tscn`, `LightingBuilder.create_fog_volume()` early-returns.

**How to apply:** If `volumetric_fog_enabled` flips back on for any reason, also set at least one light's `light_volumetric_fog_energy > 0` and unblock `create_fog_volume`, OR you're paying the GPU cost for invisible output.

**Non-issues that *looked* like issues during diagnosis:**
- TAA artifacts → was actually 8-bit color banding masked poorly by uniform pale surfaces. `use_debanding=true` + surface noise.
- Particles → ~5 visible / 47 total, room-cull worked, not a bottleneck.
- MMI count → only 8-10 visible MMIs even in a complex view, not a bottleneck.
- Draw calls → 300-500 visible draws, well below problem range (~10k+).
- AI/CPU cost from offscreen enemies → invisible enemies still run AI, but at 150-200 enemies this didn't dominate frame time in practice.

The in-game debug overlay (`prototype_hud.gd`, fields `Lights: V/T  shadow S | MMI | Particles V/T | Draw | Tri/frm`) is the right diagnostic — every time we measured we found the real bottleneck within one screenshot.
