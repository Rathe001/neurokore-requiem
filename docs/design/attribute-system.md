# Attribute System

> Status: Design phase — not yet implemented.

Each of the 8 classes maps to a moral attribute. Items roll these stats, and characters scale off them based on their class. Think Pokemon type matchups, but grounded in the morality system.

## The 8 Attributes

Six **class stats** roll on items. Two **origin stats** are derived, not rolled.

| Stat | Short | Class | Opposes | Rollable |
|---|---|---|---|---|
| Soul | SOU | Analog | Interface | No (derived) |
| Interface | ITF | Cyborg | Soul | No (derived) |
| Orthodoxy | ORT | Gentleman | Deviation | Yes |
| Deviation | DEV | Forged | Orthodoxy | Yes |
| Optimization | OPT | Automaton | Ingenuity | Yes |
| Ingenuity | ING | Survivalist | Optimization | Yes |
| Clarity | CLA | Polymath | Ambition | Yes |
| Ambition | AMB | Enculted | Clarity | Yes |

### Attribute Colors

Each attribute uses the accent color of its class UI theme. These colors appear on item tooltips, stat displays, and anywhere an attribute value is shown.

| Stat | Short | Color Name | RGB |
|---|---|---|---|
| Soul | SOU | Brown | `(0.65, 0.45, 0.25)` |
| Interface | ITF | Cyan | `(0.3, 0.85, 1.0)` |
| Orthodoxy | ORT | Ivory | `(0.95, 0.92, 0.8)` |
| Deviation | DEV | Red | `(0.9, 0.25, 0.2)` |
| Optimization | OPT | Steel blue | `(0.55, 0.78, 0.85)` |
| Ingenuity | ING | Olive green | `(0.7, 0.85, 0.35)` |
| Clarity | CLA | Yellow | `(0.95, 0.9, 0.3)` |
| Ambition | AMB | Purple | `(0.78, 0.35, 0.85)` |

These match the `accent` field in each class's `UIThemeConfig` resource (`game/resources/ui/theme_*.tres`).

### Soul & Interface — Derived Stats

Soul and Interface do not roll on items. They are calculated from the average of the character's three team stats (the three class stats belonging to the same origin).

- **Analog → Soul** = average of Orthodoxy, Ingenuity, Ambition
- **Cyborg → Interface** = average of Deviation, Optimization, Clarity

This means Soul/Interface rise naturally as you gear well for your team. They are never chased directly — they are a byproduct of coherent gearing.

## Origin Class Scaling (Analog / Cyborg)

Analog and Cyborg are generalist origin classes — the "easy to understand" entry point. They don't care about individual attributes. Everything rolls up into one number.

- **Own team stats** (all 3) → contribute equally to Soul / Interface
- **Opposing team stats** (all 3) → averaged into a single negative value

Because both the positive and negative sides are averaged, origin classes are forgiving. A single bad stat on an item barely hurts. A single good stat barely helps. The tradeoff is lower peak power compared to specialized classes.

### Example — Analog

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

Each option completely reframes what "good gear" means for the same class. This is a build-defining choice. Origin classes (Analog/Cyborg) always use the average — the skill tree mechanic is for specialized classes only.

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

Tier thresholds are based on what percentage of total stats a single attribute represents. Five tiers provide granular progression — cheap early dips, expensive deep commitments.

Thresholds vary based on the **relationship** between the player's class and the stat being checked:

- **Own class stat** — the stat that maps to your chosen class (e.g., Deviation for Forged). **No threshold required** — your own class tree is always fully unlocked. Your identity is guaranteed.
- **Team stats** — the other two stats from your origin (e.g., Optimization and Clarity for a Forged). Reduced thresholds — same-origin affinity.
- **Opposing stats** — the three stats from the other origin (e.g., Orthodoxy, Ingenuity, Ambition for a Forged). Increased thresholds — cross-origin friction.

**Specialized class thresholds (Forged, Automaton, Polymath, Survivalist, Gentleman, Enculted):**

