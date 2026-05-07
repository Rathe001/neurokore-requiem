# Classes

Eight classes at launch: two **origin classes** (generalists) and six **specialized classes** (three per origin). Class identity is the core design pillar — each class plays differently enough that it could feel like a different game mode.

Class metadata (IDs, origin mapping, accent colors, stat-tree mapping) lives in `game/scripts/systems/attribute_state.gd`. Talent and perk content lives in `game/resources/talents/` and `game/resources/perks/` — the .tres files are authoritative for current numbers.

## Roster

| Origin | Specialization | Resource | Signature perk ladder |
|---|---|---|---|
| **Analog** | — *(origin generalist)* | TBD | TBD (origin perks not yet designed) |
| Analog | **Survivalist** | Adrenaline (builds under pressure, decays when safe) | **IED** |
| Analog | **Count / Countess** | Composure (maintained through controlled play, breaks under panic) | **Exile** |
| Analog | **Enculted** | TBD (rethinking to align with the ambition fantasy) | **Doomsayer** |
| **Cyborg** | — *(origin generalist)* | TBD | TBD |
| Cyborg | **Forged** | Power Grid (a budget for what's active simultaneously, not a pool) | **Amalgamation** |
| Cyborg | **Automaton** | Bandwidth (caps active drones/scripts) | **Drone Swarm** |
| Cyborg | **Polymath** | TBD (Memory/CPU dual-axis backburned; likely simplifies to one) | **Telekinesis** |

Origin classes are easier to gear and more forgiving — generalists with shallow access across their three specialist trees. Specializations trade that flexibility for depth: a Tier V specialist plays nothing like the origin class they came from.

## Talent tree shape

Each class has a talent tree that drives build identity. Progression through the tree unlocks **perk tiers** (I through V):

- **Tier I–II** — broadening; picking up tools, exploring the kit
- **Tier III** — committing; the tree narrows, builds start to specialize
- **Tier IV–V** — defining; perks that fundamentally change how the class plays, potentially altering resource mechanics or adding entirely new systems

Perk tiers are permanent progression through talent investment. They cannot be lost by swapping gear. The signature perk ladders in the table above are what *make* each class — not shared, not transferable (outside extremely rare class-granting item mods).

Tuning lever: talent-point cadence (1 point per 3 levels currently), point-threshold gating between tiers, and tier exclusivity rules all live in `talent_state.gd` and `perk_state.gd`.

## The six specializations

Short fantasies and current signature-perk behavior. Numbers come from the .tres files — re-read those when tuning rather than this doc.

### Survivalist *(Analog, mid-range)*

Adaptability and improvisation. Thrives in chaos, uses scavenged gear and jury-rigged weapons. Gets stronger as conditions get worse.

**IED.** Every LMB attack tosses a proximity trap at the cursor (clamped to placement range). Traps pulse visibly during an arming window, then live a short time or detonate when an enemy enters their radius. Per-tier: more concurrent traps, faster arming. T1 forces predictive placement; T3 feels snappy. New traps FIFO-evict the oldest at cap.

### Count / Countess *(Analog, ranged)*

Discipline, composure, old-world refinement. Refused augmentation on principle and became dangerous through mastery instead. Precise, methodical — dueling, marksmanship, controlled aggression.

**Exile.** Hits curse the target for several seconds. Cursed enemies take bonus damage from any source (per-tier multiplier scales up). Duration is fixed — kill them inside the window or the curse silently expires and you auto-fire one massive shot at them.

The Count's **Point Blank** talent (T1, ort.tres node 0) waives the ranged-at-melee accuracy penalty for player-fired shots — a deliberate counter-pick to the global "ranged inside 2.5m halves accuracy" rule.

### Enculted *(Analog, ranged)*

Tapped into something ancient living in the network. The augmentations that make the Cyborg powerful are blocking signals the unmodified mind can receive. Unstable, dangerous power with a horror edge.

**Doomsayer.** Constant aura with linear distance falloff. Multiple rolls per second on every enemy in range — per-tier chance per roll to inflict stun, charm (mind-control), or weaken. Charm has its own cap of simultaneously-charmed enemies — persistent until you die or a new charm bumps the oldest out. The player is wreathed in a visible purple miasma whose intensity scales with tier.

### Forged *(Cyborg, melee)*

Sell nearly all remaining humanity for raw mechanical power. Extra limbs, chassis upgrades, heavy attachments.

**Amalgamation.** Grow extra arm slots — equipable 1H weapons. LMB fires every equipped weapon, staggered across the main weapon's attack interval. Extra arms fire **free** — only the main weapon spends resource. Per-arm spawn offsets emit shots from right / left / above the player. Pattern for any future perk that adds equipment slots.

### Automaton *(Cyborg, mid-range)*

Command the machine through AI scripting and a fleet of drones. Set conditions, automate responses, build a system that fights alongside you.

**Drone Swarm.** Untargetable hover drones wander semi-randomly near the player and auto-fire on enemies in range. Drones collide with walls (won't shoot through them) but are invulnerable. Per-tier: more drones. Future Mainboard chips will modify drone behavior.

The full vision (drones-as-script-hosts, scripts-as-loot, condition/response pairs, overflow/crash) is mostly aspirational — current implementation is one generic combat drone.

### Polymath *(Cyborg, ranged)*

Augment the mind beyond human limits. The body is just a platform for expanded cognition.

**Telekinesis.** Every several seconds, thin psionic beams emit from the player's head, each anchoring on a distinct nearby enemy. Over a windup the target is lifted into the air, then slammed back to the ground for direct + radial AoE damage. Per-tier: more concurrent beams. Bolts within the same trigger pick distinct targets when possible.

## Class-tuned monster variants

Certain enemies have class-specific variants — different forms of the same base threat tuned to the player's class. The world shapes itself around what threatens *you* specifically. Variants stack with the standard enemy; the base encounter is always the foundation, and your class adds a personal layer on top.

| Origin | Class | Variant | Threat type |
|---|---|---|---|
| Cyborg | Cyborg (origin) | Caustic Beetle | Biological — corrodes hardware |
| Cyborg | Forged | Swarm of Nanobytes | Nano-mechanical — drains Power Grid |
| Cyborg | Automaton | Software Bug | Digital entity — corrupts scripts |
| Cyborg | Polymath | Hallucination | Cognitive — generated by the augmented mind itself |
| Analog | Analog (origin) | Wraith | Supernatural — drawn to unshielded minds |
| Analog | Survivalist | Irradiated Spider | Biological / environmental |
| Analog | Count / Countess | Heathen | Ideological — chaos against order |
| Analog | Enculted | Unbeliever | Ideological — actively suppresses occult power |

In a future multiplayer party, all active variants spawn simultaneously — party composition becomes a tactical decision beyond skill synergies.

Class-variant encounters are not yet wired into `game/resources/enemies/`; the table is design intent, not shipped content.
