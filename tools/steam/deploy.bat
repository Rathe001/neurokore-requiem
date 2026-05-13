@echo off
setlocal

:: -- Configuration ------------------------------------------------------------
:: All three honor an existing env var if set; placeholder defaults match the
:: pattern in deploy.sh (${VAR:-default}). Set STEAM_USER persistently with
:: `setx STEAM_USER your_username` (fresh terminal required) so you don't have
:: to substitute it into this committed file each deploy.
if "%GODOT%"=="" set GODOT=godot
if "%STEAMCMD%"=="" set STEAMCMD=steamcmd
if "%STEAM_USER%"=="" set STEAM_USER=your_steam_username
:: -----------------------------------------------------------------------------

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
echo  Neurokore: Requiem - Steam Deploy
echo ========================================
echo.

:: -- Step 1: Bump version + roll CHANGELOG ------------------------------------
echo [1/4] Preparing build (version bump + changelog rotation)...
"%PYTHON%" "%PREPARE%" --bump %BUMP%

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: prepare_build.py failed. The most common cause is an empty
    echo CHANGELOG '## [Unreleased]' section - add your patch notes there
    echo before re-running.
    exit /b 1
)

:: -- Step 2: Clean previous build ---------------------------------------------
echo [2/4] Cleaning previous build...
if exist "%BUILD_DIR%" (
    rmdir /s /q "%BUILD_DIR%"
)
mkdir "%BUILD_DIR%"

:: -- Step 3: Export from Godot ------------------------------------------------
echo [3/4] Exporting Windows build from Godot...
:: `call` is mandatory when %GODOT% resolves to a .cmd shim (godot.cmd). Without
:: it, the shim's `%~dp0` evaluates against deploy.bat's directory instead of
:: the shim's own folder, so the shim tries to invoke the Godot exe from
:: tools\steam\ and bombs out with "not recognized."
call "%GODOT%" --headless --path "%GAME_DIR%" --export-release "Windows Desktop" "%BUILD_DIR%\neurokore-requiem.exe"

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Godot export failed. Check that:
    echo   - Godot is on your PATH or update GODOT in this script
    echo   - Windows export template is installed
    echo   - export_presets.cfg has a "Windows Desktop" preset
    exit /b 1
)

echo    Export complete: %BUILD_DIR%

:: -- Step 4: Upload to Steam --------------------------------------------------
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
