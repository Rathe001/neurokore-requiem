# Attribute System

## Core Philosophy

- **Class = verbs**, **attributes = modifiers**. Stats shape *how* you do things; classes define *what* you can do. Stats never gate access to abilities.
- **Baseline identity is guaranteed.** Off-stat builds distort your playstyle — they don't replace it.
- Supports specialization (stack primary), hybridization (kore stats), and off-path experimentation (opposing stats with friction).

> **Kore.** Stats sharing your origin are your **kore** — the Analog kore is ORT/ING/AMB; the Cyborg kore is DEV/OPT/CLA. Named for the game's title (Neurokore). Stats from the opposite kore are "opposing" and create distortion.

---

## The 8 Attributes

Six **class stats** roll on items. Two **origin stats** are derived, not rolled.

| Stat | Short | Class | Pairwise Flavor | Rollable |
|---|---|---|---|---|
| Soul | SOU | Analog | — | No (derived) |
| Interface | ITF | Cyborg | — | No (derived) |
| Orthodoxy | ORT | Count | Deviation | Yes |
| Deviation | DEV | Forged | Orthodoxy | Yes |
| Optimization | OPT | Automaton | Ingenuity | Yes |
| Ingenuity | ING | Survivalist | Optimization | Yes |
| Clarity | CLA | Polymath | Ambition | Yes |
| Ambition | AMB | Enculted | Clarity | Yes |

> **Note on pairwise opposition:** The "Pairwise Flavor" column reflects thematic tension between paired stats (Orthodoxy/Deviation, Optimization/Ingenuity, Clarity/Ambition). This is flavor and lore — it is **not a mechanical category**. All three stats from the opposing origin are treated identically by the system.

### Gameplay Axes

Each attribute maps to a behavioral axis.

| Stat | Axis |
|---|---|
| Orthodoxy | Reliability |
| Deviation | Throughput (chaotic) |
| Optimization | Throughput (systemic) |
| Ingenuity | Control |
| Clarity | Reliability / foresight |
| Ambition | Risk / reward |

### Attribute Colors

Each attribute has an identity colour shared with its class UI theme. The *colour* is the design intent; the precise RGB lives in the theme resources.

| Stat | Identity |
|---|---|
| Soul | Brown |
| Interface | Cyan |
| Orthodoxy | Ivory |
| Deviation | Red |
| Optimization | Steel blue |
| Ingenuity | Olive green |
| Clarity | Yellow |
| Ambition | Purple |

### Relationship Color Overlay

The base stat color is identity (always visible). A **relationship overlay** (ring / highlight / icon) layers on top to communicate the stat's relationship to the current class — never replaces the base color.

| Relationship | Overlay | Meaning |
|---|---|---|
| Primary (own class) | Bright green | Full efficiency |
| Kore (same origin) | Dark green | Partial scaling |
| Opposing (other origin) | Red | Interference + distortion |

Origin classes use balance-state coloring instead: green (stable) / yellow (drifting near threshold) / red (about to lose origin perks).

### Soul & Interface — Derived Stats

Calculated from the average of the character's three kore stats — never rolled directly. They represent identity coherence, not raw power.

- **Soul** (Analog) — averaged from the three Analog kore stats; vibe is stability / sustain / momentum.
- **Interface** (Cyborg) — averaged from the three Cyborg kore stats; vibe is speed / responsiveness / cooldown smoothing.

Both stats' load-bearing mechanical role beyond identity is still open design.

---

## Attribute Relationships

Each stat falls into one of **three categories** relative to a player's class. Tier thresholds are evenly spaced so each tier costs the same fraction of the player's stat budget — every tier is a real commitment.

| Relationship | Who | Scaling | Tier reach |
|---|---|---|---|
| **Primary** | Own class stat | Full | Specialists reach all three tiers; origins have no primary |
| **Kore** | Other two stats from same origin | Partial | Both can reach low tiers, but specialists alone push deeper |
| **Opposing** | All three stats from other origin | Interference + distortion | Origins can dabble at the lowest tier; specialists are locked out entirely |

### Opposing Stats — Resistance Model

Opposing stats don't apply a flat negative — they use a resistance model: **efficiency reduction** (points contribute less), **behavioral distortion** (mechanics warp, not just weaken), **conditional penalties** (situational), and **conversion loss** (partial waste).

