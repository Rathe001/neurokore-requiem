#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
# Path to the Godot editor binary. Common locations:
#   macOS:    /Applications/Godot.app/Contents/MacOS/Godot
#   Linux:    godot or /usr/local/bin/godot
#   Windows:  handled by deploy.bat instead
GODOT="${GODOT:-godot}"
# Path to steamcmd. Install via Homebrew: brew install steamcmd
# Apple Silicon Macs also need Rosetta: softwareupdate --install-rosetta
STEAMCMD="${STEAMCMD:-steamcmd}"
# Steam account used for uploads (must have Steamworks publisher permissions).
STEAM_USER="${STEAM_USER:-your_steam_username}"
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/../.."
GAME_DIR="$ROOT/game"
BUILD_DIR="$ROOT/build/windows"
VDF="$SCRIPT_DIR/app_build_4689320.vdf"
PREPARE="$SCRIPT_DIR/prepare_build.py"

# Bump type can be overridden: BUMP=minor ./deploy.sh
BUMP="${BUMP:-patch}"
PYTHON="${PYTHON:-python3}"

echo ""
echo "========================================"
echo " Neurokore: Requiem — Steam Deploy"
echo "========================================"
echo ""

# ── Step 1: Bump version + roll CHANGELOG ────────────────────────────────────
echo "[1/4] Preparing build (version bump + changelog rotation)..."
"$PYTHON" "$PREPARE" --bump "$BUMP"

# ── Step 2: Clean previous build ─────────────────────────────────────────────
echo "[2/4] Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Step 3: Export from Godot ─────────────────────────────────────────────────
echo "[3/4] Exporting Windows build from Godot..."
"$GODOT" --headless --path "$GAME_DIR" --export-release "Windows Desktop" "$BUILD_DIR/neurokore-requiem.exe"

echo "   Export complete: $BUILD_DIR"

# ── Step 4: Upload to Steam ──────────────────────────────────────────────────
echo "[4/4] Uploading to Steam via SteamCMD..."
"$STEAMCMD" +login "$STEAM_USER" +run_app_build "$VDF" +quit

echo ""
echo "========================================"
echo " Upload complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Go to https://partner.steamgames.com"
echo "  2. App Admin > SteamPipe > Builds"
echo "  3. Set the new build live on the \"default\" branch"
echo "  4. Commit the version bump + changelog:"
echo "     git commit -am 'Release v\$(grep -oE \"\\\"\\d+\\.\\d+\\.\\d+\\\"\" \"$GAME_DIR/scripts/systems/build_info.gd\" | head -1 | tr -d \\\")'"
echo ""
