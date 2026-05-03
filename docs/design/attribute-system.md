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

Stat colors reflect the stat's identity. A second layer — the **relationship overlay** — communicates the stat's relationship to the current player class. These are overlaid (ring, highlight, icon) on top of the base color rather than replacing it.

| Relationship | Overlay Color | Meaning |
|---|---|---|
| Primary (own class) | Bright green | Full efficiency, core identity |
| Team (same origin) | Dark green | Partial scaling, easy thresholds |
| Opposing (other origin) | Red | Interference, distortion, high friction |

For **origin classes** (Analog / Cyborg), the overlay reflects balance state rather than alignment:

| Balance State | Overlay | Meaning |
|---|---|---|
| Stable | Green | All stats within healthy range |
| Drifting | Yellow | One stat approaching threshold edge |
| Destabilizing | Red | Stat distribution at risk of losing origin perks |

An **intensity layer** (dim → bright) reflects impact magnitude. An optional **motion layer** (steady → pulsing → jitter) reflects stability. These layers are additive — the base stat color is always visible beneath them.

> **Rule:** Colors represent system truth. They are never changed based on player preference.
>
> **Player intent** is expressed separately via an overlay system (highlight / ring / icon), not by recoloring stats. This lets the UI show both system truth (base color) and player intent (overlay) simultaneously without conflict.

### Soul & Interface — Derived Stats

Soul and Interface do not roll on items. They are calculated from the average of the character's three team stats.

- **Analog → Soul** = average of Orthodoxy, Ingenuity, Ambition
- **Cyborg → Interface** = average of Deviation, Optimization, Clarity

Soul and Interface are never chased directly — they rise as a byproduct of coherent gearing. They represent identity coherence rather than raw power.

| Origin Stat | Design Role | Behavioral Feel |
|---|---|---|
| Soul | Stability, sustain, consistency, momentum | The class holds together under pressure |
| Interface | Speed, responsiveness, cooldown smoothing | The class reacts faster and flows cleanly |

---

## Attribute Relationships

Each stat falls into one of **three categories** relative to a player's class:

| Relationship | Who | Scaling | Threshold |
|---|---|---|---|
| **Primary** | Own class stat | Full (1x) | Easier (12/25/40/55/72%) — class identity unlocks fast |
| **Team** | Other two stats from same origin | Partial (~0.25x) | Standard (20/40/60/75/90%) |
| **Opposing** | All three stats from other origin | Interference + distortion | Hard (30/50/70/85/95%) |

> There is no fourth category. All stats from the opposite origin are treated as opposing — pairwise naming is flavor, not a mechanical distinction.

### Opposing Stats — Resistance Model

Opposing stats do not apply a flat negative multiplier. Instead they use a **resistance model**:

- **Efficiency reduction** — opposing stat points contribute less than they would for the correct class
- **Behavioral distortion** — your primary stat's mechanics are warped, not just weakened. A Forged stacking Orthodoxy doesn't just hit softer — their Deviation-powered mechanics behave differently, creating unexpected friction.
- **Conditional penalties** — situational interference that shows up under specific conditions (not always-on punishment)
- **Conversion loss** — a portion of the opposing stat is partially wasted or redirected rather than cleanly scaling

**Goal: friction, not failure.** Opposing stats create meaningful resistance without bricking a build. A character with significant opposing stat investment is playing a harder, distorted version of their class — not a broken one.

### Specialized Class Scaling

| Relationship | Example (Forged) | Scaling |
|---|---|---|
| Primary | Deviation | 1x |
| Team | Optimization, Clarity | ~0.25x (tuning TBD) |
| Opposing | Orthodoxy, Ingenuity, Ambition | Resistance + distortion |

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

Origin classes are designed to be **casual-friendly** with broad, forgiving scaling and lower variance outcomes.

- **Scaling source:** Average of 3 team stats → feeds Soul / Interface
- **Opposing stats:** All 3 opposing stats contribute reduced efficiency (30–50% of normal), not interference-based distortion
- **No specialized mechanics inherited:** Origin classes gain blended, generalized bonuses — not the class-specific mechanics of their team's specialized classes

### Misaligned Gearing

If an origin class player invests heavily in the wrong trio (opposing stats):
- They still gain balance perks at a reduced rate
- Derived stat efficiency drops 30–50%
- Overall payoff is weaker
- The character feels misaligned but remains functional

**Result: stable but suboptimal** — not invalid, but not optimal.

### Example — Analog

| Stat | Role | Effect |
|---|---|---|
| Orthodoxy | Team | Feeds Soul (averaged) |
| Ingenuity | Team | Feeds Soul (averaged) |
| Ambition | Team | Feeds Soul (averaged) |
| Deviation | Opposing | Reduced efficiency (30–50%), no distortion |
| Optimization | Opposing | Reduced efficiency (30–50%), no distortion |
| Clarity | Opposing | Reduced efficiency (30–50%), no distortion |

