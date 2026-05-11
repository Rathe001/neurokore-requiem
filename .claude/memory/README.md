# Claude memory — synced via git

This directory is the **committed mirror** of Claude Code's auto-memory for the
project. The canonical per-machine location is:

- Windows: `C:\Users\<user>\.claude\projects\C--Users-<user>-Projects-neurokore-requiem\memory\`
- Linux/Mac: `~/.claude/projects/-Users-<user>-Projects-neurokore-requiem/memory/`

(The path is OS-dependent because Claude Code encodes the project's filesystem
path into the memory directory name.)

## Why this exists

Memories accumulate per-machine. When you pull this repo on another machine,
its Claude instance has none of the project context built up on the original
machine. Mirroring the files into the repo means a quick sync step picks up
the latest understanding without re-discovering everything.

## Sync flow

**Onto a fresh machine (or after `git pull`):**

```bash
# Linux/Mac
cp .claude/memory/*.md ~/.claude/projects/-Users-$USER-Projects-neurokore-requiem/memory/

# Windows (PowerShell)
Copy-Item .claude\memory\*.md $env:USERPROFILE\.claude\projects\C--Users-$env:USERNAME-Projects-neurokore-requiem\memory\
```

**After Claude writes new memories (Windows, PowerShell):**

```powershell
Copy-Item $env:USERPROFILE\.claude\projects\C--Users-$env:USERNAME-Projects-neurokore-requiem\memory\*.md .claude\memory\
```

Then commit the diff. Claude on this project has been asked to commit memory
updates proactively — they should land alongside the relevant feature commit
rather than as a separate "sync memory" commit.

## What lives here

- `MEMORY.md` — the index. Always loaded into the conversation; keep concise.
- `user_*.md` — facts about the user.
- `project_*.md` — facts about the project that aren't derivable from code.
- `feedback_*.md` — collaboration guidance (do this, don't do that, with why).
- `reference_*.md` — pointers to external systems (Linear projects, Grafana boards, etc.).

See [the auto-memory section in CLAUDE.md] (project root) for the schema and
write conventions.
