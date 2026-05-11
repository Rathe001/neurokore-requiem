---
name: Estimate completion time in minutes (my time, not human-dev time)
description: When proposing or scoping work, give estimates in minutes for how long it'll take me to finish — never developer-week estimates
type: feedback
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
When I float an estimate for completing a task ("a few hours", "2-3 weeks of plumbing", "a day's work"), give it in **minutes for my own completion time**, not the equivalent human-developer estimate.

**Why:** The user works with me — what matters is when the work would actually land in their playtest, not what a dev shop would quote. Human-dev estimates are off by 10-100× and inflate scope decisions ("that's too big to tackle now"), which leads to deferring work that I could finish in the same session as the conversation. They've called this out explicitly.

**How to apply:**
- Default unit is minutes. Hours only when genuinely longer than ~90 minutes of focused work; flag "longer" rather than guessing days.
- Calibrate against what I've actually done: the host-disconnect overlay was ~10 minutes (one new file, three small edits). The flame visual rewrite was ~15 minutes. The DPS audit + fixes was ~30-45 minutes. The recent in-game chat (autoload + UI + input gate) was ~25-30 minutes.
- For "should we do this?" decisions, the honest comparison is "10 minutes now" vs "15 minutes later" — not "a day's work" vs "next sprint."
- Big asterisks the user can't easily verify (UI feel, MP behavior under real load) get called out separately. Don't bury verification debt in the time estimate.
