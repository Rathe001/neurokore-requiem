# Classes Overview

**Class identity is the core design pillar.** Each class plays differently enough that it could feel like a different game mode.

## Core Principles

- Class-specific core mechanics — not all classes share the same resource systems, survival mechanics, or win conditions. For example, not all classes will have a health bar.
- 8 classes at launch: 2 **origin classes** ([Analog](human.md) and [Cyborg](cyborg.md)) plus 6 **specialized classes** (3 per origin).
- Specialized classes are unlocked through specific quests — similar to WoW Legion artifact weapon quests. The unlock quest should feel thematic and personal to the class.
- Deep build diversity per class, with itemization designed to create build desire — finding an item should make you want to try a new build.

## Origin vs. Specialized Classes

Origin classes (Analog and Cyborg) are generalists — jack of all trades for their respective path. They are the easiest to understand and the most forgiving to gear. All three of their **kore** attributes (the three stats native to that origin) contribute equally to a single derived stat (Soul or Interface).

Specialized classes trade that flexibility for depth. They scale primarily off one attribute, get partial benefit from their two kore stats, and are actively hurt by their opposing stat. See [Attribute System](../design/attribute-system.md) for full scaling rules.

## Resource System

Each class has **one unique resource** capturing the energy they expend. Resources are class-specific and mechanically distinct.

| Class | Resource |
|---|---|
| Analog / Cyborg | TBD (origin generalists — design pending) |
| Survivalist | **Adrenaline** — builds under pressure, decays when safe |
| Count / Countess | **Composure** — maintained through controlled play, breaks under panic |
| Forged | **Power Grid** — budget for what's active simultaneously |
| Automaton | **Bandwidth** — caps active drones/scripts |
| Enculted / Polymath | TBD (rethinking — see per-class docs) |

## Stat Identity & Tier Perks

Attribute distribution drives **tier perks** that unlock at stat breakpoints and are lost when gear drops you below. All six specialist perks ship: Exile (Count), Amalgamation (Forged), Drone Swarm (Automaton), IED (Survivalist), Telekinesis (Polymath), Doomsayer (Enculted) — see each class doc and the [tier perks table](../design/attribute-system.md#specialized-class-tier-perks).

## Character Creation

Players choose male or female at the start. Both are fully supported for all classes. This effectively doubles the required player character models — a scope consideration for production and a factor in tech stack decisions around animation systems.
