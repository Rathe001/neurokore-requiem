# Tech Stack

## Engine: Godot 4

Chosen for the project's specific shape: fixed-camera low-poly 3D ARPG, heavy dynamic lighting, horde-scale entities, Steam-first with future mobile and multiplayer.

**Why Godot:**

- Forward+ renderer gives modern PBR, SDFGI (real-time global illumination), volumetric fog, screen-space reflections, and decals — the feature set the neon-noir lighting design depends on
- Mobile renderer path exists in the same engine (for the eventual mobile port — treated as lower fidelity, not a separate art pipeline)
- Native mobile export (Android/iOS) and built-in high-level multiplayer API
- Free, open source, no licensing risk
- Active community and a fast-improving editor

**What was considered:**

| Engine | Why not |
|---|---|
| Unity | Heavier-weight, licensing trust damaged post-2023 |
| Unreal | Overkill for stylized low-poly; asset pipeline and engine complexity much higher; harder to ship to mobile at fidelity parity |
| Bevy (Rust) | Immature tooling and high friction without prior Rust experience |

---

## Language: GDScript

GDScript is the default. It's Python-like, integrates tightly with the editor, and is approachable for someone coming from JavaScript. No compile step, fast iteration.

**Performance escape hatch:** if profiling shows the entity simulation or rendering can't hit horde-density targets in GDScript, hot paths can be moved to C# or to GDExtension (C++ / Rust). This is a deliberate later optimization, not an upfront architectural choice.

---

## Renderer Targets

| Platform | Renderer | Notes |
|---|---|---|
| **PC (Steam)** | Forward+ | Full PBR, SDFGI, volumetrics, dynamic shadows. The identity look. |
| **PC (low-end)** | Forward+ with reduced effects | SDFGI off, fewer dynamic lights, lower shadow resolution. Still the same visual language. |
| **Mobile** | Mobile renderer | Baked lighting where possible, limited dynamic lights, no volumetrics. Same game, lower fidelity. |

**Performance pillars to hold:**
- Disciplined dynamic-light culling from the start — hordes + many dynamic lights is the danger combo
- Poly-budget per character kept low; surface detail from normal/roughness/emissive textures instead
- Object pooling for entities and VFX
- LOD on static world meshes where horde views are wide

---

## 3D Asset Pipeline

### Modeling & Animation

[Blender](https://www.blender.org/) is the long-term tool for modeling, UV work, rigging, and animation. Free and open source, strong Godot interop (glTF export), large learning resources.

### Textures

- PBR material authoring: substance-style workflow (base color, metallic, roughness, normal, emissive). Any tool producing glTF-compatible PBR maps is fine.
- 2D pixel tooling ([Aseprite](https://www.aseprite.org/)) still useful for UI icons, decals, emissive patterns, and hand-painted texture work.

### Early Prototype Bridge

Until custom art is ready, curated asset packs (Synty, Kenney, Quaternius, or paid low-poly cyberpunk packs) can fill in placeholder models. These are **temporary** — final art must be style-consistent and should not mix sources without deliberate unification.

---

## Versions

- **Godot:** latest stable 4.x
- **Blender:** latest LTS
- **Aseprite:** latest

Locked versions and reproducible-build details will be tracked once the project has a stable `project.godot` and CI pipeline.
