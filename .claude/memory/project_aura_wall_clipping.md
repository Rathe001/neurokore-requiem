---
name: Aura wall clipping pattern
description: Player-attached AOE visuals that should appear to "stop at walls" need to lean on shadow-casting OmniLight3D, not depth-tested transparent meshes
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
When a perk-driven visual (Doomsayer fog, future similar effects) needs to *appear* contained by walls in the iso prototype view, **don't rely on per-fragment depth testing of the visual mesh**. The iso camera looking down at angle can see floor past most 2m walls, so a flat disc (or even a sphere fragment behind the wall) often passes the depth test and renders through the wall.

**The reliable pattern:** pair a soft-edged mesh with a shadow-casting `OmniLight3D` on the player. The light's purple/colored wash on world surfaces is what actually communicates "the aura stops at the wall" — lights respect walls naturally via shadow casting. The mesh is just a soft body that adds atmosphere; it can bleed slightly through walls without being noticeable as long as it's mostly transparent.

**How to apply:**
- `OmniLight3D` with `shadow_enabled = true`, `shadow_blur` ~1.5, energy + range scaled with tier.
- Mesh is unshaded with low intensity, soft silhouette fade (`pow(1.0 - dot(NORMAL, VIEW), softness)`), 3D fbm noise for organic motion.
- For very tall sphere aura volumes that would poke above wall tops, **squash vertically into an ellipsoid** (Y scale ≈ 0.4-0.5× horizontal) and position centre at knee height (~0.5m). Keeps the visible body under typical 2m wall heights.
- Cubemap shadows from one omni light is real cost but acceptable for a single player-attached perk.

Reference: `game/scripts/prototype/doomsayer_aura.gd` + `game/shaders/doomsayer_fog.gdshader` (2026-05-03).