### Origin Class Tier Perks

Origin classes are rewarded for **balance** — their tier perks are maintained as long as no single stat dominates.

| Tier | Team Stat Max | Opposing Stat Max | Condition |
|---|---|---|---|
| 0 | Any team stat ≥ 55% | Any opposing stat ≥ 45% | Too lopsided — all origin perks lost |
| 1 | No team stat ≥ 55% | No opposing stat ≥ 45% | Almost free |
| 2 | No team stat ≥ 40% | No opposing stat ≥ 30% | Intentional balance |
| 3 | No team stat ≥ 30% | No opposing stat ≥ 20% | Tight spread — aspirational |

An origin class who starts pushing a single stat loses origin perks but begins gaining the specialized class's tier perks instead. The system reflects that they are choosing to specialize.

---

## Item Stat Budget

Items roll a fixed total stat budget distributed across attributes. The distribution — not just the total — determines the item's value for any given build.

Example: an item with 10 total stat points might roll:

| Distribution | Main Stat | Team Stat | Opposing |
|---|---|---|---|
| Clean roll | 5 | 4 | 1 |
| Hybrid roll | 3 | 3 + 3 | 1 |
| Lopsided roll | 7 | 1 | 2 |

A hybrid 3/3/3 roll could be better than a clean 5/4/1 for a character using the "Lowest" team stat scaling — because raising your weakest team stat matters more than stacking your main. The same item is worse under "Focused" scaling. Itemization decisions shift entirely based on skill tree choices.

### Discovery Moments

Items can push players across tier thresholds accidentally. This is a **feature** — an intentional source of build discovery. The system must make these moments:

- **Visible** — the player sees the change happening
- **Exciting** — a threshold crossing should feel like a reward, not a surprise tax
- **Understandable** — the player immediately knows what changed and why

**Feedback:** VFX + "Tier unlocked" message with immediate highlight of new options. No instant punishment. No unclear impact.

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

Three tiers drive everything: talent tree access, tier perks, VFX metamorphosis, and NPC reactions. Thresholds are based on what percentage of total stats a single attribute represents.

**Specialized class thresholds:**

| Tier | Own Class | Team Trees | Opposing Trees | Effect |
|---|---|---|---|---|
| 0 | — | < 25% | < 40% | No perk, no visual change |
| 1 | 12% | 25% | 40% | Entry perk, faint visual hint, resource bar unlocked |
| 2 | 25% | 40% | 55% | Second perk, moderate visual shift |
| 3 | 40% | 55% | 70% | Full perk, dramatic transformation |

> **Design note:** Primary stat tiers unlock significantly easier than team or opposing stats — class identity should feel immediate. Team requires moderate investment. Opposing demands heavy commitment. Thresholds are set so that unlocking 4+ class trees simultaneously is mathematically impossible (12+25+25+40 = 102% > 100%), enforcing a natural **3-tree cap**.

> **Tier 3 is exclusive:** Reaching tier 3 in any stat locks every other stat to tier 0 — no other perks anywhere. Tier 3 is a hard "all-in" commitment, not a bonus on top of mid-tier perks. If multiple stats meet their tier-3 threshold (rare but mathematically possible), the highest-percentage stat wins exclusivity. Tiers 1 and 2 still stack freely across stats.

> **Build patterns:**
> - **3-only:** Tier 3 in one stat, nothing elsewhere. Pure specialist — one large resource pool, one perk ladder, dramatic visual transformation.
> - **2-1-0:** 2 tiers in one class, 1 in another. Moderate hybrid — two resource pools.
> - **2-2-0 / 2-1-1:** Wider mid-tier spreads. Several small perk ladders, no apex perk.
> - **1-1-1:** 1 tier in each of 3 classes. Wide hybrid — three small resource pools.

**Cross-class access:** Any class can unlock any stat's tree by meeting that stat's threshold. An Analog pushing Optimization past the team threshold gets Automaton tier 1. A Count pushing Deviation past the opposing threshold starts unlocking Forged nodes — while also experiencing distortion. Tier access is not permanent: dropping below a threshold locks the tier and deactivates its nodes (points stay allocated but dormant).

> **Code source of truth:** Threshold values are defined in `game/scripts/systems/attribute_state.gd` — `TIERS_OWN`, `TIERS_TEAM`, `TIERS_OPPOSING`. Update there; this table documents the current values.

### Talent Points

Players earn **1 talent point per level**. At level 100: ~100 points (tuning TBD). Points are spent on individual nodes within unlocked talent tiers.

Each class tree: **8 nodes × 3 tiers = 24 nodes**. Six class trees = **144 total nodes**.

With 20 points at level 100, a fully committed build can't fill even one class tree (20 of 24). Every tier forces meaningful choices — the question is always "which nodes," not "can I even get here."

**Spending:** Each node costs 1 point. Nodes can only be purchased in unlocked tiers.

