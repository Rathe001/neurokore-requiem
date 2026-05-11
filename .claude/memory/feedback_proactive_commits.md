---
name: Commit proactively at logical breakpoints
description: User wants commits to happen automatically when work reaches a sensible stopping point, instead of waiting for "please commit" each time
type: feedback
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
Commit work proactively at logical breakpoints — don't wait to be asked.

**Why:** User said "in the future just go ahead and commit work as makes the most logical sense." Several large change sets piled up uncommitted across this session (camera/shake/push, footstep particles, icon resolver, save manager, tooltip format, equipment layout, missions panel, energy ramp, shader/scene tweaks) before being bundled at the end. That's friction.

**How to apply:**
- Commit when a feature/fix reaches a self-contained working state — don't accumulate unrelated changes.
- Group by intent: one commit per "thing the user asked for" rather than one giant dump.
- Still ask before risky operations (force push, rebase, anything destructive). Routine commits don't need confirmation.
- Mention what was committed in the response so the user can verify, but don't make a production of it.