| Tier | Own Class | Team Trees | Opposing Trees | Effect |
|---|---|---|---|---|
| 0 | — | < 10% | < 20% | No perk, no visual change |
| 1 | Free | 10% | 20% | Entry perk unlocked, faint visual hint |
| 2 | Free | 20% | 30% | Second perk, subtle visual shift |
| 3 | Free | 35% | 45% | Third perk, pronounced visual change |
| 4 | Free | 50% | 60% | Fourth perk, major transformation |
| 5 | Free | 70% | 80% | Full perk, dramatic transformation — deep all-in |

**Example — Forged (Cyborg):**
- Deviation tree: always fully unlocked (own class)
- Optimization, Clarity trees: team rates (10/20/35/50/70%)
- Orthodoxy, Ingenuity, Ambition trees: opposing rates (20/30/45/60/80%)

**Multi-tree budget math:** A Forged with 35% Optimization (team tier 3) + 20% Ambition (opposing tier 1) = 55% committed, 45% remaining for Deviation and other stats. Comfortable. That same Forged trying Ambition tier 3 (opposing, 45%) + Optimization tier 3 (team, 35%) = 80% committed — extremely tight but technically possible. Opposing tier 5 at 80% is nearly impossible (leaves 20% for 5 other stats) — an aspirational ceiling.

### Talent Points

Talent points are the standard progression currency. Players earn **1 talent point every 5 levels** and spend them on individual nodes within unlocked skill tree tiers. Stat thresholds (via gear) determine *which* tiers are accessible; talent points determine *which* nodes you take.

Each class tree has **4 nodes per tier × 5 tiers = 20 nodes**. Six class trees = **120 total nodes**. At max level 100, a player has 20 talent points — enough to exactly fill one full tree, or spread across several.

**Spending talent points:** Each node costs 1 talent point. Nodes can only be purchased in tiers the player has unlocked via stat thresholds. Higher-tier nodes may require prerequisite nodes in the tier below (tree-specific).

**Locked nodes:** Nodes in tiers that haven't met the stat threshold are visible but grayed out. If gear changes drop a stat below a threshold, nodes in that tier become **inactive** but the points remain allocated. The player can either re-gear to reactivate them or reallocate the points.

**Reallocation:** Talent points can be freely reassigned at any time (no cost, no cooldown). The constraint is the stat thresholds, not the points themselves. Points are a budget — thresholds are the gate.

**Example builds at level 100 (20 talent points):**

| Build | Stat Budget | Accessible Nodes | Points vs Nodes |
|---|---|---|---|
| Deep specialist (75% one stat) | 75% committed | 20 (one full tree) | 20/20 — fills exactly |
| Dual focus (40% + 25%) | 65% committed | 12 + 8 = 20 | 20/20 — tight but complete |
| Triple dip (25% + 25% + 15%) | 65% committed | 8 + 8 + 4 = 20 | 20/20 — spread thin |
| Wide (15%×4 + 20%×2) | 100% | 16 + 16 = 32 | 20/32 — forced to choose |

Wide builds have more accessible nodes than talent points, creating real choices. Deep builds can fill everything they unlock but sacrifice breadth. Both are viable — the tension is genuine.

### Skill Tree Access — Stat Gated

Each of the 6 rollable stats corresponds to a class's skill tree. The tree is divided into five sections, each with 4 talent nodes. Access is gated by the tier breakpoints above, with thresholds varying by relationship (own/team/opposing):

| Tier | Tree Access | Own Class | Team | Opposing | Nodes |
|---|---|---|---|---|---|
| 1 | First 1/5 | Free | 10% | 20% | 4 |
| 2 | First 2/5 | Free | 20% | 30% | 4 |
| 3 | First 3/5 | Free | 35% | 45% | 4 |
| 4 | First 4/5 | Free | 50% | 60% | 4 |
| 5 | Full tree | Free | 70% | 80% | 4 |