**Locked nodes:** If gear drops a stat below a threshold, nodes in that tier become inactive but points remain allocated. Re-gear to reactivate, or reallocate freely.

**Reallocation:** Free at any time. Points are a budget — thresholds are the gate.

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

A **separate talent tree** that rewards synergy across all three team stats rather than depth in any single one.

### Design Role

Team nodes sit between class nodes (deep identity) and origin scaling (broad baseline). They provide:
- QoL improvements
- Consistency bonuses
- Flow enhancements

They do **not** provide class-specific mechanics, outscale class nodes, or scale off a single stat.

### Structure

- **3 tiers** (matching talent tree depth)
- **4 nodes per tier** (smaller tree than class trees — supplementary, not identity-defining)
- **Combined threshold unlocks** — tier access is gated by the *sum* of all three team stats, not any individual stat
- **Additive bonuses** — effects are additive, not multiplicative

| Tier | Combined Team Stat | Design Type |
|---|---|---|
| 1 | 20% combined | QoL, minor consistency |
| 2 | 35% combined | Moderate flow improvements |
| 3 | 50% combined | Strong broad bonus; plateau hard after this |

> **Code source of truth:** `TEAM_NODE_THRESHOLDS` in `attribute_state.gd`. Values above document the current implementation.

### Power Curve

Team nodes are **strong early, plateau hard.** Tier 3 is achievable but demanding — reaching it means committing roughly 30% per team stat, leaving little room for anything else. The payoff is broad but not identity-defining.

### Optional: Team Keystones

At high combined investment, a **keystone** unlock may be available — broad and impactful, but still not class-defining. Details TBD.

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

Character appearance is dynamically driven by stat distribution. Each stat contributes its own visual channel independently:

- **Modular mesh parts** — appendages, drones, growths, mechanical plating. Added at tier thresholds.
- **Shader-driven blending** — skin pallor, vein visibility, metallic creep, emissive glow. Driven continuously by stat percentages.
- **Particle/VFX layers** — ambition wisps, electric arcing, heat distortion. Intensity scales with stat %.

Combo appearances emerge naturally. A character at 45% Ambition and 42% Deviation shows mild ambition effects AND early machine-creep simultaneously.

### Threshold VFX

When a breakpoint is crossed:
- **Perk gained** — unique effect per class (tendrils coalescing, plating locking into place)
- **Perk lost** — unique effect per class (tendrils receding, plating fracturing)

If a gear swap causes both a loss and a gain, effects play in sequence: **lost first, gained second**.

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

## Open Questions

- Exact **team stat scaling multiplier** (~0.25x is a starting point, needs playtesting).
- Exact **opposing stat interference mechanics** — what specifically distorts for each class? Needs design per class.
- Exact **tier breakpoints** — implemented as 3 tiers (see breakpoints table and `attribute_state.gd`), needs playtesting.
- **Team node specific bonuses** — what do tiers 1/2/3 actually grant?
- **Team node keystone** — what is the tier 3 high-investment reward?
- **Class-specific stat functions** for Orthodoxy, Optimization, Ingenuity, Clarity, Ambition.
- **Origin class tier perks** — what does balanced Analog/Cyborg actually unlock?
- **Talent point cadence** — currently 1 per level (code: `TALENT_POINTS_PER_LEVEL`). At level 100 that's ~100 points, well above the 20-point budget intended for meaningful scarcity. Needs tuning.
- **Node prerequisites** — do higher-tier nodes require specific lower-tier nodes, or just tier access?
- What does **Soul** govern beyond being a derived stat? Candidates: willpower, resilience, HP, CC resistance.
- What does **Interface** govern beyond being a derived stat? Candidates: precision, latency, cooldown reduction, cast speed.
- **Resource system** for each class — 1 unique resource per class (8 total). Resource bars are shown for each class with T1+ unlocked (max 3 bars). Pool size scales with contribution-weighted stat total. Origin classes use a single resource bar tied to Soul/Interface. See individual class pages.
- **HP scaling** — implemented. Max HP = base (100) + level-up gains + stat bonus. Stat bonus uses contribution-weighted totals: primary stat at 1.0x, team stats at 0.25x, opposing stats at 0.10x, multiplied by `HP_PER_WEIGHTED_STAT` (2.0). Current HP scales proportionally when max changes so equipping/unequipping gear doesn't leave the player at a strange ratio. Code: `AttributeState.get_stat_bonus_hp()`, `PrototypePlayer._recompute_stat_bonuses()`.
- **Resource pool scaling** — implemented alongside HP. Uses the same weighted stat total multiplied by `RESOURCE_PER_WEIGHTED_STAT` (1.0). Code: `AttributeState.get_stat_bonus_resource()`.
- **Visual metamorphosis art pipeline** — modular mesh kits per stat, shader channels, VFX layers. Needs concept work per class.
- **Relationship overlay** implementation — where exactly do overlays appear (item tooltips, stat bars, talent panel, character sheet)?
