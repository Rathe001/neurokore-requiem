---
name: Procgen level realism pass
description: Procgen levels scaled to 25-40 rooms with asylum/prison clutter, facility-themed rooms, pit design elements, and doors
type: project
---

Procgen levels (procgen_demo.tres) scaled up to match prototype_layout's scope: 10-14 room chain + depth 2-4 branches = 25-40 rooms total, ground 320x120.

**Design decisions:**
- Pits are used as **design elements** (bridges, islands, crossings), not just jump puzzles. Large pillar_size creates continuous walkways; pillar arrays form shapes (cross, bridge strip).
- Clutter is asylum/prison themed: MedicalCart, FilingCabinet, CellBars, ExamTable, RestraintChair, etc. Metal-forward, no wood.
- ~85% of connections get doors (door_chance export on BranchingGenerator).
- Themed facility rooms (cell_block, mess_hall, medical_ward, security_checkpoint, isolation_wing) mix into the linear pool alongside existing combat rooms.
- Role rooms (start/end/junction/branch) use larger variants so fights aren't cramped.

**Why:** First level (hand-built) had 25 rooms across 100x130; procgen was only 5-8 rooms in 160x60. Players blew through procgen levels in under a minute.

**How to apply:** When adding new procgen room templates, match the facility/institutional tone. New pit rooms should use the design-element pattern (large pillar_size for walkways) unless specifically designing a jump challenge.
