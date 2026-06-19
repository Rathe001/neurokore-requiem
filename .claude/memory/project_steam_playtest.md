---
name: Steam Playtest live
description: Steam Playtest is live and accepting builds; deploy infrastructure exists end-to-end (CHANGELOG-driven version bumps + auto VDF desc + interactive SteamCMD). Use this for any Steam-deploy questions or when reasoning about playtest stability.
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
**Status (2026-06-19):** Playtest is **live** with **v0.5.0** shipped and set live on the default branch (BuildID 23824650). Players can request access via the base game's Steam page; auto-grant is configurable in Steamworks playtest settings. Prior versions: v0.1.0 (2026-04-28 initial), v0.1.1 (2026-05-06 export-resource-loader fix), v0.1.2 (2026-05-06 AA + balance), v0.1.3 (2026-05-08 ragdolls + early-game tuning), v0.2.0 (2026-05-10 mid-range weapons + signature quirks + melee combo + coop visibility), v0.2.1 (2026-05-12 audio overhaul + item icons + camera shake/push + enemy module extraction), v0.3.0 (2026-05-13 procgen dungeons + cover system + destructibles + health potions + armor DR + weapon signatures + unarmed + density scaling + big tuning pass), v0.4.0 (2026-05-15 visual meter tooltips + Recovery rename/retune + flipbook explosions + MissionState panel + sustain system + bigger procgen with asylum clutter + PILLAR layer redesign + mid-air control + volumetric fog + freight elevator + combat-feel batch + universal rarity rolling + AoE-matches-visual fix + audit cleanup), v0.4.1 (2026-05-20 Mixamo character meshes for player+enemies with gender-driven swap + MP per-peer gender plumbing + ranged firing pose with stationary/strafe variants + Jog Forward/Crouched Walking/14 death clips + sci-fi monitor switch model + NG+ pill in HUD and continue panel + blood spray nerf + SSR steps lowered + boot splash resize + Jolt non-uniform-scale spam fix via parent-chain normalize + null-material backfill + player & enemy MP-client death anim fix), v0.5.0 (2026-06-19 — THE OVERHAUL: full character/weapon model swap to custom Meshy low-poly ~16× lower tris + two enemy archetypes + visible weapons in hand (player+enemy) + animation overhaul (per-weapon stances, fire-rate-synced aim pose, authored strafe clips, impact-frame melee, death anims on non-explosive kills) + shell-casing eject + dropped-weapon physics + persistent LiquidLayer blood (merging pools, wall drips, footprints) + blood-as-traction-hazard + impact craters + neon interactable outlines + floor clutter decals + fake-ortho camera + loading-screen progress bar + Display settings (vsync/fps/GI) + behavior mods on armor + tiered affix ladders + MAJOR perf pass (streamed level build, per-frame reveal budgets, ragdoll queue, distant/idle enemy throttle, SDFGI off by default, laser-hitch material-RID-sync fix) + asset dedupe/1024 caps + switch/elevator collision fixes; BuildID 23824650, ~660MB).

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
5. Player-facing patch notes: paste Steam BBCode into the "Set Build Live" form. Keep a paste-ready copy at `tools/steam/steam-patch-notes-vX.Y.Z.md` (the terminal mangles line breaks on copy).

**Deploy gotchas (learned shipping v0.5.0, when driving the steps by hand instead of via deploy.bat):**
- **SteamCMD resolves the `+run_app_build` VDF argument relative to steamcmd's OWN install dir, not the shell CWD** — pass an ABSOLUTE path to the `.vdf`. But the VDF's `contentroot`/`buildoutput` are relative, so CWD must STILL be `tools/steam`. Symptom of getting it wrong: `ERROR! App build file does not exist`.
- `git push --follow-tags` only pushes ANNOTATED tags; `git tag vX.Y.Z` makes a lightweight tag that needs an explicit `git push origin vX.Y.Z`.
- Steam Guard 2FA: cached credentials persist per machine, so non-interactive re-deploys (e.g. from an agent shell) work without a prompt. A machine's FIRST deploy still needs an interactive `steamcmd +login`.
- Build uploads with `setlive=""` (draft) — going live is a manual Steamworks web step. The build sits safe as a draft until you click Set Build Live, which is the natural pre-live playtest window. For v0.5.0 the [[godot4-runtime-gotchas]]-style Godot-shim trap was dodged by pointing `GODOT` straight at `Godot_v4.6.2-stable_win64_console.exe` instead of the `godot.cmd` shim.
- A minor/major version warrants `deploy.bat minor` / `deploy.bat major` (or `--bump minor`); the default is `patch`. v0.5.0 was a `--bump minor`.

**Why:** Friends-mode playtest while continuing development. Playtest model is free past the $100 Direct fee, no release-date commitment, gated access.

**How to apply:**
- Anything shipping to playtesters needs polish even at small scope.
- Watch for export-vs-editor divergence — see [Resource loader gotcha](project_resource_loader_gotcha.md). DirAccess directory enumeration is the canonical example; assume any "works in editor, broken on Steam" report is a similar class of issue.
- Patch notes are the forcing function — nothing ships without an Unreleased section in the changelog.
