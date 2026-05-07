# Changelog

All notable changes to Neurokore: Requiem are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

The `[Unreleased]` section accumulates notes until the next deploy. Run
`tools/steam/prepare_build.py` (or `deploy.sh`/`deploy.bat`, which call it)
to roll the unreleased entries into a versioned section and bump the build.
The script will refuse to deploy if `[Unreleased]` is empty — patch notes
are mandatory.

## [Unreleased]

### Added

- Low-HP warning vignette: pulsing red rim activates below 30% HP, intensity ramps as HP drops further.
- Death screen glitch effect: slice displacement + channel drops behind the death screen UI.
- Impact burst VFX on bullet and laser hits — emissive flash + light pop at the target.
- Temporal Anti-Aliasing (TAA) option in display Settings.

### Changed

- Default anti-aliasing now MSAA 4× + TAA on + 16× anisotropic filtering. Kills the texture shimmer / crawl on movement that's been there since the project started.
- Enemy HP cut 50% globally — combat was excessively grindy at higher levels.
- Player now spawns at room center; starter chest tucked into the SW corner.
- HP regen pauses while aggro'd enemies are within 12m, not just for 5s after damage.
- Enemy chase→attack transitions get hysteresis on both ranged and melee paths — no more stutter at the range boundary, melee enemies hold position between swings instead of pushing into the player.
- Death screen overlay alpha and glitch intensity toned down for readability.
- Projectile and laser glow values rebalanced now that transient lights actually spawn at full brightness.

### Fixed

- Projectile and laser-impact lights now glow on spawn — `ProximityLighting` was pre-dimming all transient lights to zero.
- Glow / bloom no longer disappears after alt-tabbing back into the game.

### Docs

- Full `/docs/` rewrite: 32-file tree consolidated into 5 short docs (`world.md`, `classes.md`, `systems.md`, `conventions.md`, `narrative-bible.md`) plus a rewritten README and CLAUDE.md.

## [0.1.1] - 2026-05-06

### Fixed

- Resource loaders for perks, monster pack affixes, and named monsters
  now load in exported Steam builds. The previous `DirAccess` enumeration
  worked in the editor but returned empty in the export, silently dropping
  every talent perk grant, every rare-pack modifier, and every named-boss
  encounter. Talent allocations now correctly grant perks again.

## [0.1.0] - 2026-04-28

### Added

- Initial Steam playtest build.
