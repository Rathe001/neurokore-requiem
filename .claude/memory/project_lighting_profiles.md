---
name: Zone lighting profiles (planned)
description: Proximity lighting and global light behavior should be driven by per-zone profiles, not hardcoded constants
type: project
originSessionId: 3ccada6b-b909-4f94-a64f-38aa2efcfd7e
---
Lighting effects (proximity dimming, global brightness floor, falloff radii, etc.) should eventually be selected by zone profile rather than hardcoded.

**Why:** Outdoor zones need fundamentally different global lighting than indoor/dungeon zones — e.g. an outdoor area shouldn't feel pitch-black with a personal-bubble pool the way Sub-Level Zero does. Aligns with the existing `docs/world/lighting.md` "zone lighting tiers" concept.

**How to apply:** When extending `scripts/systems/proximity_lighting.gd` (or adding new lighting systems), expose the constants (INNER_RADIUS, OUTER_RADIUS, DIM_FACTOR, etc.) as a profile resource that a zone selects on load, rather than tuning the autoload globals. Don't bake assumptions about indoor-style darkness into shared code.