**Your own class tree is always fully unlocked.** A Forged always has access to all 20 Deviation nodes — identity is guaranteed. Team trees (Optimization, Clarity for a Forged) use reduced thresholds. Opposing trees (Orthodoxy, Ingenuity, Ambition) require more investment, and the stats themselves are harder to stack due to negative/zero scaling.

**Origin classes (Analog, Cyborg)** have no "own" class stat — all 6 trees use either team or opposing rates. Their 3 team trees (same-origin stats) use team thresholds; their 3 opposing trees use opposing thresholds. This makes origin classes natural generalists across their team trees.

**At any given tier level, 6 classes × 4 nodes = 24 possible choices.** A dual-focus build with two stats at tier 2+ sees at least 16 nodes to choose from. This is where build diversity lives — not just which stats to stack, but which nodes to take within the tiers you've unlocked.

**Talents panel (N key):** The talents panel shows all 6 class skill trees as horizontal rows, grouped by origin (Analog top, Cyborg bottom) with subtle tinted backgrounds (warm brown for Analog, cool cyan for Cyborg). Each row has:

- **Class name** (larger font) with **stat name + percentage** below it (smaller, muted)
- **Full-width progress bar** divided into 5 equal sections with tier markers
- **Skill node grid** (2×2 per tier) aligned beneath each bar section

The bar fill reflects the stat's share of total allocation from equipped gear. Unlocked tiers and nodes light up in the stat's color; locked tiers are grayed out. All rows share the same layout — the only visual difference is how far each bar fills and which tiers light up (determined by own/team/opposing thresholds). A note at the top clarifies that percentages reflect gear-based stat allocation.

**Example — level 100 Forged (Cyborg):** Dev 42%, Opt 28%, Cla 14%, Ort 8%, Ing 5%, Amb 3%

```
                              TALENTS
                       Talent Points: 20 / 20
          Percentages reflect share of total stat allocation from equipped gear

  ┌─ Analog (warm tint) ─────────────────────────────────────────────────────┐
  │                                                                           │
  │  Gentleman       [░░░░░░░░░|░░░░░░░░░|░░░░░░░░░|░░░░░░░░░|░░░░░░░░░░░] │
  │  Orthodoxy  8%    ·· ··     ·· ··     ·· ··     ·· ··     ·· ··         │
  │                   ·· ··     ·· ··     ·· ··     ·· ··     ·· ··         │
  │                                                                           │
  │  Survivalist     [░░░░░░░░░|░░░░░░░░░|░░░░░░░░░|░░░░░░░░░|░░░░░░░░░░░] │
  │  Ingenuity  5%    ·· ··     ·· ··     ·· ··     ·· ··     ·· ··         │
  │                   ·· ··     ·· ··     ·· ··     ·· ··     ·· ··         │
  │                                                                           │
  │  Enculted        [░░░░░░░░░|░░░░░░░░░|░░░░░░░░░|░░░░░░░░░|░░░░░░░░░░░] │
  │  Ambition   3%    ·· ··     ·· ··     ·· ··     ·· ··     ·· ··         │
  │                   ·· ··     ·· ··     ·· ··     ·· ··     ·· ··         │
  │                                                                           │
  └───────────────────────────────────────────────────────────────────────────┘

  ┌─ Cyborg (cool tint) ─────────────────────────────────────────────────────┐
  │                                                                           │
  │  Forged          [█████████████████████████████████████████|░░░░░░░░░░░] │
  │  Deviation 42%    ■■ ■■     ■■ ■■     ■■ ··     ■■ ··     ■■ ··  [12] │
  │                   ■■ ■■     ■■ ■■     ·· ··     ·· ··     ·· ··       │
  │                                                                           │
  │  Automaton       [████████████████████████████|░░░░░░░░░░░|░░░░░░░░░░░] │
  │  Optimization 28% ■■ ■■     ■■ ··     ·· ··     ·· ··     ·· ··   [5] │
  │                   ■■ ■■     ·· ··     ·· ··     ·· ··     ·· ··       │
  │                                                                           │
  │  Polymath        [██████████████|░░░░░░░░░░░░░░|░░░░░░░░░|░░░░░░░░░░░] │
  │  Clarity  14%     ■■ ··     ·· ··     ·· ··     ·· ··     ·· ··   [3] │
  │                   ■■ ··     ·· ··     ·· ··     ·· ··     ·· ··       │
  │                                                                           │
  └───────────────────────────────────────────────────────────────────────────┘

  Key:  ████ = bar fill       ░░░░ = bar empty
        ■■   = allocated node (talent point spent)
        ·· (in unlocked tier) = available node (can spend point here)
        ·· (in locked tier)   = locked node (tier threshold not met)
        |    = tier marker (equal fifths)
        [N]  = total points spent in this tree
```

