---
name: light-volumetric-fog-energy
description: Every Light3D needs light_volumetric_fog_energy = 0.0 explicitly — Godot's default of 1.0 scatters into FogVolumes and produces a screen-space halo even with env.volumetric_fog_enabled = false
metadata:
  type: project
---

Godot's per-light `light_volumetric_fog_energy` defaults to **1.0**. Any Light3D that doesn't explicitly set it to 0 injects energy into the per-room FogVolumes, which Godot's volumetric fog accumulates across screen space. Result: a V-shaped halo radiating from room corners into the void, visible even though the env-level `volumetric_fog_enabled = false`.

**Why:** the halo doesn't respect shadow casters — it's screen-space scatter through fog, not direct light. We chased it for hours assuming it was bloom, shadow bias, or light bleed. Confirmed by toggling lights one at a time: ceiling fluorescents, player headlight (omni AND spot branches), explosion light, switch lamp, FPS fill, attack-indicator pooled lights all needed the explicit 0.

**How to apply:** every new Light3D creation site MUST include `light.light_volumetric_fog_energy = 0.0` unless you specifically want lit volumetric fog (which we don't, at our iso camera angle). For pooled lights (e.g. `_acquire_light` in attack_indicator), every call site sets the property — `_release_light` doesn't reset it, so a pooled light can carry a stale non-zero value between uses.

You do NOT lose the room mist by doing this — FogVolumes keep their own `density` and `albedo`. What's lost is dynamic "light shafts" through fog, which barely read at top-down iso anyway.

See [[project_void_cover]] and [[project_light_bleed_fixes]].
