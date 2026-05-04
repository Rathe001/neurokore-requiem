# Combat & Scale

- **Feel:** D2-style — deliberate, weighted, build-dependent. Combat should feel impactful, not floaty.
- **Enemy density:** Scales across the game. Early game: small groups. End-game: large hordes filling the screen.
- **Player scale:** Smaller than D2. More screen real estate means more simultaneous action and more readable large bosses.
- **Core mechanic:** Class-specific (see [Classes](../classes/overview.md)). No universal mechanic shared across all classes.
- **Stat identity:** Attribute distribution drives tier perks that change combat capabilities — extra appendages, drones, curses, etc. See [Attribute System — Stat Identity](attribute-system.md#stat-identity--tier-perks--visual-metamorphosis).
- **Gear augmentation:** Equipment can be modified at workbenches (schematics) or on the fly (class skills). Augments add functional and visual changes beyond stat increases. See [Gear Augmentation](gear-augmentation.md).

## Targeting Modes

Every skill resolves hits through one of four targeting shapes. Each gets a clear ground telegraph so the player can read the threat / opportunity without inspection.

| Mode | Behavior | Telegraph |
|---|---|---|
| Cone | All enemies in a cone in the facing direction. Melee default. | Cone outline on ground |
| Radial AoE | All enemies within a radius. | Circle outline on ground |
| Projectile | A travelling projectile that hits the first enemy on contact and self-destructs at max range. | Line on ground |
| Hitscan | Instant ray with a narrow cone clipped to wall distance. Hits the closest enemy along the ray. | Line on ground + beam flash |

Weapon archetype determines which mode its skill uses. Melee weapons use cone or radial AoE. Ranged weapons use projectile or hitscan. Targeting mode, damage, range, and cooldown all live with the skill, so swapping weapons changes combat behavior entirely — a pipe wrench reads completely differently than a shock baton.

Damage resolution feeds through one shared pipeline regardless of mode: accuracy roll → hit/miss → crit roll → base damage roll → attribute damage multiplier → crit multiplier. Centralised so weapon-affix balancing affects every mode equally.