In this example, 20 talent points are distributed across 32 accessible nodes — the player had to choose. Deviation (own, 12 pts): all 5 tiers open, T1–T2 full, cherry-picked from T3–T5. Optimization (team, 5 pts): T1 full, 1 point in T2. Clarity (team, 3 pts): 3 of 4 T1 nodes. Analog trees are fully locked — opposing thresholds need ≥20% and none reach that. Available-but-empty nodes show the player where they *could* spend points if they reallocate.

Tier access is **not permanent** — it is maintained by meeting the threshold. Swapping gear that drops a stat below a breakpoint immediately locks the associated tier and deactivates any talent nodes in it (the points stay allocated but dormant). Gear decisions have real consequences beyond raw damage numbers.

**Gear swap confirmation:** When equipping an item would cross a breakpoint (up or down), a confirmation dialog shows exactly what changes — e.g. *"This change will lock Forged T3 (2 active nodes). Unlock Enculted T1 (0 nodes). Are you sure?"* This dialog is behind a **Help Tooltips** toggle in the accessibility menu for players who prefer to manage it themselves.

### Specialized Class Tier Perks

Each class stat has a unique perk that unlocks at each tier. These are the mechanical rewards for going deep into an identity:

| Stat | Class | Tier 1 (15%) | Tier 2 (25%) | Tier 3 (40%) | Tier 4 (55%) | Tier 5 (75%) |
|---|---|---|---|---|---|---|
| Orthodoxy | Gentleman | TBD | TBD | TBD | TBD | TBD |
| Deviation | Forged | TBD | Extra appendage slot | TBD | TBD | TBD |
| Optimization | Automaton | TBD | Additional drone | TBD | TBD | TBD |
| Ingenuity | Survivalist | TBD | TBD | TBD | TBD | TBD |
| Clarity | Polymath | TBD | TBD | TBD | TBD | TBD |
| Ambition | Enculted | Tier 1 curse | TBD | TBD | TBD | TBD |

### Origin Class Tier Perks

Analog and Cyborg are rewarded for **balance** — not letting any single stat dominate. Their tier perk thresholds are inverted: they maintain perks as long as no single stat exceeds a threshold. Team stats (same origin) are tolerated at higher values; opposing stats (other origin) are penalized more harshly. Leaning into your own side is natural — crossing the line is not.

With 6 rollable stats summing to ~100%, a perfectly even distribution is ~16.7% each. The thresholds are designed around what's actually achievable within that budget:

| Tier | Team Stat Max | Opposing Stat Max | Condition |
|---|---|---|---|
| 0 | Any team stat ≥ 55% | Any opposing stat ≥ 45% | Too lopsided — all origin perks lost |
| 1 | No team stat ≥ 55% | No opposing stat ≥ 45% | Almost free |
| 2 | No team stat ≥ 45% | No opposing stat ≥ 35% | Easy with spread gearing |
| 3 | No team stat ≥ 35% | No opposing stat ≥ 25% | Moderate — needs intentional balance |
| 4 | No team stat ≥ 30% | No opposing stat ≥ 20% | Demanding — tight spread |
| 5 | No team stat ≥ 25% | No opposing stat ≥ 15% | Near-perfect balance. Aspirational ceiling. |

