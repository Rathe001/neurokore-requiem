---
name: Level builder shader-overlap trap
description: Why corridor and room walls/floors must share a shader — geometric overlap is built into the system
type: project
originSessionId: 3ccada6b-b909-4f94-a64f-38aa2efcfd7e
---
LevelBuilder builds corridor walls (BoxMesh) and corridor floors (PlaneMesh) with deliberate geometric overlap into adjacent rooms — `_FLOOR_OVERLAP = 0.2` extends piece floors 0.2m under walls from both sides, and corridor wall BoxMeshes extend `(thick - _SEAM)` past corridor ends to abut the room's procedural wall mesh. This is intentional: it hides seams and makes the joint visually continuous.

**Why:** When both surfaces run the same shader, overlapping coplanar pixels write the same color and z-fighting is invisible. As soon as they run different shaders (e.g., a "corridor uses alt shader" variant), the contested pixels alternate per frame and the seams produce visible cross-hatch flickering — confirmed 2026-04-28 with the tech_wall_riveted / tech_floor_grate experiment which was reverted.

**How to apply:** Don't wire `wall_shader_alt` / `floor_shader_alt` in a LevelTheme to differentiate corridors from rooms unless the geometric overlap is fixed first (e.g., make corridor floors edge-aligned with no overlap, and have corridor walls stop at the room wall outer face instead of extending into it). The unused alt fields and the variant shaders (`tech_wall_riveted.gdshader`, `tech_floor_grate.gdshader`) are still on disk for future use. Per-piece visual variety is safe via parameter tweaks on the same shader (panel_variation, accent colors), or via dedicated meshes that don't share planes with neighbours (tech_door is the model — its slab doesn't overlap anything else).

**Update 2026-05-03:** When applying a Y-bias to win z-fights between coplanar surfaces (corridor floor vs room floor, pillar top vs corridor floor), bias ONLY the visual mesh's local position — leave the StaticBody3D / CollisionShape3D unbiased. Otherwise enemies and the player snag at the seam, sinking visibly into the floor. See `floor_builder.gd::CORRIDOR_FLOOR_MESH_Y_BIAS` and `pit_builder.gd::PILLAR_TOP_Y_BIAS` for the right pattern: `mesh_inst.position.y = bias`, body+collision at the nominal floor height (y=0).
