---
name: blenderkit-normals-fix
description: "Don't bulk-recalculate normals on Blenderkit models — 'Recalculate Outside' destroys intentionally-inverted detail (recessed panels, inner flaps). Fix individual models by hand; never run tools/fix_normals.py without a filter."
type: project
---

> Reconstructed 2026-06-19 from the MEMORY.md index hook — the original file
> was lost to canonical/mirror drift before it was ever committed. Content below
> is faithful to the recorded summary; if more detail surfaces, expand it.

Bulk `Recalculate Outside` (Blender's normal recalculation) on Blenderkit-
imported models **destroys intentionally-inverted detail** — recessed panels,
inner flaps, and other geometry that relies on flipped normals to read
correctly. The auto-recalc flattens everything to face "outside," which breaks
those surfaces.

**Rules:**
- Do NOT auto-recalc normals across a whole model or in bulk.
- Fix problem models individually, by hand, in Blender.
- The models are untracked in git — there is **no rollback** if you corrupt them.
- Do NOT run `tools/fix_normals.py` without a filter restricting it to the
  specific model(s) that actually need it.

See [[blenderkit-import]] for the import workflow these models come through.
