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
| Clarity | Polymath | Ambition | Yes |
| Ambition | Enculted | Clarity | Yes |

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
| Ambition | Purple | `(0.78, 0.35, 0.85)` |

These match the `accent` field in each class's `UIThemeConfig` resource (`game/resources/ui/theme_*.tres`).

### Soul & Interface — Derived Stats

Soul and Interface do not roll on items. They are calculated from the average of the character's three team stats (the three class stats belonging to the same origin).

- **Human → Soul** = average of Orthodoxy, Ingenuity, Ambition
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
| Ambition | equal | Feeds Soul (averaged) |
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
| Ambition | 0.25x | Same origin, non-opposing |
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
| Ambition | Enculted | Yes | TBD |

These special functions are what make each stat feel different beyond raw numbers. A Forged stacking Deviation isn't just hitting harder — they're unlocking body modification slots.

## Stat Identity — Tier Perks & Visual Metamorphosis

As a character's stat distribution shifts, two things happen: they unlock **tier perks** (mechanical rewards) and their **appearance transforms** to reflect what they're becoming. Both are driven by the same breakpoints and are always in sync.

### Breakpoints

Tier thresholds are based on what percentage of total stats a single attribute represents:

| Threshold | Tier | Effect |
|---|---|---|
| < 40% | 0 | No perk, no visual change |
| 40–59% | 1 | First perk unlocked, subtle visual shift |
| 60–79% | 2 | Second perk, pronounced visual change |
| ≥ 80% | 3 | Full perk, dramatic transformation |

Perks are **not permanent** — they are maintained by meeting the threshold. Swapping gear that drops a stat below a breakpoint immediately loses the associated tier perk and visual changes. Gear decisions have real consequences beyond raw damage numbers.

**Gear swap confirmation:** When equipping an item would cross a breakpoint (up or down), a confirmation dialog shows exactly what changes — e.g. *"This change will cause Drones III → Drones II. + Curse I. Are you sure?"* This dialog is behind a **Help Tooltips** toggle in the accessibility menu for players who prefer to manage it themselves.

### Specialized Class Tier Perks

Each class stat has a unique perk that unlocks at each tier. These are the mechanical rewards for going deep into an identity:

| Stat | Class | Tier 1 (40%) | Tier 2 (60%) | Tier 3 (80%) |
|---|---|---|---|---|
| Orthodoxy | Gentleman | TBD | TBD | TBD |
| Deviation | Forged | Extra appendage slot | TBD | TBD |
| Optimization | Automaton | Additional drone | TBD | TBD |
| Ingenuity | Survivalist | TBD | TBD | TBD |
| Clarity | Polymath | TBD | TBD | TBD |
| Ambition | Enculted | Tier 1 curse | TBD | TBD |

### Origin Class Tier Perks

Human and Cyborg are rewarded for **balance** — not letting any single stat dominate. Their tier perk thresholds are inverted: they maintain perks as long as no single stat exceeds a threshold.

| Threshold | Tier | Condition |
|---|---|---|
| No stat ≥ 40% | 3 | Perfectly balanced — full origin perk |
| No stat ≥ 60% | 2 | Mostly balanced |
| No stat ≥ 80% | 1 | Slightly lopsided |
| Any stat ≥ 80% | 0 | Fully consumed — origin perk lost |

This means origin class players who start drifting toward a single stat will lose origin perks but begin gaining the specialized class's tier perks instead. A Human who pushes Ambition past 40% starts unlocking Enculted perks while losing Human balance perks — the tradeoff is explicit and visible.

### Cross-Class Perk Unlocking

**Any class can unlock any stat's tier perks** if they hit the breakpoint — the system does not care which class was chosen. A Human stacking Optimization past 50% gets an Automaton drone. A Gentleman deep in Deviation starts growing mechanical appendages.

This is possible but *difficult* for off-origin stats because of negative scaling. A Human stacking Optimization is fighting averaged negative scaling the entire way — every point of Optimization costs more than it would for a Cyborg. The perk is the reward for paying that cost.

It should be possible but extremely demanding to maintain a high tier perk in one stat while unlocking a perk in another. The fixed stat budget on items means pushing one stat high enough necessarily pulls others down. Multi-perk builds are the ultimate expression of build mastery.

### Visual Metamorphosis

