# Neurokore: Requiem

A Diablo 2-style ARPG built in Godot 4. Fixed-camera 3D, low-poly meshes with PBR textures and realistic dynamic lighting. Cyberpunk neon-noir baseline, 80s sci-fi surface, body-horror edge.

## Status

Early prototype. **Steam playtest is live** (v0.1.1, 2026-05-06). The code under `game/` is the source of truth for what currently works — `git log` and the scripts there are more accurate than any status writeup.

## Cloning

Character meshes (`*.fbx`) are stored in [Git LFS](https://git-lfs.github.com/). Install once per machine before cloning, otherwise FBXs will appear as ~1KB pointer files and Godot will fail to import them:

```bash
# macOS
brew install git-lfs && git lfs install

# Windows (winget)
winget install GitHub.GitLFS && git lfs install

# Linux (Debian/Ubuntu)
sudo apt install git-lfs && git lfs install
```

Then a normal `git clone` will pull LFS-backed files transparently. On an existing clone, `git lfs pull` fetches them after-the-fact.

## Design pillars

- **Class identity is paramount** — eight classes (two origins + six specializations), each plays like a different game mode.
- **Class-specific resources** — not shared across classes.
- **Deep build diversity** — talents are the build spine, gear is the build amplifier.
- **Deliberate, weighted, build-dependent combat** — D2-style feel, not floaty.

## Repository layout

| Path | What lives there |
|---|---|
| `game/` | The Godot project. Scripts under `game/scripts/`, scenes under `game/scenes/`, content resources under `game/resources/`. Code is authoritative for current behavior. |
| `docs/` | Design intent — the "why" behind systems, the world, and the classes. Intentionally short. |
| `tools/steam/` | Steam deploy pipeline (`prepare_build.py`, `deploy.sh`/`deploy.bat`). See `tools/steam/DEPLOY.md` for per-machine setup. |
| `CHANGELOG.md` | Per-release patch notes. The deploy script refuses to ship if `[Unreleased]` is empty. |
| `CLAUDE.md` | Pointer file for AI coding assistants — orients Claude to the codebase. |

## Docs

- [`docs/world.md`](docs/world.md) — tone, faction dynamic, art direction, lighting, zones
- [`docs/classes.md`](docs/classes.md) — the eight classes, resources, talent tiers, signature perks
- [`docs/systems.md`](docs/systems.md) — combat, itemization, item architecture, ilvl scaling, equipment
- [`docs/conventions.md`](docs/conventions.md) — tech stack, coding conventions, inspirations
- [`docs/narrative-bible.md`](docs/narrative-bible.md) — Earth Facility #723, the reps, the Confrontation. Design intent — not yet implemented.

## License

MIT — see [LICENSE](LICENSE).
