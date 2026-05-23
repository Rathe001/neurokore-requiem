---
name: vfx-warmup
description: "Shader pre-compile pass during loading-screen window — fixes first-LMB/RMB lag from Godot 4 lazy shader compile"
metadata:
  type: project
---

`VfxWarmup` (game/scripts/prototype/vfx_warmup.gd) compiles combat-relevant spatial shaders at level load by parking a tiny QuadMesh + ShaderMaterial below the map for two process_frames. Without it the first swing / first shot of a session stalls a frame on Godot 4's lazy shader compile and feels like input lag.

Called from `PrototypeRoot._ready()` right before the loading-screen `hide_loading` call, so the compile cost lands during the cover, not in gameplay.

**How to apply / extend:** Adding a new combat shader → append its path to `VfxWarmup._COMBAT_SHADERS`. UI-overlay shaders (canvas_item) and always-on structural shaders (walls/floors/doors) compile naturally during scene boot and don't need to be in the list. If a hitch shows up on a new VFX, suspect that the new shader isn't in the warmup list.

Related: audio is warmed at autoload init via `WeaponSounds._ensure_loaded()` synchronously in its `_ready()`. Full-scene VFX (projectile, explosion) are intentionally NOT warmed by instantiation because their `_ready()` runs tweens / audio / timers that aren't safe to invoke off-stage — if those hitch later, prefer extracting their materials and warming those instead.

See also [[godot4-shader-gotchas]] for the underlying compile-time silent-failure modes that make shader testing tricky to begin with.
