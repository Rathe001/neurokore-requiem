---
name: deploy.bat Godot shim still breaks step 3
description: Recurring trap — `deploy.bat`'s `call %GODOT%` resolves to the deploy.bat dir even though `call` should preserve %~dp0. Bit us in v0.3.0 and v0.4.0. Always invoke the Godot exe directly during deploy.
type: project
originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---
**Status:** Bit us in v0.3.0 (2026-05-13), v0.4.0 (2026-05-15), and v0.4.1 (2026-05-20) deploys. The `call` in `deploy.bat:56` was supposed to fix this in v0.3.0 but doesn't actually resolve the issue. Three strikes — at this point the workaround is the deploy path; the `call` line is decorative.

**Symptom:** `deploy.bat` step 3 (Godot export) errors with
```
'"C:\...\tools\steam\Godot_v4.6.2-stable_win64_console.exe"' is not recognized
```
The `tools\steam\` segment is wrong — that's `deploy.bat`'s dir, not `godot.cmd`'s. Means `%~dp0` inside `godot.cmd` is resolving to the caller instead of the shim itself.

**Workaround** (used in both deploys):
1. Let `deploy.bat` run steps 1–2 (prepare_build + clean) until it errors out on step 3.
2. Run Godot export manually with the absolute exe path:
   ```powershell
   & "C:\Users\josh\Tools\Godot\Godot_v4.6.2-stable_win64_console.exe" `
     --headless --path "C:\Users\josh\Projects\neurokore-requiem\game" `
     --export-release "Windows Desktop" `
     "C:\Users\josh\Projects\neurokore-requiem\build\windows\neurokore-requiem.exe"
   ```
3. Manually run steamcmd (step 4):
   ```powershell
   & "C:\Users\josh\Tools\steamcmd\steamcmd.exe" +login darkapocrypha `
     +run_app_build "C:\Users\josh\Projects\neurokore-requiem\tools\steam\app_build_4689320.vdf" +quit
   ```
   (Cached credentials work — no Steam Guard prompt needed unless they expire.)

**Why:** Suspect cmd.exe's `call "%GODOT%"` where `%GODOT%=godot` doesn't behave the same as `call godot` for `%~dp0` resolution. Or the shim invocation path differs when called from a parent batch vs. directly. Not fully diagnosed.

**How to apply:**
- When deploying, don't try to "fix" the `call` line — it's already there. Just expect step 3 to fail and run Godot directly.
- Real fix attempt for next time: change `godot.cmd` to use an absolute path to the exe instead of `%~dp0`, OR change `deploy.bat` to call the Godot exe directly via an env var (`GODOT_EXE` pointing at the full path).
- This is separate from the `STEAM_USER` env var being unset — that one was solved by passing `darkapocrypha` explicitly. Both are minor papercuts on the otherwise-working deploy pipeline.
- For agent-driven deploys where the parent shell's env may not have refreshed STEAM_USER even though `setx` wrote it, fetch the user-scope value at call time: `[Environment]::GetEnvironmentVariable("STEAM_USER", "User")`. Works in v0.4.1's deploy without re-spawning the shell.
