---
name: crater-vfx
description: "Hammer / explosion impact crater pipeline — refraction + center darken + NORMAL_MAP_DEPTH + scorch tint, plus debris + dust spawn"
metadata:
  type: project
---

The hammer-crater (also used for explosion craters) is layered visual VFX that took several iterations to land. Key design choices, recorded so we don't re-derive them:

**Architecture: PBR mesh + custom shader (not Decal3D).** The crater is the Blenderkit "crater-dry-hills" sculpted glb, but the source asset's orange albedo is dropped — we sample `SCREEN_TEXTURE` instead so the floor's own palette comes through. Decal3D was considered and rejected because we need a ShaderMaterial on the surface, which Decal3D doesn't support.

**Shader is `res://scripts/prototype/hammer_crater.gdshader`. Three effects stack:**

1. **Screen-space refraction.** SCREEN_UV is offset by the normal map's decoded XY (`nrm.xy * 2 - 1`) times `distort_strength` (currently 0.08). Floor tiles visibly bend through the rim/depression slopes. Sells real depth far better than lighting shading alone.

2. **Radial center darkening.** ALBEDO is darkened up to `center_darken` (0.55) at r=0, falling to 1.0 by `vignette_start`. Pit-shadow look that reinforces depth.

3. **Exaggerated normals.** `NORMAL_MAP_DEPTH = normal_strength` (3.0) — pushes the crater's sculpted bump so it casts stronger highlights/shadows from world lighting. Critical for readability from the iso camera.

**Required render_mode:** `depth_draw_never` is mandatory for SCREEN_TEXTURE sampling to capture the floor pixel beneath. Without it, the crater clips itself out of the screen-texture pass and you sample the void below the floor.

**Required varying:** `v_local_pos` carries VERTEX from vertex() to fragment(), because Godot's built-in `VERTEX` in `fragment()` is in VIEW space, not model space. See [[godot4-shader-gotchas]] #10.

**fade_radius is per-mesh, not per-instance.** Walking the AABB through wrapper Node3D transforms inside the glb gives the right mesh-local extent. Hardcoded constants drifted on re-import.

**Three things that DIDN'T work and shouldn't be tried again:**

- Bright emissive rim halo: at high intensity bloom amplified it into a separate orange ring that looked identical to `spawn_hammer_impact`'s shockwave, making the impact read as "duplicate VFX" not "crater + shockwave".
- Source-asset orange albedo: read as a sticker dropped on the floor, never blended.
- Dark scorch on dark floor: invisible. Warm-toned scorch (0.75, 0.45, 0.25) gives color contrast against the cool cyberpunk palette.

**Spawn layering on explosions** (plasma RMB, grenades, RPG, anything via `spawn_explosion`):
- spawn_hammer_crater — the scar
- spawn_hammer_dust_ring — expanding dust cloud (reused from hammer LMB)
- spawn_explosion_debris — 8 tumbling DebrisShard chunks, scaled to blast radius

All three are gated behind `blast_radius >= 1.0` to skip proximity fizzles. world_pos.y is projected to 0.0 so airborne detonations still scar the ground below.

**MP coverage is free** for everything inside `spawn_explosion` and `spawn_hammer_crater` because `CombatVisuals.spawn_explosion`'s RPC already replays the call on every peer. No new sync code needed for new spawn additions in this chain.

**Combo finisher pattern:** the 2H hammer LMB's step-2 finisher spawns a player-centered AoE crater sized to `eff_range`, mirroring the RMB AoE pattern — NOT the front-impact crater that build-up swings use. Same in PlayerCombat's `_resolve_cone` for `is_hammer_finisher`.

Related: [[godot4-shader-gotchas]], [[vfx-warmup]], [[melee-impact-ratio]].