Character appearance is **dynamically driven by stat distribution**. Each stat contributes its own visual channel independently:

- **Modular mesh parts** — appendages, drones, ambition growths, mechanical plating. Swapped/added at tier thresholds.
- **Shader-driven blending** — skin pallor, vein visibility, metallic creep, emissive glow. Driven continuously by stat percentages for smooth transitions between breakpoints.
- **Particle/VFX layers** — ambition wisps, electric arcing, heat distortion. Intensity scales with stat %.

Because each stat drives its own visual channel, **combo appearances emerge naturally**. A character at 45% Ambition and 42% Deviation shows mild ambition effects AND early machine-creep simultaneously. Opposing stat combos — Orthodoxy and Deviation stacked together — create a character visually at war with themselves.

Origin class players who maintain balance look intentionally neutral — no single visual channel dominates. The moment they start drifting, the character model tells that story.

### Threshold VFX

When a breakpoint is crossed, a class-specific VFX plays on the character model:

- **Perk gained** — unique "gained" effect per class (e.g. ambition tendrils coalescing, mechanical plating locking into place)
- **Perk lost** — unique "lost" effect per class (e.g. tendrils receding, plating fracturing away)

If a single gear swap causes both a loss and a gain (e.g. dropping Drones III while gaining Curse I), the effects play in sequence: **lost first, gained second**. This keeps the cause-and-effect readable.

### Character Sheet — Stat Distribution

The character sheet displays a **stat distribution visualization** showing each attribute's percentage of total stats. This replaces the morality plane (see [Morality System](morality-system.md)) as the primary identity readout.

The distribution view should make current tier perks and proximity to breakpoints visible at a glance. When a stat combination has a recognized identity (e.g. high Ambition + moderate Deviation), the character sheet can display a **combo description** — a short flavor line describing what the character has become.

### NPC Identity Reactions

Key NPCs — reps, vendors, bosses, and gate encounters — can react to the player's **dominant stat identity** rather than their chosen class. This is not a universal system (8 reaction profiles on every NPC would be an authoring nightmare) but a selective tool used on important characters to dynamically tailor the story to player state.

An Enculted who stacks Orthodoxy gets treated like a Gentleman by NPCs who care about identity. A Human who has visibly drifted into Ambition territory gets reactions appropriate to what they've become, not what they started as. The rep companion is the most sensitive to this — they react to identity drift as a personal betrayal or validation depending on alignment.

## Opposing Stat Philosophy

Opposing stats should feel **wrong and disappointing** on an otherwise great item, but not cripple the character unless deliberately stacked. The negative multiplier (-0.25x to -0.5x) is a tax, not a death sentence.

Design space exists for **build-around uniques** that require stacking your opposing stat and scale off it — forcing the player into "wrong" gear for a powerful payoff. A Gentleman wearing Deviation-heavy gear is narratively compelling and mechanically novel.

## Design Intent

Items carry moral weight. A Forged player finding Orthodoxy-heavy gear is actively hurt by it — reinforcing character identity at the itemization level. Combined with the tier perk system and visual metamorphosis, item drops feel meaningful beyond raw numbers — every piece of gear is a statement about who you're becoming.

## Open Questions

- Exact **team stat scaling multiplier** (0.25x is a starting point, needs playtesting).
- Exact **negative scaling multiplier** (-0.25x to -0.5x range, needs playtesting).
- Exact **tier perk breakpoints** (40/60/80% is the starting design, needs playtesting).
- **Class-specific stat functions** for Orthodoxy, Optimization, Ingenuity, Clarity, Ambition.
- **Tier perks** for most classes beyond tier 1 — see tier perk table above.
- **Origin class tier perks** — what does balanced Human/Cyborg actually unlock?
- **Tooltip design**: show stats the character scales off (positive or negative); hide irrelevant 0x stats to reduce noise.
- What does **Soul** govern beyond being a derived stat? Candidates: willpower, resilience, HP, CC resistance.
- What does **Interface** govern beyond being a derived stat? Candidates: precision, latency, cooldown reduction, cast speed.
- **Resource system** for each class — 1 unique resource per class (8 total). See individual class pages.
- **Visual metamorphosis art pipeline** — modular mesh kits per stat, shader channels, VFX layers. Needs concept work per class.
