# Neurokore: Requiem — Claude Context

This file is committed to the repo so context is available on any machine. It is intentionally brief — the docs are the source of truth.

## How to Work on This Project

- **Two sources of truth, with a clear split.**
  - `/docs` is the **design intent** layer: tone, vision, system shape, identity, design rules. Read it before answering design-shaped questions or proposing changes that affect the game's identity. It is intentionally lossy on numbers and current state.
  - **Code** is the **implementation** layer: the actual stats, formulas, field names, current behaviour. Read it before answering questions about what the game *currently does*.
  - When the two diverge, that's a flag to revisit one or the other — not automatically a bug. Sometimes the implementation has moved past the design, sometimes the design has moved past the implementation.
- **Don't update docs after every implementation tweak.** Docs change when *intent* changes (new class, new system, dropped feature). Tuning a magnitude or renaming a field is a code change only.
- **CLAUDE.md is a pointer, not a mirror.** Do not duplicate doc content here — just enough to orient and navigate.

## What This Is

**Neurokore: Requiem** is a Diablo 2-style fixed-camera low-poly 3D ARPG set in a cyberpunk world with a layered tone: gritty neon-noir baseline, campy 80s sci-fi surface, 80s body horror edge. Low-poly meshes + high-res PBR textures + realistic dynamic lighting — stylized, not photo-real.

Full world and tone detail: [`docs/world/tone.md`](docs/world/tone.md)

## Design Pillars

- Class identity is paramount — each class plays like a different game mode
- Class-specific resource systems (not shared across classes)
- Deep build diversity through loot-driven itemization
- Deliberate, weighted, build-dependent combat

Full combat design: [`docs/design/combat.md`](docs/design/combat.md) — includes targeting modes (cone, AoE, projectile, hitscan) and damage pipeline

## Classes (8 at launch)

Two **origin classes** (generalist) and six **specialized classes** (3 per origin):

| Origin | Specialized Classes |
|---|---|
| **Analog** | Survivalist, Count/Countess, Enculted |
| **Cyborg** | Forged, Automaton, Polymath |

Each class has one unique resource. See [`docs/classes/overview.md`](docs/classes/overview.md) for the full resource table.

Full class details:
- [`docs/classes/overview.md`](docs/classes/overview.md)
- [`docs/classes/cyborg.md`](docs/classes/cyborg.md)
- [`docs/classes/human.md`](docs/classes/human.md) *(Analog origin class)*
- [`docs/classes/spec-monsters.md`](docs/classes/spec-monsters.md)

## Visual Style & Level Design

- [`docs/world/art-style.md`](docs/world/art-style.md)
- [`docs/world/level-design.md`](docs/world/level-design.md)

## Starting Zones & Key Systems

- [`docs/design/starting-zones.md`](docs/design/starting-zones.md) — Earth Facility #723, rep system, class choice boss battle, origin class path
- [`docs/design/morality-system.md`](docs/design/morality-system.md) — on hold; rep alignments preserved, plane backburnered in favor of stat identity
- [`docs/design/skill-tree.md`](docs/design/skill-tree.md) — Fire/Alt Fire (weapon/offhand), 1H/2H weapons, tutorial progression, starting skills, hotkeys
- [`docs/design/item-architecture.md`](docs/design/item-architecture.md) — **item system source of truth**: type hierarchy, slots, weight system, prefix/suffix modifiers, rarity tiers, item generation pipeline, augment slot rules
- [`docs/design/equipment.md`](docs/design/equipment.md) — weapon types (energy, kinetic, elemental, melee, class-specific), offhands, armor, damage types
- [`docs/design/gear-augmentation.md`](docs/design/gear-augmentation.md) — schematics (workbench), field augments (class skills), ammo types, magazine/reload, augment slots
- [`docs/design/zones.md`](docs/design/zones.md) — zone design philosophy, Sub-Level Zero, zone registry
- [`docs/design/dialog-ui.md`](docs/design/dialog-ui.md) — animated portraits, class effects, UI philosophy
- [`docs/design/attribute-system.md`](docs/design/attribute-system.md) — 8 moral attributes, item stat budgets, class scaling, opposing stats, tier perks, visual metamorphosis, NPC identity reactions, HP/resource stat scaling
- [`docs/design/controls.md`](docs/design/controls.md) — WASD movement, mouse for attacks, controller as future work
- [`docs/world/lighting.md`](docs/world/lighting.md) — darkness as default, equippable light sources, zone lighting tiers
- [`docs/design/ui-style-guide.md`](docs/design/ui-style-guide.md) — type scale, tag components, color groups, all 9 class palettes, i18n and theming conventions

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

Early prototype. [`docs/status.md`](docs/status.md) lists the **open design questions** (not implementation status — code is authoritative for that). When you need to know "what currently works," read the code under `game/scripts/` or check `git log`.
