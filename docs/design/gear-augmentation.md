# Gear Augmentation

Equipment can be modified with **augments** — functional additions that go beyond raw stat increases. Augments change how gear looks, feels, and behaves. For the full weapon, offhand, and armor taxonomy, see [Equipment](equipment.md).

## Augment Sources

### Schematics (Workbench Augments)

Schematics are unlocked recipes that become available at a **workbench** — a crafting station located at class rep hubs. Once a schematic is unlocked, it can be applied to any compatible piece of gear at the workbench as many times as needed.

- Schematics are **not consumable** — they're permanent unlocks.
- Schematics may drop as loot, be purchased from vendors, or be rewarded by rep encounters.
- Comparable to the pattern/recipe system in Diablo 3/4 — collect it once, craft it forever.

### Skill-Based Augments (Field Augments)

Certain class skills allow the player to augment gear **on the fly**, without workbench access. These are rougher, improvised versions of workbench augments — effective but with trade-offs.

Examples:

- **Survivalist** — "Jury-Rigged Laser Sight": cobbled-together targeting aid. Works, but maybe flickers or has reduced range compared to a proper workbench laser sight.
- Other classes would have their own flavor of field augmentation, reflecting their identity.

Field augments consume a skill slot and may have resource costs or cooldowns. They can likely be overwritten by workbench augments later.

## Augment Slots

Gear has a limited number of **augment slots** (similar to sockets in Diablo 2). The number of slots depends on the item's base type and rarity.

!!! question "Open Questions — Slot Design"
    - Fixed slot count per base type, or variable (e.g., rare items roll more slots)?
    - Can augment slots be added to gear, or is the count locked at drop?
    - Are slots typed (weapon-only, armor-only) or universal?

## Type-Specific Augments

Augments are **item-type specific** — a shotgun has shotgun augments, a pistol has pistol augments, armor has armor augments. This keeps modifications thematically grounded and prevents nonsensical combinations.

### Example: Shotgun Augments

| Augment | Effect | Visual |
|---|---|---|
| Sawed-Off Barrel | Increases cone size, reduces range | Shortened barrel model |
| Rifled Barrel | Tightens cone, increases range | Extended barrel model |
| Drum Magazine | Increases magazine capacity | Drum mag model |

### Example: General Weapon Augments

| Augment | Effect | Visual |
|---|---|---|
| Laser Sight | Displays a targeting beam where the player aims | Red laser line from weapon to aim point |
| Suppressor | Reduces enemy aggro range on fire | Barrel extension on weapon |
| Shock Capacitor | Fire skill applies a brief stun | Electrical arcing VFX on weapon |
| Bayonet | Adds a melee fallback when magazine is empty | Blade attached to barrel |

### Example: Armor Augments

See [Equipment — Armor Augments](equipment.md#armor-augments) for the full armor augment table (pockets, reinforcement, custom tailored, resistances).

These are illustrative — the full augment list will grow per item type.

## Ammo Types

Ammo is a special augment category for ranged weapons. Ammo types change how the weapon's Fire and Alt Fire skills behave — they are **not consumable** (unlimited supply once equipped), but the weapon still requires reloading after expending its magazine.

| Ammo Type | Targeting | Effect |
|---|---|---|
| Standard | Weapon default | No modification |
| Buckshot | Wide cone | Short range, hits multiple targets |
| Slug | Single straight shot (no cone) | Long range, high single-target damage |
| Incendiary | Weapon default | Applies burn DoT, reduced base damage |
| AP (Armor Piercing) | Weapon default | Ignores a percentage of damage reduction |

Ammo type is set at the workbench or via field augment — not swapped mid-combat. Changing ammo type replaces the weapon's `fire_skill` targeting parameters (cone width, range, damage type) while preserving its base identity.

### Magazine & Reload

Ranged weapons have a **magazine capacity** — the number of shots before a reload is required. Firing consumes one round per shot. When the magazine is empty, the player must reload before firing again.

- **Reload** is an explicit action (keybind: **R**). The player can also reload at any time to top off a partial magazine.
- Reload has a **wind-up duration** that varies by weapon — a revolver reloads differently than a belt-fed LMG.
- Reload can be interrupted by taking damage, sprinting, or using a class skill (TBD).
- Magazine capacity can be modified by augments (e.g., Extended Magazine, Drum Magazine).
- Melee weapons do not have magazines or reloads.

!!! question "Open Questions — Ammo & Reload"
    - Does reload speed scale with any gear stat (e.g., hands attack speed)?
    - Should certain ammo types be class-locked or require schematics?
    - Can ammo type affect Alt Fire as well, or only Fire?
    - Should there be a passive auto-reload after a delay (like some ARPGs), or always manual?

## Augment Removal

!!! question "Open Questions — Removal"
    - Can augments be removed and reused, or are they destroyed on removal?
    - Does the workbench offer a "salvage" option that recovers the schematic materials?
    - Are field augments permanent until overwritten, or do they expire?

## Interaction with Other Systems

- **Talent tree / tier perks** — Some augment schematics could require a minimum talent tier to unlock (e.g., Forged tier II unlocks augments for mechanical appendages).
- **Fire / Alt Fire** — Weapon augments can modify the behavior of Fire and Alt Fire skills (e.g., a laser sight augment adds a visual beam during aiming, a bayonet augment changes the melee fire skill).
- **Two-handed vs. one-handed** — 2H weapons may have more augment slots than 1H weapons to compensate for losing the offhand.

---

## Open Questions

!!! question "Open Questions"
    - Should field augments be strictly worse than workbench augments, or just different?
    - Can augments conflict with each other (e.g., suppressor + muzzle flash augment)?
    - Should augments be visible in the character panel tooltip, or get their own inspection UI?
    - Do augments affect item trade value or rarity tier?
    - Should certain augments be class-locked (only Automaton can install drone-link augments)?
