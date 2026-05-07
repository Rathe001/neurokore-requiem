# Neurokore: Requiem — Claude Context

This file is committed to the repo so context is available on any machine. It is intentionally brief — the docs are the source of truth.

## How to Work on This Project

- **Two sources of truth, with a clear split.**
  - `/docs` is the **design intent** layer: tone, vision, system shape, identity, design rules. Read it before answering design-shaped questions or proposing changes that affect the game's identity. It is intentionally lossy on numbers and current state.
  - **Code** under `game/` is the **implementation** layer: actual stats, formulas, field names, current behaviour. Read it before answering questions about what the game *currently does*.
  - When the two diverge, that's a flag to revisit one or the other — not automatically a bug. Sometimes the implementation has moved past the design, sometimes the design has moved past the implementation.
- **Don't update docs after every implementation tweak.** Docs change when *intent* changes (new class, new system, dropped feature). Tuning a magnitude or renaming a field is a code change only.
- **CLAUDE.md is a pointer, not a mirror.** Do not duplicate doc content here — just enough to orient and navigate.

## What This Is

**Neurokore: Requiem** is a Diablo 2-style fixed-camera low-poly 3D ARPG in a cyberpunk world with a layered tone: gritty neon-noir baseline, campy 80s sci-fi surface, 80s body horror edge. Low-poly meshes + high-res PBR textures + realistic dynamic lighting — stylized, not photo-real.

## Design Pillars

- Class identity is paramount — each class plays like a different game mode
- Class-specific resource systems (not shared across classes)
- Deep build diversity — talents are the build spine, gear is the build amplifier
- Deliberate, weighted, build-dependent combat

## Docs

The design intent layer lives in five short docs. Code is authoritative for current numbers — these docs explain the *why*.

- [`docs/world.md`](docs/world.md) — tone, faction dynamic, art direction, lighting policy, zones thesis
- [`docs/classes.md`](docs/classes.md) — the eight classes (2 origins + 6 specs), resources, talent tier shape, signature perks, class-tuned monster variants
- [`docs/systems.md`](docs/systems.md) — combat targeting modes + damage pipeline, itemization design intent, gear slots, traction breakpoints, item-level effectiveness curve, equipment taxonomy
- [`docs/conventions.md`](docs/conventions.md) — tech stack, performance pillars, coding conventions, infrastructure (SpatialGrid / EntityPool), inspirations
- [`docs/narrative-bible.md`](docs/narrative-bible.md) — Earth Facility #723, the reps, the Confrontation, Sub-Level Zero, mystery rep, rep alignments. **Aspirational — none of it is implemented yet.** Read for tone; don't read as current state.
- [`docs/multiplayer.md`](docs/multiplayer.md) — Steam P2P coop plan (host-authoritative, 4-player cap, drop-in, instanced loot with manual-drop sharing). **Planned, not yet implemented.** Lobby UI scaffolding shipped; networking unbuilt.

## Platform & Performance

Always keep these in mind when making architecture or design decisions:

- **Initial release:** Steam, single player only
- **Future targets:** Android/iOS port, multiplayer — do not design against these
- **Performance bar:** average spec PC (integrated graphics, 8GB RAM). Mobile-aware.
- **Horde density** (end-game Vampire-Survivors scale) must be solved at the architecture level — entity management, spatial partitioning (`SpatialGrid` autoload), object pooling (`EntityPool` autoload)
- **Multiplayer:** design for it from the start, implement it later

## Project Status

Early prototype. **Steam playtest is live** (v0.1.1, 2026-05-06). The code under `game/scripts/` and `git log` are authoritative for what currently works — more accurate than any status writeup could stay.

Open design areas not derivable from code: origin-class perk ladders (Analog/Cyborg generalists), Polymath/Enculted resource models (both currently TBD), behavior-mod pools per slot (~4 each), end-game loop, death/failure model, economy and crafting, power-budget tuning at scale.
