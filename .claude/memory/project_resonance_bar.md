---
name: Resonance bar is world-space
description: Accelerator resonance bar moved from HUD to 3D cast bar under player using health_bar.gdshader
type: project
---

Resonance bar (Accelerator ramp indicator) is now a world-space MeshInstance3D under the player, not a HUD element. Uses the same `health_bar.gdshader` as enemy health bars (billboarded quad, depth_test_disabled, instance shader params for fill_ratio/fill_color). Label3D shows "RESONANCE" above. Built programmatically in `_build_resonance_bar()` in prototype_player.gd.

**Why:** User wanted it to feel like a cast bar under the character, not a HUD element.
**How to apply:** Any future cast/channel bars should follow this pattern — reuse health_bar.gdshader with instance params, child of the player node.
