@echo off
setlocal

:: ── Configuration ────────────────────────────────────────────────────────────
:: Path to the Godot editor executable. Update this if yours lives elsewhere.
set GODOT=godot
:: Path to steamcmd.exe. Update this to your local install.
set STEAMCMD=steamcmd
:: Steam account used for uploads (must have Steamworks publisher permissions).
set STEAM_USER=your_steam_username
:: ─────────────────────────────────────────────────────────────────────────────

set ROOT=%~dp0..\..
set GAME_DIR=%ROOT%\game
set BUILD_DIR=%ROOT%\build\windows
set VDF=%~dp0app_build_4689320.vdf

echo.
echo ========================================
echo  Neurokore: Requiem — Steam Deploy
echo ========================================
echo.

:: ── Step 1: Clean previous build ─────────────────────────────────────────────
echo [1/3] Cleaning previous build...
if exist "%BUILD_DIR%" (
    rmdir /s /q "%BUILD_DIR%"
)
mkdir "%BUILD_DIR%"

:: ── Step 2: Export from Godot ────────────────────────────────────────────────
echo [2/3] Exporting Windows build from Godot...
"%GODOT%" --headless --path "%GAME_DIR%" --export-release "Windows Desktop" "%BUILD_DIR%\neurokore-requiem.exe"

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Godot export failed. Check that:
    echo   - Godot is on your PATH or update GODOT in this script
    echo   - Windows export template is installed
    echo   - export_presets.cfg has a "Windows Desktop" preset
    exit /b 1
)

echo    Export complete: %BUILD_DIR%

:: ── Step 3: Upload to Steam ──────────────────────────────────────────────────
echo [3/3] Uploading to Steam via SteamCMD...
"%STEAMCMD%" +login %STEAM_USER% +run_app_build "%VDF%" +quit

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: SteamCMD upload failed. Check that:
    echo   - steamcmd is on your PATH or update STEAMCMD in this script
    echo   - Your Steam account has publisher permissions
    echo   - Steam Guard code is entered when prompted
    exit /b 1
)

echo.
echo ========================================
echo  Upload complete!
echo ========================================
echo.
echo Next steps:
echo   1. Go to https://partner.steamgames.com
echo   2. App Admin ^> SteamPipe ^> Builds
echo   3. Set the new build live on the "default" branch
echo.

endlocal
