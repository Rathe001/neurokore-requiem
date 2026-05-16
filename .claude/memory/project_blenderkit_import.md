---
name: blenderkit-model-import-workflow
description: "Use tools/import_blenderkit.py to bring a Blenderkit model into the project as a clean .glb. The user downloads in Blender's Blenderkit panel first (handles auth/payment), then the script converts the cached .blend to .glb without modifying geometry. NEVER bulk-process or recalculate normals — that was destructive."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**Tool:** `tools/import_blenderkit.py`

**Workflow when the user shares a Blenderkit asset_base_id or search query:**

1. The user has to download the asset in Blender's Blenderkit panel first
   (Blenderkit's addon handles auth, credits, and rate-limiting for paid
   assets). Blenderkit caches the source .blend under
   `~/blenderkit_data/models/<slug>_<id>/`.

2. Run the import script:
   ```
   python tools/import_blenderkit.py <asset_base_id> <target_name> [--category objects]
   ```
   - `asset_base_id` is the UUID from the Blenderkit URL (e.g. the one in
     `https://www.blenderkit.com/get-blenderkit/<UUID>/`). The script
     accepts either the bare UUID or a full Blenderkit search-query
     fragment like `asset_base_id:UUID asset_type:model`.
   - `target_name` is the project slug (e.g. `barrel3`, `console2`).
   - `--category` defaults to `objects`; use `characters` for rigged figures.

3. The script:
   - Queries Blenderkit's anonymous search API to bridge asset_base_id
     (URL form) → `id` (cache-folder form). They are NOT the same UUID.
   - Locates the cached .blend file.
   - Opens it in headless Blender and exports as `.glb` with default
     glTF settings (normals + tangents + skinning + animations preserved,
     no geometry modification).
   - Appends a row to `docs/assets.md` so the asset is tracked for
     license verification.

**Critical: do NOT modify geometry on import.** The previous
`tools/fix_normals.py` ran "Recalculate Outside" globally and destroyed
intentionally-inverted detail (recessed panels, inner cardboard flaps,
hollow sci-fi monitor cavities) on ~half the Blenderkit assets. That
tool no longer exists. The right approach for normal issues is
per-model in Blender's UI: enable Face Orientation overlay, select
only the red faces, `Mesh → Normals → Flip`. Surgical, not bulk.

**If a model has visible "transparent / inside-out" faces after import:**
- Don't auto-fix. Tell the user to open the .glb in Blender, use Face
  Orientation overlay to find red faces, flip those specifically, re-
  export over the imported .glb.
- Or — if the user is fine living with it — `ClutterBuilder.disable_backface_culling`
  still exists as an opt-in per-model workaround (call it from the
  specific consumer's `_ready`, not globally).

**Hard-won lesson (don't repeat):** Untracked .glbs under
`game/assets/models/` mean no rollback if a destructive transform runs.
Either commit before running anything destructive, or copy to a backup
location first. The import script is non-destructive by design — it
exports default glTF settings without any geometry passes.
