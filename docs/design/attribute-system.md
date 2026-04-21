# Attribute System

> Status: Design phase — not yet implemented.

Each of the 8 class/spec identities maps to a moral attribute. Items roll these stats, and characters scale off them based on their spec. Think Pokemon type matchups, but grounded in the morality system.

## The 8 Attributes

| Stat | Tied To | Opposes |
|---|---|---|
| Soul | Human (base) | Interface |
| Interface | Cyborg (base) | Soul |
| Virtue | Gentleman | Deformity |
| Deformity | Forged | Virtue |
| Command | Automaton | Resourcefulness |
| Resourcefulness | Survivalist | Command |
| Sanity | Polymath | Corruption |
| Corruption | Enculted | Sanity |

## Scaling Rules

For any given character build:

- **Own spec's stat** → full scaling (1×)
- **Other two same-class spec stats** → quarter scaling (0.25×)
- **Base class stat** (Soul for Human, Interface for Cyborg) → TBD, likely broad utility scaling
- **Opposing spec's stat** → negative scaling (applies even across class lines)
- **Opposite class's non-opposing stats** → no benefit (0×)

### Example — Human Gentleman

| Stat | Scaling | Reason |
|---|---|---|
| Virtue | 1× | Own spec |
| Sanity | 0.25× | Same class, non-opposing |
| Resourcefulness | 0.25× | Same class, non-opposing |
| Soul | TBD | Base class stat |
| Deformity | negative | Opposing spec |
| Interface, Command, Corruption | 0× | Opposite class |

## Design Intent

Items carry moral weight. A Forged player finding Virtue-heavy gear is actively hurt by it — reinforcing character identity at the itemization level. This ties directly into the 2D morality plane and makes item drops feel meaningful beyond raw numbers.

## Open Questions

- What do **Soul** and **Interface** govern narratively and mechanically? Candidates: Soul → willpower/resilience (HP, CC resistance); Interface → precision/latency (cooldown reduction, cast speed).
- Exact **negative scaling multiplier** not decided (−0.5×? −1×?).
- **Tooltip design**: only show stats the character scales off (positive or negative); hide irrelevant ones to reduce noise.
- Lock in **Survivalist** vs **Scavenger** as the canonical spec name.