**Example — Analog:** Team stats are Orthodoxy, Ingenuity, Ambition. Opposing stats are Deviation, Optimization, Clarity. An Analog at tier 3 can have Ingenuity at 34% without losing balance perks, but if Deviation hits 26%, tier 3 drops. The message: leaning into your own side is tolerated, drifting toward the other side is not.

**The tradeoff is explicit:** Origin class players who start pushing a single stat will lose origin perks but begin gaining the specialized class's tier perks instead. An Analog who pushes Ambition past 20% (opposing tier 1 for a specialized class) starts unlocking Enculted tree access. At the same time, if Ambition exceeds 55%, all origin perks are lost. The player is choosing to specialize — the system reflects that.

### Cross-Class Perk Unlocking

**Any class can unlock any stat's skill tree** if they hit the breakpoint — the system does not care which class was chosen. An Analog stacking Optimization past 20% (team rate) gets access to Automaton tier 1. A Gentleman pushing Deviation past 30% (opposing rate) starts growing mechanical appendages.

This is possible but *difficult* for off-origin stats because of both higher thresholds and negative scaling. An Analog stacking Optimization is fighting averaged negative scaling *and* opposing-rate thresholds the entire way — every point of Optimization costs more than it would for a Cyborg. The tree access is the reward for paying that cost.

It should be possible but extremely demanding to reach deep tiers in multiple trees. The fixed stat budget on items means pushing one stat high enough necessarily pulls others down. Multi-tree builds are the ultimate expression of build mastery — and talent point scarcity ensures even accessible tiers require meaningful node choices.

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

An Enculted who stacks Orthodoxy gets treated like a Gentleman by NPCs who care about identity. An Analog who has visibly drifted into Ambition territory (past the 15% tier 1 threshold) gets reactions appropriate to what they've become, not what they started as. The rep companion is the most sensitive to this — they react to identity drift as a personal betrayal or validation depending on alignment.

## Opposing Stat Philosophy

Opposing stats should feel **wrong and disappointing** on an otherwise great item, but not cripple the character unless deliberately stacked. The negative multiplier (-0.25x to -0.5x) is a tax, not a death sentence.

Design space exists for **build-around uniques** that require stacking your opposing stat and scale off it — forcing the player into "wrong" gear for a powerful payoff. A Gentleman wearing Deviation-heavy gear is narratively compelling and mechanically novel.

## Design Intent

Items carry moral weight. A Forged player finding Orthodoxy-heavy gear is actively hurt by it — reinforcing character identity at the itemization level. Combined with stat-gated skill trees, visual metamorphosis, and talent point allocation, item drops feel meaningful beyond raw numbers — every piece of gear is a statement about who you're becoming.

## Open Questions

- Exact **team stat scaling multiplier** (0.25x is a starting point, needs playtesting).
- Exact **negative scaling multiplier** (-0.25x to -0.5x range, needs playtesting).
- Exact **tier breakpoints** — own (free), team (10/20/35/50/70%), opposing (20/30/45/60/80%) — needs playtesting.
- **Class-specific stat functions** for Orthodoxy, Optimization, Ingenuity, Clarity, Ambition.
- **Tier perks** for most classes beyond tier 1 — see tier perk table above.
- **Origin class tier perks** — what does balanced Analog/Cyborg actually unlock?
- **Talent point cadence** — every 5 levels is a starting point (20 points at level 100). Needs tuning against max level and number of meaningful nodes.
- **Talent respec** — currently free reallocation. Should there be a cost, cooldown, or NPC requirement?
- **Node prerequisites** — do higher-tier nodes require specific lower-tier nodes, or just tier access?
- **Tooltip design**: show stats the character scales off (positive or negative); hide irrelevant 0x stats to reduce noise.
- What does **Soul** govern beyond being a derived stat? Candidates: willpower, resilience, HP, CC resistance.
- What does **Interface** govern beyond being a derived stat? Candidates: precision, latency, cooldown reduction, cast speed.
- **Resource system** for each class — 1 unique resource per class (8 total). See individual class pages.
- **Visual metamorphosis art pipeline** — modular mesh kits per stat, shader channels, VFX layers. Needs concept work per class.
