---
name: Enemy attribute affinity
description: Enemies have stat affinities that counter opposing player stats — damage scales by tier mismatch
type: project
---

Enemies can have an **attribute affinity** (e.g., Deviation, Orthodoxy, etc.).

**Damage interaction with players:**
- An enemy's affinity opposes the nemesis stat on the player side.
- Rather than computing raw stat differences, use the player's **attribute tier** in the opposing stat to determine the bonus.
- Example: enemy with "Deviation" affinity vs. a player with Orthodoxy tiers:
  - Tier 1 Orthodoxy → small extra damage dealt to/resisted less by the player
  - Tier 2 → moderate extra damage
  - Tier 3 → large extra damage

**Affinity levels:** Enemies can also have affinity *levels* that scale the tier-based bonus further (e.g., a weak Deviation-affinity mob vs. a Deviation-affinity boss).

**Why:** Creates a rock-paper-scissors dynamic that rewards diverse stat investment and makes enemy composition tactically meaningful.

**How to apply:** When implementing enemy damage or resistance, look up the enemy's affinity, find the player's tier in the opposing stat, and apply a multiplier scaled by both tier and affinity level.
