# Classes Overview

**Class identity is the core design pillar.** Each class plays differently enough that it could feel like a different game mode.

## Core Principles

- Class-specific core mechanics — not all classes share the same resource systems, survival mechanics, or win conditions. For example, not all classes will have a health bar.
- 8 classes at launch: 2 **origin classes** ([Human](human.md) and [Cyborg](cyborg.md)) plus 6 **specialized classes** (3 per origin).
- Specialized classes are unlocked through specific quests — similar to WoW Legion artifact weapon quests. The unlock quest should feel thematic and personal to the class.
- Deep build diversity per class, with itemization designed to create build desire — finding an item should make you want to try a new build.

## Origin vs. Specialized Classes

Origin classes (Human and Cyborg) are generalists — jack of all trades for their respective path. They are the easiest to understand and the most forgiving to gear. All three of their team's attributes contribute equally to a single derived stat (Soul or Interface).

Specialized classes trade that flexibility for depth. They scale primarily off one attribute, get partial benefit from their two team stats, and are actively hurt by their opposing stat. See [Attribute System](../design/attribute-system.md) for full scaling rules.

## Resource System

Each class has **one unique resource** that encapsulates the energy they would expend in the real world. Resources are class-specific and mechanically distinct.

| Class | Resource | Description |
|---|---|---|
| Human | TBD | Generalist — should capture the unaugmented human experience |
| Cyborg | TBD | Generalist — should capture the augmented machine experience |
| Survivalist | Adrenaline | Builds under pressure, decays when safe |
| Gentleman / Lady | Composure | Maintained through controlled play, breaks under panic |
| Enculted | TBD | Rethinking — should align with ambition-as-power fantasy |
| Forged | Power Grid | Power budget — manage what's active simultaneously |
| Automaton | Bandwidth | Caps how many drones/scripts run simultaneously |
| Polymath | TBD | Rethinking — was Memory/CPU dual axis, may simplify to one resource |

## Stat Identity & Tier Perks

Attribute distribution drives **tier perks** — mechanical rewards that unlock at stat breakpoints and are lost if the breakpoint is no longer met. Gear swaps have real consequences. Each class has unique perks; origin classes are rewarded for balance. Character appearance transforms dynamically to reflect stat identity.

See [Attribute System — Stat Identity](../design/attribute-system.md#stat-identity--tier-perks--visual-metamorphosis) for full details on breakpoints, cross-class perk unlocking, visual metamorphosis, and NPC identity reactions.

## Character Creation

Players choose male or female at the start. Both are fully supported for all classes. This effectively doubles the required player character models — a scope consideration for production and a factor in tech stack decisions around animation systems.
