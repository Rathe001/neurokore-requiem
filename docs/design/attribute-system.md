# Attribute System

> Status: Core system + all six specialist tier perks implemented (Exile, Amalgamation, Drone Swarm, IED, Telekinesis, Doomsayer). Origin-class tier perks, team stat scaling multipliers, visual metamorphosis, and NPC reactions are still TBD.

## Core Philosophy

- **Class = verbs**, **attributes = modifiers**. Stats shape *how* you do things; classes define *what* you can do. Stats never gate access to abilities.
- **Baseline identity is guaranteed.** Off-stat builds distort your playstyle — they don't replace it.
- Supports specialization (stack primary), hybridization (team stats), and off-path experimentation (opposing stats with friction).

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

Each attribute maps to a behavioral axis. These are design intent — mechanical implementations are TBD.

| Stat | Axis |
|---|---|
| Orthodoxy | Reliability |
| Deviation | Throughput (chaotic) |
| Optimization | Throughput (systemic) |
| Ingenuity | Control |
| Clarity | Reliability / foresight |
| Ambition | Risk / reward |

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

### Relationship Color Overlay

The base stat color is identity (always visible). A **relationship overlay** (ring / highlight / icon) layers on top to communicate the stat's relationship to the current class — never replaces the base color.

| Relationship | Overlay | Meaning |
|---|---|---|
| Primary (own class) | Bright green | Full efficiency |
| Team (same origin) | Dark green | Partial scaling |
| Opposing (other origin) | Red | Interference + distortion |

Origin classes use balance-state coloring instead: green (stable) / yellow (drifting near threshold) / red (about to lose origin perks).

### Soul & Interface — Derived Stats

Calculated from the average of the character's three team stats — never rolled directly. They represent identity coherence, not raw power.

- **Soul** (Analog) = avg(Orthodoxy, Ingenuity, Ambition) → stability / sustain / momentum
- **Interface** (Cyborg) = avg(Deviation, Optimization, Clarity) → speed / responsiveness / cooldown smoothing

---

## Attribute Relationships

Each stat falls into one of **three categories** relative to a player's class. All tier thresholds are multiples of 33% — every tier costs another third of your stat budget.

| Relationship | Who | Scaling | Specialist Tiers | Origin Tiers |
|---|---|---|---|---|
| **Primary** | Own class stat | Full (1x) | T1=33%, T2=66%, T3=99% | n/a (origins have no primary) |
| **Team** | Other two stats from same origin | Partial (~0.25x) | T1=33%, T2=66%, T3=— | T1=33%, T2=66%, T3=— |
| **Opposing** | All three stats from other origin | Interference + distortion | T1=—, T2=—, T3=— | T1=33%, T2=—, T3=— |

> T3 for team / opposing is unreachable in practice — getting one stat to 66% leaves only 34% for everything else. Specialists are sentinel-locked out of opposing trees entirely; origins can dabble into opposing T1 (≥33%). The "—" entries are sentinel thresholds (>1.0) in code.

### Opposing Stats — Resistance Model

Opposing stats don't apply a flat negative — they use a resistance model: **efficiency reduction** (points contribute less), **behavioral distortion** (mechanics warp, not just weaken), **conditional penalties** (situational), and **conversion loss** (partial waste).

**Goal: friction, not failure.** A character heavily invested in opposing stats plays a harder, distorted version of their class — not a broken one.

### Team Stat Scaling — Skill Tree Mechanic

By default, the team stat contribution scales off the **lowest** of the three team stats. This forces balanced gearing across all three.

Skill tree nodes can change this calculation:

| Node | Scales Off | Gearing Effect |
|---|---|---|
| (default) | Lowest of 3 team stats | Must balance all three — every item matters |
| Balanced | Average of 3 team stats | Tolerates some lopsidedness |
| Focused | Highest of 3 team stats | Go all-in on main stat, ignore the others |

Each option completely reframes what "good gear" means for the same class. Origin classes (Analog/Cyborg) always use the average — this mechanic is for specialized classes only.

---

## Origin Class Scaling (Analog / Cyborg)

Origin classes are casual-friendly: broad, forgiving scaling and lower variance.

- Scaling: average of 3 team stats → feeds Soul / Interface
- Opposing stats reduce efficiency (30-50%) but don't distort
- No specialized mechanics inherited — gains are blended and generalized
- Misaligned gearing (heavy opposing investment) stays functional, just suboptimal

### Origin Tier Perks (Balance-Gated)

Origin perks reward staying balanced — single rule: no stat may meet or exceed the cap. Same rule applies to team and opposing alike. Specific perks TBD.

| Tier | Cap | Vibe |
|---|---|---|
| 1 | No stat ≥ 66% | Almost free |
| 2 | No stat ≥ 50% | No single stat dominates |
| 3 | No stat ≥ 33% | Perfect 1-1-1 spread, exactly at cap |

An origin class that starts pushing a single stat loses origin perks but begins unlocking the matching specialized class's tier perks instead.

---

## Item Stat Budget

Items roll a fixed total stat budget distributed across attributes. The *distribution* matters as much as the total — a hybrid roll can outvalue a clean one depending on which team-stat-scaling node you've taken. Full item rules in [item-architecture.md](item-architecture.md).

### Discovery Moments

Items can push players across tier thresholds accidentally — a feature, not a bug. Threshold crossings get VFX + "Tier unlocked" message with immediate highlight of new options. No silent punishment, no unclear impact.

---

## Class-Specific Stat Functions

Each class's main stat affects damage and has a unique mechanical function tied to class fantasy.

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