**Goal: friction, not failure.** A character heavily invested in opposing stats plays a harder, distorted version of their class — not a broken one.

### Kore Stat Scaling — Skill Tree Mechanic

By default, the kore stat contribution scales off the **lowest** of the three kore stats. This forces balanced gearing across all three.

Skill tree nodes can change this calculation:

| Node | Scales Off | Gearing Effect |
|---|---|---|
| (default) | Lowest of 3 kore stats | Must balance all three — every item matters |
| Balanced | Average of 3 kore stats | Tolerates some lopsidedness |
| Focused | Highest of 3 kore stats | Go all-in on main stat, ignore the others |

Each option completely reframes what "good gear" means for the same class. Origin classes (Analog/Cyborg) always use the average — this mechanic is for specialized classes only.

---

## Origin Class Scaling (Analog / Cyborg)

Origin classes are casual-friendly: broad, forgiving scaling and lower variance.

- Scaling: average of 3 kore stats → feeds Soul / Interface
- Opposing stats reduce efficiency but don't distort behavior
- No specialized mechanics inherited — gains are blended and generalized
- Misaligned gearing (heavy opposing investment) stays functional, just suboptimal

### Origin Tier Perks (Balance-Gated)

Origin perks reward staying balanced — single rule: no stat may meet or exceed the cap, applied uniformly across kore and opposing.

- Tier 1 — generous cap (most builds qualify).
- Tier 2 — tighter; no stat dominates.
- Tier 3 — strict; only the perfect even spread qualifies.

An origin class that starts pushing a single stat loses origin perks but begins unlocking the matching specialized class's tier perks instead.

---

## Item Stat Budget

Items roll a fixed total stat budget distributed across attributes. The *distribution* matters as much as the total — a hybrid roll can outvalue a clean one depending on which kore-stat-scaling node you've taken. Full item rules in [item-architecture.md](item-architecture.md).

### Discovery Moments

Items can push players across tier thresholds accidentally — a feature, not a bug. Threshold crossings get VFX + "Tier unlocked" message with immediate highlight of new options. No silent punishment, no unclear impact.

---

## Class-Specific Stat Functions

Each class's main stat scales damage and has a unique mechanical function tied to class fantasy. Most non-damage functions are still TBD.

| Stat | Class | Damage Scaling | Special Function |
|---|---|---|---|
| Orthodoxy | Count | Yes | TBD |
| Deviation | Forged | Yes | Allows attaching more limbs |
| Optimization | Automaton | Yes | TBD |
| Ingenuity | Survivalist | Yes | TBD |
| Clarity | Polymath | Yes | TBD |
| Ambition | Enculted | Yes | TBD |

---

## Stat Identity — Tier Perks & Visual Metamorphosis

As a character's stat distribution shifts, two things happen: they unlock **tier perks** (mechanical rewards) and their **appearance transforms**. Both are driven by the same breakpoints and are always in sync.

### Breakpoints (3 tiers)

Three tiers drive everything: talent tree access, tier perks, VFX metamorphosis, and NPC reactions. Each threshold costs another even fraction of the player's stat budget — every tier is a meaningful commitment, not a minor checkpoint.

Reachable specialist patterns are exactly three:

- **All-in on primary** — pure specialist, true single-axis build.
- **Primary + one kore** — moderate hybrid, two perk ladders open.
- **Even spread** — wide across primary + both kore stats; no apex.

Tier 3 is "all-in" by design — reaching it leaves nothing for any other stat. Tier access tracks live with gear: dropping below a threshold locks the tier and deactivates its nodes (points stay allocated, reactivate when threshold returns).

**Cross-class access for origins:** Origin classes (Analog/Cyborg) can dabble in opposing-origin tier perks at Tier 1 only. An Analog with enough Optimization could unlock Drone Swarm I. Specialists cannot reach opposing perks at all.

### Talent Points

One point per level, with a player budget far smaller than the total node count. Each class tree is large enough that even a fully committed build can't fill it — every tier is a meaningful "which nodes," never "can I even get here."

