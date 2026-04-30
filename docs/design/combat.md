# Combat & Scale

- **Feel:** D2-style — deliberate, weighted, build-dependent. Combat should feel impactful, not floaty.
- **Enemy density:** Scales across the game. Early game: small groups. End-game: large hordes filling the screen.
- **Player scale:** Smaller than D2. More screen real estate means more simultaneous action and more readable large bosses.
- **Core mechanic:** Class-specific (see [Classes](../classes/overview.md)). No universal mechanic shared across all classes.
- **Stat identity:** Attribute distribution drives tier perks that change combat capabilities — extra appendages, drones, curses, etc. See [Attribute System — Stat Identity](attribute-system.md#stat-identity--tier-perks--visual-metamorphosis).
- **Gear augmentation:** Equipment can be modified at workbenches (schematics) or on the fly (class skills). Augments add functional and visual changes beyond stat increases. See [Gear Augmentation](gear-augmentation.md).

## Targeting Modes

Each skill has a targeting mode that determines how it resolves hits. Modes are defined on the `Skill` resource.

| Mode | Behavior | Telegraph |
|---|---|---|
| `SINGLE_CONE` | Spatial query: all enemies in a cone (facing direction, configurable arc). Melee default. | Cone outline on ground |
| `AOE_RADIAL` | Spatial query: all enemies within radius. | Circle outline on ground |
| `PROJECTILE` | Spawns a projectile node that travels in a straight line. Hits the first enemy on contact, then despawns. Self-destructs at max range. | Line on ground |
| `HITSCAN` | Raycast + narrow cone query clipped to wall distance. Hits the closest enemy along the ray. Beam VFX. | Line on ground + beam flash |

Weapon bases determine which targeting mode their skill uses. Melee weapons use `SINGLE_CONE` or `AOE_RADIAL`. Ranged weapons use `PROJECTILE` or `HITSCAN`. The targeting mode, damage, range, and cooldown are all properties of the `Skill` resource attached to the weapon — swapping weapons changes combat behavior entirely.

Damage resolution for all modes feeds through the same pipeline: accuracy roll → hit/miss → crit roll → base damage roll (weapon or skill) → attribute damage multiplier → crit multiplier. This pipeline lives in the `PlayerCombat` component.