Three tiers drive everything: talent tree access, tier perks, VFX metamorphosis, and NPC reactions. Each threshold is a multiple of 33% — every tier costs another third of your budget. Full threshold table is in [Attribute Relationships](#attribute-relationships) above.

Reachable specialist patterns are exactly three:

- **3-only** (99% in one stat) — pure specialist, true all-in
- **2-1-0** (66% main + 33% in one team stat) — moderate hybrid, two perk ladders
- **1-1-1** (33% × 3) — wide spread across own + both teams; no apex

T3 is "all-in" by design — getting one stat to 99% leaves only 1% for everything else. Tier access tracks live with gear: dropping below a threshold locks the tier and deactivates its nodes (points stay allocated, reactivate when threshold returns).

**Cross-class access for origins:** Origin classes (Analog/Cyborg) can dabble in opposing-origin tier perks at T1 only (≥33%). An Analog with 33%+ Optimization unlocks Drone Swarm I (2 drones). Specialists cannot reach opposing perks at all — those thresholds are sentinel-locked.

> **Code source of truth:** `TIERS_OWN`, `TIERS_TEAM_SPEC`, `TIERS_OPPOSING_SPEC`, `TIERS_TEAM_ORIGIN`, `TIERS_OPPOSING_ORIGIN`, and `ORIGIN_TIER_CAPS` in `attribute_state.gd`. Sentinel value `1.01` marks unreachable tiers.

### Talent Points

1 point per level (currently — target budget is ~20 at L100; cadence needs tuning). Each class tree is 8 × 3 = 24 nodes (144 total across six trees), so even a fully committed build can't fill one tree. Every tier is a meaningful "which nodes," never "can I even get here."

- Nodes cost 1 point each, only purchasable in unlocked tiers
- Gear-driven tier loss makes nodes dormant — points stay allocated, reactivate when threshold is met again
- Reallocation is free at any time

### Specialized Class Tier Perks

All six are implemented. Aggregates are additive across tiers (see `game/resources/perks/{stat}.tres` for authoring).

| Stat | Class | Perk | T1 → T2 → T3 |
|---|---|---|---|
| Orthodoxy | Count | **Exile** — hits curse target; +X% damage taken; auto-shot on expire | +10% → +20% → +40% |
| Deviation | Forged | **Amalgamation** — extra arm slots; LMB fires every weapon | +1 → +2 → +3 weapon slots |
| Optimization | Automaton | **Drone Swarm** — wandering hover drones auto-fire on enemies | 2 → 3 → 5 drones |
| Ingenuity | Survivalist | **Improvised Explosive Device** — toss prox trap on every LMB | 1 → 2 → 3 max active traps |
| Clarity | Polymath | **Telekinesis** — periodic psionic bolts grab + slam enemies | 1 → 2 → 4 bolts per trigger |
| Ambition | Enculted | **Doomsayer** — aura procs stun / charm / weaken on enemies | 5% → 10% → 20% per second; charms 1 → 2 → 3 |

**Gear swap confirmation:** When equipping an item would cross a breakpoint, a confirmation dialog shows exactly what changes. This is behind a Help Tooltips toggle for players who prefer to manage it themselves.

---

## Team Nodes

A separate, smaller talent tree (3 tiers × 4 nodes) that rewards **synergy across all three team stats** rather than depth in any single one. Provides QoL, consistency, and flow enhancements — never class-specific mechanics.

Tier access is gated by the *combined sum* of the three team stats:

| Tier | Combined Team Stat |
|---|---|
| 1 | 20% |
| 2 | 35% |
| 3 | 50% |

Strong early, plateaus hard. T3 is demanding (~30% per team stat) and the payoff is broad but not identity-defining. An optional **keystone** at very high investment is design space (TBD). Code source of truth: `TEAM_NODE_THRESHOLDS` in `attribute_state.gd`.

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

Combo appearances emerge naturally — a character at 45% Ambition and 42% Deviation shows mild ambition effects AND early machine-creep simultaneously. Breakpoint crossings get unique gain/loss VFX (gain plays second on simultaneous swaps).

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

---

## Implemented

- HP and resource pool max scale with contribution-weighted stat totals (primary 1.0x, team 0.25x, opposing 0.10x). Current values scale proportionally on gear swap. Code: `AttributeState.get_stat_bonus_hp()` / `get_stat_bonus_resource()`.
- Resource bars unlock per-class once that class's tier 1 is met (max 3 bars active).
- All six specialist tier perks (see table above).

## Open Questions

- **Tuning:** team stat scaling multiplier (~0.25x placeholder); tier breakpoints (need playtest); talent point cadence (currently 1/level → far above the ~20-point intended budget at L100).
- **Origin class tier perks** — what do balanced Analog / Cyborg unlock?
- **Class-specific stat functions** beyond damage scaling (Orthodoxy, Optimization, Ingenuity, Clarity, Ambition all marked TBD).
- **Opposing stat distortion specifics** — what literally distorts for each class? Needs per-class design.
- **Soul / Interface governance** — beyond being derived: candidates include willpower / resilience for Soul, precision / cooldown reduction for Interface.
- **Team nodes** — tier 1/2/3 specific bonuses; the optional keystone.
- **Node prerequisites** — tier-only access, or specific intra-tier dependencies?
- **Visual metamorphosis art pipeline** — mesh kits, shader channels, VFX layers per class.
- **Relationship overlay placement** — which UI surfaces (tooltips, stat bars, talents, sheet) get the overlay rings.
