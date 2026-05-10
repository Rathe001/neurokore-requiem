# Steam Deploy Guide

## First-Time Setup (per machine)

Walk through this once on each machine you plan to deploy from. Subsequent deploys only need the [per-deploy ritual](#before-you-deploy-write-patch-notes).

### Windows

The whole setup lives under `C:\Users\<you>\Tools\` — keeps it portable and out of `Program Files`.

1. **Install Python 3** if you don't have it:
   - From https://www.python.org/downloads/, tick "Add python.exe to PATH" during install.
   - If you already have Microsoft's Python Install Manager (`py.exe`) but `python` doesn't run, do `py install default` once.
   - Verify: `python --version`

2. **Install Godot 4**:
   - Download `Godot_v4.X.Y-stable_win64.exe` from https://godotengine.org/download/windows
   - Place it in `C:\Users\<you>\Tools\Godot\` (or wherever you want — adjust paths below).
   - Open Godot once, then **Editor > Manage Export Templates** and download the matching templates.
   - Create a `godot.cmd` shim in the same folder so `godot` works on PATH:
     ```bat
     @echo off
     "%~dp0Godot_v4.X.Y-stable_win64_console.exe" %*
     ```
     (Use the `_console` variant — it forwards stdout properly for headless export. Update the binary name when Godot updates.)

3. **Install SteamCMD**:
   ```powershell
   $dest = "C:\Users\$env:USERNAME\Tools\steamcmd"
   New-Item -ItemType Directory -Path $dest -Force | Out-Null
   Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile "$env:TEMP\steamcmd.zip" -UseBasicParsing
   Expand-Archive -Path "$env:TEMP\steamcmd.zip" -DestinationPath $dest -Force
   & "$dest\steamcmd.exe" +quit  # bootstraps the rest of SteamCMD's payload (~45MB)
   ```

> **Heads-up on `setx` / `[Environment]::SetEnvironmentVariable("User")`**: both write to the persistent user environment but only affect shells opened **after** the write. Any terminal that was already open keeps its old env. After the step below — and after the `setx STEAM_USER ...` step further down — open a fresh terminal before running anything else, or the deploy script will look for `godot` / `steamcmd` / `STEAM_USER` and not find them.

4. **Add both tools to your User PATH**:
   ```powershell
   $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
   $entries = @("C:\Users\$env:USERNAME\Tools\Godot", "C:\Users\$env:USERNAME\Tools\steamcmd")
   $current = $userPath -split ';' | Where-Object { $_ -ne "" }
   foreach ($e in $entries) {
       if ($current -notcontains $e) { $current += $e }
   }
   [Environment]::SetEnvironmentVariable("PATH", ($current -join ';'), "User")
   ```
   **Open a fresh terminal** to pick up the PATH change.

5. **(Optional) Persist your Steam username** so you don't have to set it each deploy:
   ```bat
   setx STEAM_USER your_actual_steam_username
   ```
   Again, fresh terminal required.

6. **Cache your Steam credentials** — run SteamCMD once interactively so it asks for your password and Steam Guard 2FA code, then caches them:
   ```bat
   steamcmd +login your_actual_steam_username +quit
   ```
   After this, future deploys skip the prompts.

### macOS

```bash
brew install python godot
brew install steamcmd        # Apple Silicon also needs: softwareupdate --install-rosetta
```

Then run `steamcmd +login your_username +quit` once to cache credentials.

The deploy script reads `GODOT`, `STEAMCMD`, `STEAM_USER` env vars; set them in your shell profile if the defaults don't match (`GODOT=/Applications/Godot.app/Contents/MacOS/Godot` is the typical Mac override).

### Linux

`apt install python3 godot steamcmd` (or distro equivalents). Cache credentials the same way.

---

## Prerequisites

- **Godot 4** on PATH (or set `GODOT` env var / edit the script)
- **Python 3** on PATH. Used by `prepare_build.py` to bump version + roll the changelog. Standard library only — no `pip install` step.
  - macOS: usually preinstalled; otherwise `brew install python`.
  - Linux: `apt install python3` / your distro's equivalent.
  - Windows: install from https://www.python.org/downloads/ and tick "Add python.exe to PATH" during setup. If you have the Microsoft Python Install Manager (`py.exe`) but no actual interpreter, run `py install default` once. Verify with `python --version`.
- **SteamCMD** installed and on PATH (or set `STEAMCMD` env var / edit the script)
  - macOS: `brew install steamcmd` (Apple Silicon also needs `softwareupdate --install-rosetta`)
  - Windows: https://developer.valvesoftware.com/wiki/SteamCMD#Downloading_SteamCMD
- **Windows export template** installed in Godot (Editor > Manage Export Templates)
- Steam account with Steamworks publisher permissions

## Before You Deploy: Write Patch Notes

Open [`CHANGELOG.md`](../../CHANGELOG.md) at the repo root and add bullet points to the `## [Unreleased]` section under the appropriate `### Added` / `### Changed` / `### Fixed` / `### Removed` heading. **The deploy script will refuse to proceed if `[Unreleased]` is empty** — patch notes are mandatory, not optional.

Example:

```markdown
## [Unreleased]

### Fixed

- Resource loaders now work in exported builds (perks, monster affixes,
  named monsters were silently empty after the playtest export).

### Added

- Hardcore mode toggle on the character creation panel.
```

## Quick Deploy

**macOS / Linux:**
```bash
cd tools/steam
./deploy.sh                # patch bump (default): 0.1.0 → 0.1.1
BUMP=minor ./deploy.sh     # 0.1.0 → 0.2.0
BUMP=major ./deploy.sh     # 0.1.0 → 1.0.0
```

**Windows:**
```bat
cd tools\steam
deploy.bat              :: patch bump (default)
deploy.bat minor        :: 0.1.0 → 0.2.0
deploy.bat major        :: 0.1.0 → 1.0.0
```

Both scripts accept config via environment variables:
```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot \
STEAMCMD=steamcmd \
STEAM_USER=your_username \
PYTHON=python3.12 \
./deploy.sh
```

This will:
1. **Bump version** in `BuildInfo.gd` (semver, `--bump` controls which component)
2. **Roll the changelog** — moves `## [Unreleased]` body to a `## [VERSION] - DATE` section, leaves a fresh empty `## [Unreleased]` above
3. **Update the VDF `desc`** to `v<version> · <git-sha> · <first changelog bullet>` so the Steamworks build list is scannable
4. Clean the `build/windows/` directory
5. Export the Godot project (headless, release mode) — cross-compiles on macOS
6. Upload to Steam via SteamCMD (prompts for password + Steam Guard on first run)

After upload succeeds, **commit the changes** — the script edited `BuildInfo.gd`, `CHANGELOG.md`, and the VDF on disk:
```bash
git commit -am "Release v0.1.1"
git tag v0.1.1            # optional but useful for `git log` navigation
git push --follow-tags
```

### Dry Run

If you want to see what version would be bumped without actually deploying:
```bash
python3 tools/steam/prepare_build.py --bump patch --dry-run
```

That skips file writes and tells you the new version + VDF desc the real run would produce.

## After Upload

The build uploads in draft state. To make it available:

1. Go to https://partner.steamgames.com
2. Navigate to **App 4689320** > **SteamPipe** > **Builds**
3. Find your new build (sorted by time, description matches the VDF `desc` field)
4. Set it live on the **default** branch

## Opening the Playtest

One-time setup after the first build is live:

1. **App 4689320** > **General** > **Playtest Settings**
2. Toggle **Signup enabled** to ON
3. Toggle **Auto-accept** to ON (players get instant access) or leave off for manual waves
4. Set **Max players** (optional — leave blank for unlimited)

The "Request Access" button appears automatically on the base game's store page.

## App/Depot IDs

| Entity            | ID      |
|-------------------|---------|
| Playtest App      | 4689320 |
| Playtest Depot    | 4689321 |

## File Structure

```
tools/steam/
  prepare_build.py         # Version bump + changelog rotation + VDF desc rewrite
  app_build_4689320.vdf    # App-level build config (desc auto-updated by prepare_build.py)
  depot_build_4689321.vdf  # Depot file mapping + exclusions
  deploy.sh                # macOS/Linux: prepare + export + upload
  deploy.bat               # Windows: prepare + export + upload
  output/                  # SteamPipe build logs (auto-created, gitignored)

CHANGELOG.md               # Patch notes (root of repo). [Unreleased] section is the
                           # source of truth for what's in the next deploy.
```

## Troubleshooting

**"Godot export failed"**
- Is `godot` on your PATH? Try `godot --version`.
- macOS: set `GODOT=/Applications/Godot.app/Contents/MacOS/Godot` or wherever your .app lives.
- Are export templates installed? Editor > Manage Export Templates > download if missing.
- Cross-compiling Windows from macOS works out of the box — no extra toolchain needed.

**"SteamCMD upload failed"**
- First run requires interactive login (password + Steam Guard). Run `steamcmd +login your_username +quit` once to cache credentials.
- Make sure your account has "Edit App Metadata" permission for app 4689320 in Steamworks.
- Apple Silicon Macs: SteamCMD is x86-only. Run `softwareupdate --install-rosetta` if you get "Bad CPU type in executable".

**Build uploads but depot is empty**
- Check that `build/windows/` actually contains the exported files after the Godot step.
- The VDF uses a relative `contentroot` (`../../build/windows/`) — run the script from `tools/steam/`.

**"prepare_build.py failed" / "CHANGELOG.md '## [Unreleased]' section is empty"**
- The deploy script intentionally refuses to ship without patch notes. Open `CHANGELOG.md`, write what's in this build under `## [Unreleased]` (use the existing `### Added` / `### Fixed` headings as a template), then re-run.

**"NoInstallsError: No runtimes are installed" (Windows)**
- You have Microsoft's Python Install Manager (`py.exe`) but no actual Python interpreter. Run `py install default` once, then `python --version` should work.
