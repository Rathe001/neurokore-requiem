# Tech Stack

## Engine: Godot 4

Chosen for the project's specific shape: isometric pixel-art ARPG, 2D dynamic lighting with normal maps, horde-scale entities, Steam-first with future mobile and multiplayer.

**Why Godot:**

- 2D pipeline is first-class — not bolted on top of a 3D engine
- Light2D + normal-mapped sprites cover the lighting requirements out of the box
- Native mobile export (Android/iOS) and built-in high-level multiplayer API
- Free, open source, no licensing risk
- Active community and a fast-improving editor

**What was considered:**

| Engine | Why not |
|---|---|
| Unity | Heavier-weight, weaker native 2D story, licensing trust damaged post-2023 |
| Bevy (Rust) | Best peak performance, but immature tooling and high friction without prior Rust experience |
| MonoGame / FNA | Too low level — would mean building an engine before building the game |

---

## Language: GDScript

GDScript is the default. It's Python-like, integrates tightly with the editor, and is approachable for someone coming from JavaScript. No compile step, fast iteration.

**Performance escape hatch:** if profiling shows the entity simulation can't hit horde-density targets in GDScript, hot paths can be moved to C# or to GDExtension (C++ / Rust). This is a deliberate later optimization, not an upfront architectural choice.

---

## Pixel Art Tooling

[Aseprite](https://www.aseprite.org/) — industry standard for pixel art and sprite animation. Used for any in-house sprite work and for editing commissioned art.

---

## Versions

- **Godot:** latest stable 4.x
- **Aseprite:** latest

Locked versions and reproducible-build details will be tracked once the project has a `project.godot` and CI pipeline.
