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

echo ""
echo "========================================"
echo " Neurokore: Requiem — Steam Deploy"
echo "========================================"
echo ""

# ── Step 1: Clean previous build ─────────────────────────────────────────────
echo "[1/3] Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Step 2: Export from Godot ─────────────────────────────────────────────────
echo "[2/3] Exporting Windows build from Godot..."
"$GODOT" --headless --path "$GAME_DIR" --export-release "Windows Desktop" "$BUILD_DIR/neurokore-requiem.exe"

echo "   Export complete: $BUILD_DIR"

# ── Step 3: Upload to Steam ──────────────────────────────────────────────────
echo "[3/3] Uploading to Steam via SteamCMD..."
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
echo ""
