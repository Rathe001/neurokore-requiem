# Neurokore: Requiem — Claude Context

This file is committed to the repo so context is available on any machine. It is intentionally brief — the docs are the source of truth.

## How to Work on This Project

- **Docs are the source of truth.** All game design detail lives in `/docs`. Read the relevant doc before answering questions or making changes.
- **Keep this file in sync with the docs.** When a docs file changes in a way that affects the high-level summary below (new class, renamed spec, changed mechanic), update this file too. A hook will remind you automatically.
- **CLAUDE.md is a pointer, not a mirror.** Do not duplicate doc content here — just enough to orient and navigate.

## What This Is

**Neurokore: Requiem** is a Diablo 2-style isometric pixel art ARPG set in a cyberpunk world with a layered tone: gritty neon-noir baseline, campy 80s sci-fi surface, 80s body horror edge.

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

- [`docs/design/starting-zones.md`](docs/design/starting-zones.md) — Earth Facility #723, rep system, spec choice boss battle, base class path, morality system

## Platform & Performance

**Always keep these in mind when making architecture or design decisions:**

- **Initial release:** Steam, single player only
- **Future targets:** Android/iOS port, multiplayer — do not design against these
- **Performance bar:** average spec PC (integrated graphics, 8GB RAM). Mobile-aware.
- **Horde density** (end-game Vampire Survivors scale) must be solved at the architecture level — entity management, spatial partitioning, object pooling
- **Multiplayer:** design for it from the start, implement it later

Full details: [`docs/design/platform.md`](docs/design/platform.md)

## Project Status

- [`docs/status.md`](docs/status.md)
