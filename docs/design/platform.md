# Platform & Performance

## Principles

Performance is a first-class design consideration — not an afterthought. Architecture, rendering, and systems decisions should always account for target hardware. A game that runs poorly on average hardware is a failed game regardless of design quality.

The goal is a smooth, responsive experience on modest machines. This game does not need to be graphically demanding to achieve its visual goals.

---

## Target Platforms

| Platform | Status | Notes |
|---|---|---|
| **Steam (PC)** | Initial release | Single player only at launch |
| **Android / iOS** | Future consideration | Keep mobile architecture in mind — do not design against it |
| **Multiplayer** | Future consideration | Design with it in mind from the start — implement later |

---

## Performance Targets

- **Target hardware:** Average spec consumer PC. Integrated graphics, 8GB RAM, mid-range CPU should be sufficient for a smooth experience.
- Horde-scale enemy counts (end-game Vampire Survivors density) must perform within this budget.
- Real-time dynamic lighting must be efficient — the visual goal does not require expensive rendering.
- 3D assets should be kept at appropriate polygon counts and texture resolutions — high fidelity without being wasteful.

---

## Architecture Considerations

### Multiplayer-Ready, Single Player First

The initial release is single player only. However, architecture decisions should not foreclose multiplayer — avoid designs that assume a single local player at a fundamental level. When in doubt, prefer approaches that would extend to networked play without a rewrite.

### Mobile Awareness

An Android/iOS port is not confirmed but is a realistic future goal. Keep in mind:

- Avoid PC-only input assumptions baked into core systems
- Prefer lighter rendering approaches where a choice exists
- Memory and draw call budgets that work on mobile will work everywhere

### Entity Management

End-game horde density is a known requirement. Entity and AI systems must be designed to handle large numbers efficiently from the start — this is not something that can be optimized in later without structural changes.

- Spatial partitioning, object pooling, and batched updates should be considered from the architecture phase
- Enemy AI complexity should scale down gracefully under load

### Rendering

- Real-time 3D lighting via the Forward Plus renderer (desktop), with Mobile/Compatibility as the fallback for future mobile targets
- Modular 3D levels enable frustum culling and chunk-based rendering
- Occlusion transparency on geometry should be handled at the shader level, not by spawning/despawning geometry

---

## Summary

| Consideration | Decision |
|---|---|
| Initial release | Steam, single player |
| Future platforms | Android/iOS, multiplayer |
| Performance bar | Average spec PC, mobile-aware |
| Horde density | Must be solved at the architecture level |
| Multiplayer | Design for it, build it later |
