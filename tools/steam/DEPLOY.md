# Steam Deploy Guide

## Prerequisites

- **Godot 4** on PATH (or set `GODOT` env var / edit the script)
- **SteamCMD** installed and on PATH (or set `STEAMCMD` env var / edit the script)
  - macOS: `brew install steamcmd` (Apple Silicon also needs `softwareupdate --install-rosetta`)
  - Windows: https://developer.valvesoftware.com/wiki/SteamCMD#Downloading_SteamCMD
- **Windows export template** installed in Godot (Editor > Manage Export Templates)
- Steam account with Steamworks publisher permissions

## Quick Deploy

**macOS / Linux:**
```bash
cd tools/steam
./deploy.sh
```

**Windows:**
```bat
cd tools\steam
deploy.bat
```

Both scripts accept config via environment variables:
```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot \
STEAMCMD=steamcmd \
STEAM_USER=your_username \
./deploy.sh
```

This will:
1. Clean the `build/windows/` directory
2. Export the Godot project (headless, release mode) — cross-compiles on macOS
3. Upload to Steam via SteamCMD (prompts for password + Steam Guard on first run)

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
  app_build_4689320.vdf    # App-level build config (references depot VDF)
  depot_build_4689321.vdf  # Depot file mapping + exclusions
  deploy.sh                # macOS/Linux: one-click export + upload
  deploy.bat               # Windows: one-click export + upload
  output/                  # SteamPipe build logs (auto-created, gitignored)
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
