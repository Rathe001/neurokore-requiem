# Dialog & UI

## Portraits

Animated pixel art portrait busts for NPCs, enemies, and quest-givers — in the style of Bard's Tale 1. Portraits appear during dialog exchanges, quest interactions, and certain boss encounters.

### Style

- Small bust format showing head and upper chest
- Front-facing or slight 3/4 angle
- Detailed pixel art with expressive faces
- Dark background with character-appropriate rim lighting
- Distinct from the in-game sprite scale — portraits are a separate art context

### Animation

Each portrait has a base idle loop with additional states triggered by dialog tone or combat state:

| Animation | Trigger |
|---|---|
| Idle blink | Default |
| Mouth movement | Speaking |
| Damage reaction | Hit during encounter |
| Corrupted flicker | Spec-specific (see below) |
| Death state | Defeated |

### Spec & Class Effects

Portraits for player characters and allied reps reflect their spec identity through subtle persistent effects layered on top of the base animation:

| Spec | Portrait Effect |
|---|---|
| Forged | Heat shimmer, occasional sparks at frame edge |
| Automaton | Scanline overlay, data readout ticking in background |
| Polymath | Violet neural glow, faint data fragments drifting |
| Survivalist | Grit and sweat, unstable lighting (matches their light source) |
| Gentleman / Lady | Crisp, controlled — no distortion, sharp contrast |
| Enculted | Sickly green edge glow, occasional frame of something wrong that disappears immediately |
| Base Class | Clean, no overlay — the absence of effect is the effect |

Enemy portraits follow the same format but use corruption, grotesquery, and faction-specific visual language. A failed augmentation experiment looks different from a corporate security enforcer looks different from something that came out of Sub-Level Zero.

---

## UI Philosophy

- **Morality system** — never shown as a number or labeled meter. The character screen displays only the dot on a 2D coordinate plane. See [Morality System](morality-system.md) for full details.
- **Resource indicators** — class-specific and visually distinct from each other. Each spec has its own UI concept; see the individual spec pages under [Cyborg](../classes/cyborg.md) and [Human](../classes/human.md).
- **Light source status** — visible without occupying prime screen real estate. See [Lighting](../world/lighting.md) for the full lighting system and equippable light source design.
- **Skill tree** — locked and invisible until the first rep encounter. See [Skill Tree](skill-tree.md) for unlock behavior and hotkey layout.

*UI layout, HUD composition, and inventory design are TBD — to be expanded as implementation begins.*
