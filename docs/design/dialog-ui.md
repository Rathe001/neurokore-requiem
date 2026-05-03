# Dialog & UI

> **Status:** Portrait system + class-effect concepts documented below are design-only. UI layout, HUD composition, and inventory design are TBD — to be expanded as implementation begins.

## Portraits

Animated pixel art portrait busts for NPCs, enemies, and quest-givers — in the style of Bard's Tale 1. Portraits appear during dialog exchanges, quest interactions, and certain boss encounters.

### Style

- Small bust format showing head and upper chest
- Front-facing or slight 3/4 angle
- Detailed pixel art with expressive faces
- Dark background with character-appropriate rim lighting
- Distinct from the in-game 3D models — portraits are a separate art context

### Animation

Each portrait has a base idle loop with additional states triggered by dialog tone or combat state:

| Animation | Trigger |
|---|---|
| Idle blink | Default |
| Mouth movement | Speaking |
| Damage reaction | Hit during encounter |
| Corrupted flicker | Class-specific (see below) |
| Death state | Defeated |

### Class Effects

Portraits for player characters and allied reps reflect their class identity through subtle persistent effects layered on top of the base animation:

| Class | Portrait Effect |
|---|---|
| Forged | Heat shimmer, occasional sparks at frame edge |
| Automaton | Scanline overlay, data readout ticking in background |
| Polymath | Violet neural glow, faint data fragments drifting |
| Survivalist | Grit and sweat, unstable lighting (matches their light source) |
| Count / Countess | Crisp, controlled — no distortion, sharp contrast |
| Enculted | Sickly green edge glow, occasional frame of something wrong that disappears immediately |
| Analog / Cyborg | Clean, no overlay — the absence of effect is the effect |

Enemy portraits follow the same format but use corruption, grotesquery, and faction-specific visual language. A failed augmentation experiment looks different from a corporate security enforcer looks different from something that came out of Sub-Level Zero.

---

## UI Philosophy

- **Stat identity** — the character screen displays a stat distribution visualization showing each attribute's percentage of total stats, current tier perks, and proximity to breakpoints. Recognized stat combinations display a combo description. See [Attribute System — Stat Identity](attribute-system.md#stat-identity--tier-perks--visual-metamorphosis) for full details.
- **Resource indicators** — class-specific and visually distinct from each other. Each class has its own UI concept; see the individual class pages under [Cyborg](../classes/cyborg.md) and [Analog](../classes/human.md).
- **Light source status** — visible without occupying prime screen real estate. See [Lighting](../world/lighting.md) for the full lighting system and equippable light source design.
- **Skill tree** — locked and invisible until the first rep encounter. See [Skill Tree](skill-tree.md) for unlock behavior and hotkey layout.
