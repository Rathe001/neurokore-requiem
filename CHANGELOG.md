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

### Fixed

- Resource loaders for perks, monster pack affixes, and named monsters
  now load in exported Steam builds. The previous `DirAccess` enumeration
  worked in the editor but returned empty in the export, silently dropping
  every talent perk grant, every rare-pack modifier, and every named-boss
  encounter. Talent allocations now correctly grant perks again.

## [0.1.0] - 2026-04-28

### Added

- Initial Steam playtest build.
