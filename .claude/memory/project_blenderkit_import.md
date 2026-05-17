---
name: blenderkit-model-import-workflow
description: "tools/import_blenderkit.py converts a Blenderkit-cached .blend → .glb with several Godot-iso-camera-friendly fixes baked in. Workflow: user downloads in Blender first (handles auth), then script imports."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`tools/import_blenderkit.py` is the canonical import path for any Blenderkit asset. User downloads via Blender's Blenderkit panel first (handles auth + caches under `~/blenderkit_data/models/<slug>_<id>/`), then run the script with the asset_base_id from the asset's URL or search-string.

```
python tools/import_blenderkit.py <asset_base_id> <target_name> [--category objects] [--decimate 0.5] [--tint-emission "50,200,230"]
```

The script's Blender headless preprocessing applies, in order:

1. `unpack_all` packed images so paths resolve.
2. **UDIM handling** — glTF can't export `image.source == 'TILED'`. The script walks the .blend's cache directory looking for tile-1001 files (Blenderkit ships them under `textures/` even when the blend references `textures_2k/` — folder-name mismatch is common). Found tiles are loaded as regular non-tiled images and references swapped. Tiles that can't be found get disconnected from materials, AND the material's `Emission`/`Emission Strength` inputs are zeroed (else the missing texture-mask leaves the whole surface glowing white).
3. **Colorspace preservation** — swapped images inherit the original TILED image's `colorspace_settings.name` so normal/metallic/roughness/emissive maps don't get misinterpreted as sRGB.
4. **`--decimate` ratio** (optional) — Decimate modifier (COLLAPSE) before export. Use 0.4–0.6 for iso-camera clutter where fine triangles are sub-pixel anyway.
5. **`--tint-emission "r,g,b"`** (optional) — recolors every emissive texture to `luminance × tint` via numpy. Preserves the brightness pattern but remaps the hue (e.g. the Sci Fi Crate ships red emission, retinted cyan to match its preview).
6. **Per-material**: `use_backface_culling = False` (glTF `doubleSided=true`), `blend_method = 'OPAQUE'` (kills alpha-blend depth sort issues).
7. **Export**: `export_apply=True` bakes Solidify/Mirror/Subsurf modifiers into the geometry.

Appends a row to `docs/assets.md` automatically for credit/license tracking.

**Why:** Blenderkit ships film/VFX-quality models that fight Godot's iso rendering — UDIM textures, clearcoat extensions, alpha-blend decals, inverted normals, full-detail PBR. We learned the hard way; this script encodes every fix we've found.

**How to apply:** for any new third-party model that imports glitchy, run `python tools/inspect_glb.py <path>` first to see what extensions/animations/material setup it has, then decide if we need to extend the import script further.

**NEVER** bulk-recalculate normals — destroys intentionally-inverted detail (recessed panels, inner cardboard flaps, hollow sci-fi monitor cavities). The previous `tools/fix_normals.py` did this and broke half of our assets; that tool no longer exists. Per-model in Blender's UI is the right approach for normal issues.

See [[project_los_culler_transparency_pass]] for the related "model looks glitchy in-game" red herring — that was almost always our LoS culler routing meshes through the transparent pipeline, not the .glb's fault.
