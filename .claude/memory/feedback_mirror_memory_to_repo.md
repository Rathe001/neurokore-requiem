---
name: Always mirror memory to repo
description: Memory writes must be mirrored to .claude/memory/ in the repo AND committed — canonical-only writes cause cross-machine drift
type: feedback
---

Every memory write must go to BOTH the canonical per-machine location AND `.claude/memory/` in the repo. Stage the repo copy with the related code commit so it travels with `git push`.

**Why:** Writing only to the canonical location means the repo doesn't carry the update. The other machine pulls stale memory, edits on top of it, and pushes — silently overwriting the newer version. This happened with project_visual_meters.md and MEMORY.md on 2026-05-15.

**How to apply:** After every Write to `~/.claude/projects/.../memory/`, immediately `cp` to `.claude/memory/` in the repo. When committing related code, include the memory file in the same commit (or a dedicated memory commit if no code changed).
