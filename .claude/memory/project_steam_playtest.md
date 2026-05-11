---
name: Steam Playtest live
description: Steam Playtest is live and accepting builds; deploy infrastructure exists end-to-end (CHANGELOG-driven version bumps + auto VDF desc + interactive SteamCMD). Use this for any Steam-deploy questions or when reasoning about playtest stability.
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
**Status (2026-05-10):** Playtest is **live** with **v0.2.0** shipped (BuildID 23169929). Players can request access via the base game's Steam page; auto-grant is configurable in Steamworks playtest settings. Prior versions: v0.1.0 (2026-04-28 initial), v0.1.1 (2026-05-06 export-resource-loader fix), v0.1.2 (2026-05-06 AA + balance), v0.1.3 (2026-05-08 ragdolls + early-game tuning), v0.2.0 (2026-05-10 mid-range weapons + signature quirks + melee combo + coop visibility).

**Steam IDs:**
- Parent store app: **NeuroKore: Requiem** — App ID `4689190`
- Playtest sub-app: **NeuroKore: Requiem Playtest** — App ID `4689320` (builds upload here)
- Depot ID for playtest: `4689321`
- Steam username: `darkapocrypha`

**Deploy infrastructure** (committed in `tools/steam/`):
- `prepare_build.py` — bumps `BuildInfo.VERSION` (semver, `--bump patch|minor|major`), updates `BUILD_DATE` to today, rotates `## [Unreleased]` in `CHANGELOG.md` to a versioned section, regenerates VDF `desc` as `v<version> · <git-sha> · <first changelog bullet>`. Refuses to deploy if `[Unreleased]` is empty.
- `deploy.sh` / `deploy.bat` — orchestrate prep + Godot export + SteamCMD upload in one command. Defaults to patch bump.
- `DEPLOY.md` — per-machine first-time setup walkthrough + per-deploy ritual.

**Per-deploy ritual:**
1. Edit `CHANGELOG.md` `## [Unreleased]` with bullet points
2. Run `deploy.bat` (Windows) or `./deploy.sh` (mac/Linux) from `tools/steam/`
3. Set live in Steamworks: App 4689320 → SteamPipe → Builds → default branch
4. `git commit -am "Release vX.Y.Z" ; git tag vX.Y.Z ; git push --follow-tags`

**Why:** Friends-mode playtest while continuing development. Playtest model is free past the $100 Direct fee, no release-date commitment, gated access.

**How to apply:**
- Anything shipping to playtesters needs polish even at small scope.
- Watch for export-vs-editor divergence — see [Resource loader gotcha](project_resource_loader_gotcha.md). DirAccess directory enumeration is the canonical example; assume any "works in editor, broken on Steam" report is a similar class of issue.
- Patch notes are the forcing function — nothing ships without an Unreleased section in the changelog.