- Nodes cost 1 point each, only purchasable in unlocked tiers
- Gear-driven tier loss makes nodes dormant — points stay allocated, reactivate when threshold is met again
- Reallocation is free at any time

### Specialized Class Tier Perks

Each specialised class has a signature perk ladder named for the class identity. The ladder gates the class's defining mechanic — three tiers of escalation built around one fantasy.

| Stat | Class | Perk Identity |
|---|---|---|
| Orthodoxy | Count | **Exile** — hits curse the target; cursed enemies take amplified damage; on expire the player auto-fires a heavy retribution shot |
| Deviation | Forged | **Amalgamation** — extra arm slots; LMB fires every equipped weapon |
| Optimization | Automaton | **Drone Swarm** — orbiting hover drones auto-fire on enemies |
| Ingenuity | Survivalist | **Improvised Explosive Device** — attacks toss prox traps at the cursor |
| Clarity | Polymath | **Telekinesis** — periodic psionic beams lift enemies and slam them for AoE |
| Ambition | Enculted | **Doomsayer** — aura that converts enemies into a player-friendly cult and (with the Aura of Dread talent) damages the rest |

**Gear swap confirmation:** When equipping an item would cross a breakpoint, a confirmation dialog shows exactly what changes. This is behind a Help Tooltips toggle for players who prefer to manage it themselves.

---

## Kore Nodes

A separate, smaller talent tree (3 tiers) that rewards **synergy across all three kore stats** rather than depth in any single one. Provides QoL, consistency, and flow enhancements — never class-specific mechanics.

Tier access is gated by the *combined sum* of the three kore stats. Strong early, plateaus hard. The top tier is demanding and the payoff is broad but not identity-defining. An optional **keystone** at very high investment is design space.

---

## Uniques Design Space

Unique items can bend system rules. Types:

| Type | Effect |
|---|---|
| Resistance reducers | Lower the friction cost of opposing stats |
| Stat converters | Redirect opposing stat points toward partial benefit |
| Cross-synergy enablers | Create unusual synergies between normally unrelated stats |
| Rare inversion effects | Build-around mechanics that require the "wrong" stats |

**Rule:** Uniques never allow full efficiency parity with the correct class. Off-class builds enabled by uniques should feel powerful and novel — not interchangeable with a proper build.

---

## Off-Class Builds

Builds that heavily invest in opposing stats or cross-origin trees should feel:

- **Viable but inefficient** — functional in the hands of a skilled player
- **Mechanically distinct** — the distortion creates a genuinely different play experience
- **Thematically resonant** — a Count stacking Deviation is a character at war with themselves

They should not feel:
- Optimal (specialization always wins at extremes)
- Clean (friction is part of the identity)
- Interchangeable with a proper class build

---

## Visual Metamorphosis

Character appearance is dynamically driven by stat distribution. Each stat contributes its own visual channel:

- **Modular mesh parts** at tier thresholds (appendages, drones, plating)
- **Shader blending** driven by stat % (skin pallor, vein visibility, metallic creep, emissive glow)
- **Particle/VFX layers** scaling with stat % (ambition wisps, electric arcing, heat distortion)

Combo appearances emerge naturally — a character partway into Ambition AND Deviation shows mild ambition effects AND early machine-creep simultaneously. Breakpoint crossings get unique gain/loss VFX (gain plays second on simultaneous swaps).

---

## Character Sheet & NPC Reactions

The character sheet displays a **stat distribution visualization** showing each attribute's share of total stats, current tier perks, and proximity to breakpoints. When a stat combination has a recognized identity, the sheet shows a **combo description** — a short flavor line describing what the character has become.

Key NPCs (reps, vendors, bosses, gate encounters) can react to the player's dominant stat identity rather than their chosen class. An Enculted who stacks Orthodoxy gets treated like a Count. An Analog who has visibly drifted into Ambition territory gets reactions appropriate to what they've become. The rep companion is the most sensitive to this.

---

## Design Goals

1. Stats modify behavior, not access to abilities
2. Friction > punishment — opposing stats distort, they don't break
3. Balance is a valid playstyle (origin classes)
4. Specialization always wins at extremes
5. UI must communicate system truth instantly — base color = stat identity, overlay = relationship
6. Players can experiment without bricking builds — free reallocation, no dead ends
