---
name: Itemization & attribute revamp
description: Major system pivot — removing 8 moral attributes, gear now has direct bonuses + behavior mods, 5 perk tiers via talents, power budget item generation
type: project
---

Major design pivot in progress (May 2025):

- 8 moral attributes (Brutality, Empathy, etc.) fully removed
- Gear no longer carries abstract stats that gate builds — instead carries direct bonuses and behavior-changing mods
- Each gear slot owns a stat domain (gloves=attack speed, legs=movement speed, etc.) + has a pool of behavior mods
- Gear slots: head, chest, hands, legs, feet, back (backpack), weapon, offhand. Recon slot removed (head absorbs it).
- Perk tiers expand to 5 (I-V), unlocked via talent tree rather than gear stats
- Item generation uses a power budget system — each item gets a budget based on level/rarity, spends it across base stats, mod quality, affixes
- Sprint mechanic added (shift, resource cost, moddable)
- All items roll +HP and +resource; other stats stay relevant to item type (armor=damage reduction, weapons=crit/knockback)
- Mods are rollable with their own modifiers (e.g., jetpack at 18 vs 26 res/sec)
- Super-rare mods can grant class talent access or have class restrictions

**Why:** The stat-allocation-from-gear system felt passive — players discovered builds from drops rather than choosing them. Talents become the active build spine, gear becomes the amplifier.

**How to apply:** All docs referencing the old 8-attribute system need rewriting. New itemization.md is the source of truth. Code changes will be massive — defer implementation until docs are solid.
