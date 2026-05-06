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
set PREPARE=%~dp0prepare_build.py

:: Bump type can be overridden: set BUMP=minor before running, or pass as %1
if "%BUMP%"=="" set BUMP=patch
if not "%~1"=="" set BUMP=%~1
if "%PYTHON%"=="" set PYTHON=python

echo.
echo ========================================
echo  Neurokore: Requiem — Steam Deploy
echo ========================================
echo.

:: ── Step 1: Bump version + roll CHANGELOG ────────────────────────────────────
echo [1/4] Preparing build (version bump + changelog rotation)...
"%PYTHON%" "%PREPARE%" --bump %BUMP%

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: prepare_build.py failed. The most common cause is an empty
    echo CHANGELOG '## [Unreleased]' section — add your patch notes there
    echo before re-running.
    exit /b 1
)

:: ── Step 2: Clean previous build ─────────────────────────────────────────────
echo [2/4] Cleaning previous build...
if exist "%BUILD_DIR%" (
    rmdir /s /q "%BUILD_DIR%"
)
mkdir "%BUILD_DIR%"

:: ── Step 3: Export from Godot ────────────────────────────────────────────────
echo [3/4] Exporting Windows build from Godot...
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

:: ── Step 4: Upload to Steam ──────────────────────────────────────────────────
echo [4/4] Uploading to Steam via SteamCMD...
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
echo   4. Commit the version bump + changelog (the script edited
echo      build_info.gd, CHANGELOG.md, and the VDF on disk):
echo         git commit -am "Release v<version>"
echo.

endlocal
