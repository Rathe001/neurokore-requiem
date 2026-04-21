# Attribute System

> Status: Design phase — not yet implemented.

Each of the 8 classes maps to a moral attribute. Items roll these stats, and characters scale off them based on their class. Think Pokemon type matchups, but grounded in the morality system.

## The 8 Attributes

Six **class stats** roll on items. Two **origin stats** are derived, not rolled.

| Stat | Class | Opposes | Rollable |
|---|---|---|---|
| Soul | Human | Interface | No (derived) |
| Interface | Cyborg | Soul | No (derived) |
| Orthodoxy | Gentleman | Deviation | Yes |
| Deviation | Forged | Orthodoxy | Yes |
| Optimization | Automaton | Ingenuity | Yes |
| Ingenuity | Survivalist | Optimization | Yes |
| Clarity | Polymath | Corruption | Yes |
| Corruption | Enculted | Clarity | Yes |

### Attribute Colors

Each attribute uses the accent color of its class UI theme. These colors appear on item tooltips, stat displays, and anywhere an attribute value is shown.

| Stat | Color Name | RGB |
|---|---|---|
| Soul | Brown | `(0.65, 0.45, 0.25)` |
| Interface | Cyan | `(0.3, 0.85, 1.0)` |
| Orthodoxy | Ivory | `(0.95, 0.92, 0.8)` |
| Deviation | Red | `(0.9, 0.25, 0.2)` |
| Optimization | Steel blue | `(0.55, 0.78, 0.85)` |
| Ingenuity | Olive green | `(0.7, 0.85, 0.35)` |
| Clarity | Yellow | `(0.95, 0.9, 0.3)` |
| Corruption | Purple | `(0.78, 0.35, 0.85)` |

These match the `accent` field in each class's `UIThemeConfig` resource (`game/resources/ui/theme_*.tres`).

### Soul & Interface — Derived Stats

Soul and Interface do not roll on items. They are calculated from the average of the character's three team stats (the three class stats belonging to the same origin).

- **Human → Soul** = average of Orthodoxy, Ingenuity, Corruption
- **Cyborg → Interface** = average of Deviation, Optimization, Clarity

This means Soul/Interface rise naturally as you gear well for your team. They are never chased directly — they are a byproduct of coherent gearing.

## Origin Class Scaling (Human / Cyborg)

Human and Cyborg are generalist origin classes — the "easy to understand" entry point. They don't care about individual attributes. Everything rolls up into one number.

- **Own team stats** (all 3) → contribute equally to Soul / Interface
- **Opposing team stats** (all 3) → averaged into a single negative value

Because both the positive and negative sides are averaged, origin classes are forgiving. A single bad stat on an item barely hurts. A single good stat barely helps. The tradeoff is lower peak power compared to specialized classes.

### Example — Human

| Stat | Scaling | Reason |
|---|---|---|
| Orthodoxy | equal | Feeds Soul (averaged) |
| Ingenuity | equal | Feeds Soul (averaged) |
| Corruption | equal | Feeds Soul (averaged) |
| Deviation | negative (averaged) | Opposing team (averaged with Optimization + Clarity) |
| Optimization | negative (averaged) | Opposing team (averaged with Deviation + Clarity) |
| Clarity | negative (averaged) | Opposing team (averaged with Deviation + Optimization) |

## Specialized Class Scaling

For any specialized class:

- **Own class's stat** → full scaling (1x)
- **Other two same-origin class stats ("team stats")** → partial scaling (initial target: 0.25x, subject to tuning)
- **Opposing class's stat** → negative scaling (target range: -0.25x to -0.5x)
- **Opposite origin's non-opposing stats** → no benefit (0x)

### Example — Gentleman

| Stat | Scaling | Reason |
|---|---|---|
| Orthodoxy | 1x | Own class |
| Ingenuity | 0.25x | Same origin, non-opposing |
| Corruption | 0.25x | Same origin, non-opposing |
| Deviation | negative | Opposing class |
| Interface, Optimization, Clarity | 0x | Opposite origin |

### Team Stat Scaling — Skill Tree Mechanic

By default, the team stat contribution scales off the **lowest** of the three team stats. This forces balanced gearing across all three.

Skill tree nodes can change this calculation:

| Node | Scales Off | Gearing Effect |
|---|---|---|
| (default) | Lowest of 3 team stats | Must balance all three — every item matters |
| Balanced | Average of 3 team stats | Tolerates some lopsidedness |
| Focused | Highest of 3 team stats | Go all-in on main stat, ignore the others |

Each option completely reframes what "good gear" means for the same class. This is a build-defining choice. Origin classes (Human/Cyborg) always use the average — the skill tree mechanic is for specialized classes only.

## Item Stat Budget

Items roll a fixed total stat budget distributed across attributes. The distribution — not just the total — determines the item's value for any given build.

Example: an item with 10 total stat points might roll:

| Distribution | Main Stat | Team Stat | Opposing |
|---|---|---|---|
| Clean roll | 5 | 4 | 1 |
| Hybrid roll | 3 | 3 + 3 | 1 |
| Lopsided roll | 7 | 1 | 2 |

A hybrid 3/3/3 roll could be better than a clean 5/4/1 for a character using the "Lowest" team stat scaling — because raising your weakest team stat matters more than stacking your main. The same item is worse under "Focused" scaling. Itemization decisions shift entirely based on skill tree choices.

## Class-Specific Stat Functions

Each class's main stat affects damage, but also has a unique mechanical function tied to the class fantasy:

| Stat | Class | Damage Scaling | Special Function |
|---|---|---|---|
| Orthodoxy | Gentleman | Yes | TBD |
| Deviation | Forged | Yes | Allows attaching more limbs |
| Optimization | Automaton | Yes | TBD |
| Ingenuity | Survivalist | Yes | TBD |
| Clarity | Polymath | Yes | TBD |
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
- **Class-specific stat functions** for Orthodoxy, Optimization, Ingenuity, Clarity, Corruption.
- **Tooltip design**: show stats the character scales off (positive or negative); hide irrelevant 0x stats to reduce noise.
- What does **Soul** govern beyond being a derived stat? Candidates: willpower, resilience, HP, CC resistance.
- What does **Interface** govern beyond being a derived stat? Candidates: precision, latency, cooldown reduction, cast speed.
- **Resource system** for each class — 1 unique resource per class (8 total). See individual class pages.
