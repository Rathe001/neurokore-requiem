# Attribute System

> Status: Design phase — not yet implemented.

Each of the 8 class/spec identities maps to a moral attribute. Items roll these stats, and characters scale off them based on their spec. Think Pokemon type matchups, but grounded in the morality system.

## The 8 Attributes

Six **spec stats** roll on items. Two **base class stats** are derived, not rolled.

| Stat | Tied To | Opposes | Rollable |
|---|---|---|---|
| Soul | Human (base) | Interface | No (derived) |
| Interface | Cyborg (base) | Soul | No (derived) |
| Orthodoxy | Gentleman | Deviation | Yes |
| Deviation | Forged | Orthodoxy | Yes |
| Optimization | Automaton | Ingenuity | Yes |
| Ingenuity | Survivalist | Optimization | Yes |
| Sanity | Polymath | Corruption | Yes |
| Corruption | Enculted | Sanity | Yes |

### Soul & Interface — Derived Stats

Soul and Interface do not roll on items. They are calculated from the average of the character's three team stats (the three spec stats belonging to the same class).

- **Human → Soul** = average of Orthodoxy, Ingenuity, Sanity
- **Cyborg → Interface** = average of Deviation, Optimization, Corruption

This means Soul/Interface rise naturally as you gear well for your team. They are never chased directly — they are a byproduct of coherent gearing.

## Scaling Rules

For any given character build:

- **Own spec's stat** → full scaling (1x)
- **Other two same-class spec stats ("team stats")** → partial scaling (initial target: 0.25x, subject to tuning)
- **Base class stat** (Soul / Interface) → scales off team stats via skill tree (see below)
- **Opposing spec's stat** → negative scaling (target range: -0.25x to -0.5x)
- **Opposite class's non-opposing stats** → no benefit (0x)

### Example — Human Gentleman

| Stat | Scaling | Reason |
|---|---|---|
| Orthodoxy | 1x | Own spec |
| Sanity | 0.25x | Same class, non-opposing |
| Ingenuity | 0.25x | Same class, non-opposing |
| Soul | derived | Average of Orthodoxy + Sanity + Ingenuity |
| Deviation | negative | Opposing spec |
| Interface, Optimization, Corruption | 0x | Opposite class |

### Base Class Scaling — Skill Tree Mechanic

By default, the base class stat (Soul / Interface) scales off the **lowest** of the three team stats. This forces balanced gearing across all three team stats.

Skill tree nodes can change this calculation:

| Node | Scales Off | Gearing Effect |
|---|---|---|
| (default) | Lowest of 3 team stats | Must balance all three — every item matters |
| Balanced | Average of 3 team stats | Tolerates some lopsidedness |
| Focused | Highest of 3 team stats | Go all-in on main stat, ignore the others |

Each option completely reframes what "good gear" means for the same class. This is a build-defining choice.

## Item Stat Budget

Items roll a fixed total stat budget distributed across attributes. The distribution — not just the total — determines the item's value for any given build.

Example: an item with 10 total stat points might roll:

| Distribution | Main Stat | Team Stat | Opposing |
|---|---|---|---|
| Clean roll | 5 | 4 | 1 |
| Hybrid roll | 3 | 3 + 3 | 1 |
| Lopsided roll | 7 | 1 | 2 |

A hybrid 3/3/3 roll could be better than a clean 5/4/1 for a character using the "Lowest" base class scaling — because raising your weakest team stat matters more than stacking your main. The same item is worse under "Focused" scaling. Itemization decisions shift entirely based on skill tree choices.

## Spec-Specific Stat Functions

Each spec's main stat affects damage, but also has a unique mechanical function tied to the spec fantasy:

| Stat | Spec | Damage Scaling | Special Function |
|---|---|---|---|
| Orthodoxy | Gentleman | Yes | TBD |
| Deviation | Forged | Yes | Allows attaching more limbs |
| Optimization | Automaton | Yes | TBD |
| Ingenuity | Survivalist | Yes | TBD |
| Sanity | Polymath | Yes | TBD |
| Corruption | Enculted | Yes | TBD |

These special functions are what make each stat feel different beyond raw numbers. A Forged stacking Deviation isn't just hitting harder — they're unlocking body modification slots.

## Opposing Stat Philosophy

Opposing stats should feel **wrong and disappointing** on an otherwise great item, but not cripple the character unless deliberately stacked. The negative multiplier (-0.25x to -0.5x) is a tax, not a death sentence.

Design space exists for **build-around uniques** that require stacking your opposing stat and scale off it — forcing the player into "wrong" gear for a powerful payoff. A Gentleman wearing Deviation-heavy gear is narratively compelling and mechanically novel.

## Design Intent

Items carry moral weight. A Forged player finding Orthodoxy-heavy gear is actively hurt by it — reinforcing character identity at the itemization level. This ties directly into the 2D morality plane and makes item drops feel meaningful beyond raw numbers.

## Open Questions

- Exact **team stat scaling multiplier** (0.25x is a starting point, needs playtesting).
- Exact **negative scaling multiplier** (-0.25x to -0.5x range, needs playtesting).
- **Spec-specific stat functions** for Orthodoxy, Optimization, Ingenuity, Sanity, Corruption.
- **Tooltip design**: show stats the character scales off (positive or negative); hide irrelevant 0x stats to reduce noise.
- What does **Soul** govern beyond being a derived stat? Candidates: willpower, resilience, HP, CC resistance.
- What does **Interface** govern beyond being a derived stat? Candidates: precision, latency, cooldown reduction, cast speed.
