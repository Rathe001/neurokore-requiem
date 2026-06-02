---
name: blood-decal-ring
description: "Global blood-decal ring buffer (cap 400) with priority eviction sort — (priority asc, area asc, age asc). NOTE 2026-06-01: floor pools moved to [[project_liquid_layer]] so the ring now holds walls + footprints + character splats only. Will shrink further as #110/#111 land."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**2026-06-01 status:** Floor pools no longer use this ring — they
rasterize into [[project_liquid_layer]]. The ring still backs wall
splats, footprints, and character splats. Once #110 (walls) and
#111 (character/object) land, the ring + its priority sort can be
deleted entirely; until then it's still load-bearing.

**Where the dial lives.** `prototype_attack_indicator.gd` — `_track_blood_decal(decal, keep_priority)` is the single registration point. Every wall/footprint/character blood spawn path calls it; object decals self-free via tween and stay out of the ring.

**Capacity:** `BLOOD_DECAL_MAX = 400`. Cap chosen empirically — bloodier rooms before eviction kicks in. Higher = more persistence, more decal-pass cost; lower = less storytelling but tighter perf budget.

**Eviction sort (3-tier, ascending):**
1. **`_blood_priority`** — `BLOOD_PRIORITY_FLOOR = 1`, `BLOOD_PRIORITY_WALL = 2`. Walls outrank floors so vertical splatter persists through fights that flood the floor with pools.
2. **`_blood_area`** — `decal.size.x * decal.size.z`. Smaller area evicts first. Picks mist drops over kill pools, footprints over wall splats within their priority tier.
3. **`_blood_seq`** — monotonic insertion counter. Oldest first within ties.

**Eviction order in practice, first-to-last:**
1. Floor footprints (priority 1, small)
2. Floor pools (priority 1, large)
3. Wall mist drops (priority 2, small)
4. Wall kill splatter (priority 2, large)

**Why small-first (not big-first) for perf.** Decals are rendered in a screen-space pass after opaque/transparent. Cost ≈ (projection volume in screen-space) × (fragments overlapping the depth buffer) × (shader work). A 2.5m kill pool covers ~50-100× the screen pixels of a 0.25m mist drop but takes the SAME single ring slot. Evicting big pools to make room for new mist drops would be both visually worse AND more expensive per-frame. Evicting small drops first wins on both axes — the cheap, low-storytelling decals are the recyclable filler.

**Implementation notes:**
- Eviction is O(N) linear scan through the ring (N = 400). At horde scale ~50 decals/sec, ~20k comparisons/sec — trivial vs the rendering cost saved.
- Stale-slot shortcut: footprints self-free via their own tween (see `spawn_blood_footprint`), so a ring slot can hold a freed Decal reference. The scan detects this via `is_instance_valid` and reuses the slot without priority comparison.
- `set_meta(&"_blood_seq" / _blood_area / _blood_priority)` carries the sort keys per decal. Strings are interned (StringName), Dictionary lookups are cheap.
- Once evicted, the decal isn't queue_freed instantly — `_fade_and_free` tweens `modulate.a → 0` over `_BLOOD_DECAL_FADE_DURATION = 2.5s` so there's no pop. The slot is reusable immediately (the old decal is being faded by Godot while a new one occupies the ring slot).

**What's NOT in the ring:**
- **Character blood** — its own ring (`CHARACTER_BLOOD_MAX_PER_CHAR = 5`) per character so blood follows the body but doesn't compete with world decals.
- **Object blood** (props, interactables, pillars) — self-frees via tween after `OBJECT_BLOOD_FADE_DURATION = 14s`, capped per-kill at `OBJECT_BLOOD_MAX_PER_KILL = 4` receivers. See [[object-blood-pipeline]].

**Adding a new priority tier** (e.g. "boss-room walls outrank regular walls"):
1. Add a new `BLOOD_PRIORITY_*` constant ABOVE the existing wall tier.
2. Pass it as the second arg to `_track_blood_decal(decal, BLOOD_PRIORITY_X)` at the spawn site.
3. No scan change required — the 3-tier sort already handles arbitrary integer priority values.

**Future polish if pools should dry up in quiet rooms** (independent of new spawns pushing them out): add a max-age fade — `BLOOD_DECAL_FADE_AFTER = 90s` or similar — at the spawn site or via a periodic sweep. Today the only "drying out" mechanism is FIFO/priority eviction triggered by new spawns; a fight-empty room keeps its blood forever until the next fight pushes it out.
