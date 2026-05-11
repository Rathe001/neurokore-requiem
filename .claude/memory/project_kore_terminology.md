---
name: Kore terminology
description: "Kore" is the project's term for stats sharing an origin (replaces "team" stats throughout code + docs)
type: project
originSessionId: 3039965d-18fc-4299-bf16-996eecddf5ee
---
The system formerly called "team stats" is now called **kore stats** — named after the game's title (Neurokore: Requiem).

**Why:** "Team" was generic and gamey; "Kore" ties the mechanics into the game's identity. A character has a *kore* (their fundamental nature); stats matching it scale them up; stats from the opposite kore are "opposing" and create distortion.

**How to apply:**
- Code identifiers: `ANALOG_KORE_STATS`, `CYBORG_KORE_STATS`, `TIERS_KORE_SPEC`, `TIERS_KORE_ORIGIN`, `KORE_NODE_THRESHOLDS`, `kore_node_allocations`, `is_kore_node_active`, `get_kore_stats_for_origin`, `get_kore_nodes_tier`, etc.
- Relationship strings: `&"primary"`, `&"kore"`, `&"opp_kore"`, `&"opposing"` (NOT `&"team"`/`&"opp_team"`).
- Docs: "kore stats" (lowercase noun); "Kore" capitalized when referring to the relationship category in tables.
- Anywhere you see "team" in a stat-relationship context, it's stale — should be "kore".

Renamed in commit on 2026-05-03.
