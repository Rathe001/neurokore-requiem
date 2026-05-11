---
name: Don't commit usernames/credentials into deploy scripts
description: When a committed script needs a user-specific value (username, paths, tokens), use an env-var-respecting default — never substitute the real value into the file
type: feedback
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
When a committed file (deploy script, config, etc.) has a placeholder like `your_steam_username`, the right fix is to make the script honor an environment variable, not to substitute the real value into the committed file. Even a "temporary" edit-and-restore is a footgun: easy to forget the restore, and the diff sits in `git status` waiting to be accidentally added.

**Why:** Josh caught me about to commit his Steam username into `deploy.bat` after I'd "edit then revert" planned. He explicitly doesn't want personal identifiers landing in the repo.

**How to apply:** When a deploy/build script has a hardcoded placeholder, check if a sibling script (e.g. `deploy.sh` next to `deploy.bat`) already uses the env-var pattern — if yes, port that pattern over as a real fix. In Bash: `VAR="${VAR:-default}"`. In batch: `if "%VAR%"=="" set VAR=default`. Then the user's local env var (or `setx`) carries the real value, and the placeholder stays in the repo as a hint for new contributors. If you absolutely must edit a committed file with a real value temporarily, never call `git add` on it without explicit user OK.
