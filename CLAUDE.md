# Neurokore: Requiem — Claude Context

This file is committed to the repo so context is available on any machine. It is intentionally brief — the docs are the source of truth.

## How to Work on This Project

- **Docs are the source of truth.** All game design detail lives in `/docs`. Read the relevant doc before answering questions or making changes.
- **Keep this file in sync with the docs.** When a docs file changes in a way that affects the high-level summary below (new class, renamed spec, changed mechanic), update this file too. A hook will remind you automatically.
- **CLAUDE.md is a pointer, not a mirror.** Do not duplicate doc content here — just enough to orient and navigate.

## What This Is

**Neurokore: Requiem** is a Diablo 2-style fixed-camera low-poly 3D ARPG set in a cyberpunk world with a layered tone: gritty neon-noir baseline, campy 80s sci-fi surface, 80s body horror edge. Low-poly meshes + high-res PBR textures + realistic dynamic lighting — stylized, not photo-real.

Full world and tone detail: [`docs/world/tone.md`](docs/world/tone.md)

## Design Pillars

- Class identity is paramount — each class plays like a different game mode
- Class-specific resource systems (not shared across classes)
- Deep build diversity through loot-driven itemization
- Deliberate, weighted, build-dependent combat

Full combat design: [`docs/design/combat.md`](docs/design/combat.md)

## Classes (2 at launch)

| Class | Specs | Resource Systems |
|---|---|---|
| **Cyborg** | Forged, Automaton, Polymath | Power Grid / Bandwidth / Memory+CPU |
| **Human** | Survivalist, Gentleman-Lady, Enculted | Adrenaline / Composure / Sanity |

Full class details:
- [`docs/classes/overview.md`](docs/classes/overview.md)
- [`docs/classes/cyborg.md`](docs/classes/cyborg.md)
- [`docs/classes/human.md`](docs/classes/human.md)
- [`docs/classes/spec-monsters.md`](docs/classes/spec-monsters.md)

## Visual Style & Level Design

- [`docs/world/art-style.md`](docs/world/art-style.md)
- [`docs/world/level-design.md`](docs/world/level-design.md)

## Starting Zones & Key Systems

- [`docs/design/starting-zones.md`](docs/design/starting-zones.md) — Earth Facility #723, rep system, spec choice boss battle, base class path
- [`docs/design/morality-system.md`](docs/design/morality-system.md) — 2D morality plane, rep alignments, what it affects
- [`docs/design/skill-tree.md`](docs/design/skill-tree.md) — basic attacks, tutorial progression, starting skills, hotkeys
- [`docs/design/zones.md`](docs/design/zones.md) — zone design philosophy, Sub-Level Zero, zone registry
- [`docs/design/dialog-ui.md`](docs/design/dialog-ui.md) — animated portraits, spec effects, UI philosophy
- [`docs/design/controls.md`](docs/design/controls.md) — WASD movement, mouse for attacks, controller as future work
- [`docs/world/lighting.md`](docs/world/lighting.md) — darkness as default, equippable light sources, zone lighting tiers

## Platform & Performance

**Always keep these in mind when making architecture or design decisions:**

- **Initial release:** Steam, single player only
- **Future targets:** Android/iOS port, multiplayer — do not design against these
- **Performance bar:** average spec PC (integrated graphics, 8GB RAM). Mobile-aware.
- **Horde density** (end-game Vampire Survivors scale) must be solved at the architecture level — entity management, spatial partitioning, object pooling
- **Multiplayer:** design for it from the start, implement it later

Full details: [`docs/design/platform.md`](docs/design/platform.md)

## Tech Stack

- **Engine:** Godot 4 (Forward+ renderer on PC; mobile renderer path for the eventual mobile port)
- **Language:** GDScript (with C# / GDExtension as a performance escape hatch for hot paths)
- **3D modeling & animation:** Blender
- **2D tooling:** Aseprite (UI icons, decals, emissive texture work)

Full details: [`docs/design/tech-stack.md`](docs/design/tech-stack.md)

Coding conventions: [`docs/design/coding-conventions.md`](docs/design/coding-conventions.md)

## Project Status

- [`docs/status.md`](docs/status.md)
