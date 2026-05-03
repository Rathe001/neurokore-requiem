# Item Architecture

This is the source of truth for how items work. For weapon/offhand/armor specifics see [Equipment](equipment.md). For augments, ammo, and schematics see [Gear Augmentation](gear-augmentation.md).

---

## Item Hierarchy

Every item has a **main type** and a **sub type**.

| Main Type | Example Sub Types | Slot |
|---|---|---|
| 1H Weapon | Pistol, Revolver, SMG, Combat Knife, Shock Baton, Ion Sidearm, Ancient Text | Weapon |
| 2H Weapon | Assault Rifle, Shotgun, Sniper Rifle, Sledgehammer, Chainsaw, Drone Control Module | Weapon (locks offhand) |
| Offhand | Buckler, Grenade, Sidearm, Shield Generator, Disruptor, Stealth Module | Offhand |
| Head Armor | Helmet, Hood, Visor | Head |
| Chest Armor | Vest, Jacket, Plate Rig, Hardsuit | Chest |
| Gloves | Work Gloves, Gauntlets, Interface Gloves | Gloves |
| Boots | Runners, Stompers, Mag-Boots | Boots |
| Belt | Utility Belt, Bandolier | Belt (Analog origin) |
| Mainboard | Circuit Board, Neural Bridge | Mainboard (Cyborg origin) |
| Backpack | Field Pack, Cargo Frame | Backpack |
| Optics | Flashlight, Headlamp, Glow Stick, Sensor | Optics |
| Utility | Medkit, Illicit Drugs, Family Heirloom | Utility slot (Analog origin, via belt) |
| Bus | Tracking Upgrade, Drone Control Range Upgrade, Bandwidth Optimizer | Bus slot (Cyborg origin, via mainboard) |

### Origin-Specific Slot Systems

| Origin | Expansion Slot | Sub-Slots | Inspiration |
|---|---|---|---|
| Analog | Belt | Utility slots (consumables, drugs, heirlooms, tools) | Utility belt — quick-access field items |
| Cyborg | Mainboard | Bus slots (system upgrades, modules, firmware) | EVE Online — fitting modules to a ship |

The belt grants utility slots; the mainboard grants bus slots. Both work identically to the current system — the expansion item determines how many sub-slots are available.

**Origin-locked:** Belts and utility items can only be equipped by Analog classes. Mainboards and bus items can only be equipped by Cyborg classes. These items still drop for all players (trade value, future multiplayer), but cannot be used by the wrong origin.

---

## Equipment Slots (Final)

| Slot | All Classes | Notes |
|---|---|---|
| Weapon | Yes | 1H or 2H. 2H locks offhand. |
| Offhand | Yes | Blocked when 2H weapon equipped. |
| Head | Yes | |
| Chest | Yes | |
| Gloves | Yes | |
| Boots | Yes | |
| Backpack | Yes | Grants inventory capacity. |
| Optics | Yes | Flashlight, scanner, UV, etc. |
| Belt | Analog only | Grants utility sub-slots. Cannot be equipped by Cyborg classes. |
| Mainboard | Cyborg only | Grants bus sub-slots. Cannot be equipped by Analog classes. |
| Utility 1–N | Analog only | Granted by belt. Utility items are origin-locked to Analog. |
| Bus 1–N | Cyborg only | Granted by mainboard. Bus items are origin-locked to Cyborg. |

---

## Weight System

Every item has a **weight** value. Total equipped weight affects player movement speed.

- Below a **carry threshold**: no penalty (full speed).
- Above the threshold: movement speed decreases proportionally to how far over the limit the player is.
- The carry threshold can be modified by skill tree nodes, tier perks, and potentially augments.
- Weight is a property of every equippable item, not just armor. A sledgehammer is heavier than a combat knife. A plate rig is heavier than a vest. Even a backpack has weight.

This replaces the binary light/heavy armor system. There is no armor "weight class" — instead, each armor piece simply has a weight value. A player who equips all low-weight gear moves at full speed. A player who stacks heavy armor and a 2H LMG moves noticeably slower. The player optimizes their own trade-off.

!!! question "Open Questions — Weight"
    - Exact carry threshold formula? (Base + attribute scaling + skill tree bonuses?)
    - Is the speed curve linear or stepped (e.g., 10% over = 5% slow, 50% over = 25% slow)?
    - Should weight affect dodge/roll speed or stamina if those mechanics exist?
    - Visual indicator on character sheet for current weight vs. threshold?

---

## Item Properties

### Universal (every item)

| Property | Description |
|---|---|
| `id` | Unique identifier |
| `main_type` | 1H Weapon, 2H Weapon, Offhand, Chest Armor, Optics, Utility, Bus, etc. |
| `sub_type` | Pistol, Assault Rifle, Buckler, Plate Rig, Medkit, Tracking Upgrade, etc. |
| `name` | Display name (i18n key) |
| `description` | Flavor text (i18n key) |
| `rarity` | Gray, Green, Blue, Purple, Orange |
| `item_level` | Determines stat ranges and augment slot chance |
| `weight` | Affects movement speed when equipped |
| `glyph` | Inventory display character |
| `glyph_color` | Inventory display color |

### Weapon-Specific

| Property | Description |
|---|---|
| `fire_skill` | Skill resource for Fire (all weapons) |
| `alt_fire_skill` | Skill resource for Alt Fire (2H only, optional — a sledgehammer has none) |
| `two_handed` | Whether this weapon locks the offhand slot |
| `damage_type` | Energy, Kinetic, Elemental (cryo/fire/electric/toxic), Melee |
| `magazine_size` | Rounds before reload (ranged only, 0 for melee) |
| `reload_time` | Seconds to reload (ranged only) |
| `tier_perk_required` | Tier perk gate for class-specific weapons (e.g., `enculted_1`) |

### Offhand-Specific

| Property | Description |
|---|---|
| `fire_skill` | Skill resource — becomes the player's Alt Fire |
| `tier_perk_required` | Tier perk gate for class-themed offhands |

### Armor-Specific

| Property | Description |
|---|---|
| `damage_reduction` | Base DR value |
| `resistance_type` | Optional elemental/energy/kinetic resistance |
| `resistance_value` | Resistance amount |

### Backpack-Specific

| Property | Description |
|---|---|
| `inventory_bonus` | Extra inventory slots — **always rolls**, never zero. Higher item level = higher potential bonus. |

Backpacks follow the standard rarity system. A gray backpack still grants slots (just fewer). A blue backpack rolls prefix/suffix on top of its slot bonus. An orange legendary backpack might have a unique effect alongside a high fixed slot count.

### Belt / Mainboard-Specific

| Property | Description |
|---|---|
| `sub_slot_count` | Number of utility/bus slots granted |

### Optics-Specific

Optics are equippable items that provide visibility in dark zones (see [Lighting](../world/lighting.md)). Each optic has a **type** that determines how it functions.

| Optics Type | Enum | Behavior | Use Case |
|---|---|---|---|
| Directional | `DIRECTIONAL` | Narrow directed beam (SpotLight3D) in facing direction | Default. Good range, limited coverage. Reveals what you're looking at. |
| Radiant | `RADIANT` | 360-degree glow (OmniLight3D) around the player | Shorter range, but no blind spots. Good for melee builds that need awareness in all directions. |
| Scanner | `SCANNER` | Radar HUD overlay with rotating sweep; reveals enemy blips through walls | Tactical awareness — see threats through cover. Doesn't illuminate the environment. Some enemies may be immune (shielded, cloaked). |
| UV | `UV` | Reveals hidden markings, traps, loot, secret doors | Exploration tool. Emits a faint purple light but primarily reveals objects in the `uv_hidden` group. |

| Property | Description |
|---|---|
| `light_type` | `DIRECTIONAL`, `RADIANT`, `SCANNER`, `UV` |
| `light_energy` | Brightness / intensity |
| `light_range` | How far the light reaches |
| `light_color` | Tint of the light |

Optics follow standard rarity and item level. Higher rarity optics have better range, energy, and may roll prefixes/suffixes (e.g., "Focused" prefix = tighter cone + longer range, "of Efficiency" suffix = reduced battery drain if battery becomes a mechanic).

!!! question "Open Questions — Optics"
    - Do optics have a battery / fuel resource, or are they always on when equipped?
    - Can a player equip multiple optics types and swap between them, or is it one slot?
    - Should Scanner/UV be gated by item level, rarity, or tier perk?
    - Do Scanner blips persist briefly after toggling off (residual awareness)?
    - Night-vision type (full green-tinted visibility, but blinding if a bright source appears)?
    - Scanner immunity flags — which enemy properties block detection (shielded, cloaked, etc.)?

---

## Stat Budget & Modifiers

### Item Level

When an item drops, its **item level** is rolled based on:

- The **player's level** (floor)
- The **enemy's level** that dropped it (anchor)
- A small random variance (so drops aren't always exactly the enemy's level)

Item level determines the stat budget available to the item — higher item level = higher possible stat rolls.

### Prefix / Suffix System

Items can roll **modifiers** from prefix and suffix pools. Each modifier adds stats (attributes, DR, speed, crit, etc.) from a budget determined by item level.

| Rarity | Color | Prefix | Suffix | Special | Augment Slots |
|---|---|---|---|---|---|
| Common | Gray | — | — | — | Very rare (low chance based on item level) |
| Uncommon | Green | 1 | — | — | Low chance |
| Rare | Blue | 1 | 1 | — | Moderate chance, can roll 1–2 |
| Epic | Purple | 1 | 1 | 1 unique modifier | Higher chance, can roll 1–3 |
| Legendary | Orange | Hand-crafted | Hand-crafted | Hand-crafted | Fixed (designed per item) |

- **Prefixes** and **suffixes** draw from pools appropriate to the item's main type and sub type. A weapon prefix pool is different from an armor prefix pool.
- **Green** items roll either a prefix OR a suffix (not both).
- **Blue** items always roll one prefix AND one suffix.
- **Purple** items roll prefix + suffix + a **special modifier** that is non-stat — a unique mechanical effect (e.g., "kills restore 2% HP", "Fire skill has 10% chance to not consume ammo", "enemies killed explode").
- **Orange** legendaries are entirely hand-authored. Fixed stats, fixed name, fixed special effects. These are chase items with specific identities — not random rolls.

### Prefix / Suffix Examples

These are illustrative — the full affix table will be built when the stat system is implemented.

**Weapon Prefixes:**
| Prefix | Effect |
|---|---|
| Searing | +fire damage |
| Precise | +crit chance |
| Brutal | +base damage |
| Swift | -cooldown on Fire |

**Weapon Suffixes:**
| Suffix | Effect |
|---|---|
| of the Marksman | +range |
| of Devastation | +knockback |
| of Efficiency | -resource cost |
| of the Leech | +lifesteal on hit |

**Armor Prefixes:**
| Prefix | Effect |
|---|---|
| Hardened | +damage reduction |
| Nimble | +movement speed |
| Fortified | +max health |

**Armor Suffixes:**
| Suffix | Effect |
|---|---|
| of the Bear | +carry capacity |
| of Resilience | +elemental resistance |
| of the Bulwark | +max health |

### Class Attribute Stats on Items

Items can roll bonuses to the six rollable class attribute stats — Orthodoxy, Ambition, Deviation, Optimization, Ingenuity, Clarity — as a **separate slot system** independent of the prefix/suffix affix budget. The number of class stat slots an item may carry is gated by item level:

| Item Level Range | Class Stat Slots | Game Phase |
|---|---|---|
| 1 – 33 | 1 | Early game |
| 34 – 66 | 1 – 2 | Mid game |
| 67 – 100 | 1 – 3 | Late game |

Class stat slots are **additive** to prefix/suffix slots. A blue mid-game chest could carry 1 prefix + 1 suffix + 1–2 class stat rolls. Combat-side affixes (crit, pierce, attack speed, etc.) live entirely in the prefix/suffix pools and never compete with class identity for budget.

Tier perks fire on the player's **aggregate** equipped class-stat totals (see [Attribute System](attribute-system.md)). Multi-stat late-game items therefore don't inflate tier perk magnitudes — they relax slot economy, letting endgame players trade gear slots for hybrid builds (e.g. three hybrid items reaching T5 Deviation + T3 Orthodoxy instead of needing five Deviation-only items). This is the intended endgame power lever.

Swapping a piece whose class-stat rolls differ can cross tier thresholds — hence the [gear swap confirmation dialog](attribute-system.md).

### Combat Affix Pool

Combat affixes fill the standard prefix/suffix slots and tune how a build kills. The list is intentionally extensible — more affixes will be added as systems come online. All numerical ranges scale with item level.

**Damage / offense (prefix-leaning):**
- Base damage bonus
- Hit chance
- Crit chance
- Crit damage
- Pierce
- Attack speed
- Elemental damage (cryo, fire, electric, toxic — see [Equipment](equipment.md) damage types)

**Utility / defense (suffix-leaning):**
- Cooldown reduction
- Movement speed
- Lifesteal / leech on hit
- Resource regen on hit
- Reduced resource cost
- Range, knockback (weapon-specific)
- Damage reduction, elemental resistance (armor-specific)
- Carry capacity, max health

The prefix/suffix split is convention; the affix table maps each entry to its pool. Class attribute stats are **not** in this pool — they roll in the separate class-stat slot system above.

---

## Augment Slots

Augment slots are determined at drop time by **item level** and **rarity**.

- Higher item level = higher chance of rolling augment slots.
- Higher rarity = more potential slots.
- A low-level gray *can* roll an augment slot, but it's very unlikely.
- Orange legendaries have fixed augment slots designed per item.

**Augments do not scale.** A laser sight is a laser sight — there is no "Laser Sight II". The value of an augment comes from how well it synergizes with the item's rolled stats and the player's build, not from finding a higher-level version. The player sees an item drop and thinks about *which* augment would make it great, not *which level* of augment to slot.

See [Gear Augmentation](gear-augmentation.md) for the full augment system (schematics, field augments, ammo types).

---

## Item Generation Summary

```
1. Enemy dies → drop roll
2. Roll item main type + sub type (weighted by enemy type, zone, etc.)
3. Roll item level (player level, enemy level, variance)
4. Roll rarity (separate algorithm — MF%, zone modifiers, etc.)
5. Based on rarity, roll combat affixes (prefix/suffix pool):
   - Gray:   no affixes
   - Green:  roll 1 prefix OR 1 suffix
   - Blue:   roll 1 prefix AND 1 suffix
   - Purple: roll 1 prefix + 1 suffix + 1 special modifier
   - Orange: load hand-crafted definition
6. Roll class attribute stat slots based on item level (additive to affixes):
   - ilvl 1–33:   1 class stat
   - ilvl 34–66:  1–2 class stats
   - ilvl 67–100: 1–3 class stats
7. Roll values for each affix and class stat (bounded by item level budget)
8. Roll augment slot count (item level + rarity weighted)
9. Roll weight (base weight for sub type + variance from modifiers)
10. Assign item properties → spawn pickup in world
```

!!! question "Open Questions — Item Generation"
    - Magic find (MF%) stat — does it exist? If so, is it an attribute, gear affix, or both?
    - Are there zone-specific drop tables (certain sub types only drop in certain areas)?
    - Can enemies drop items above the player's level (incentivizing punching up)?
    - Smart loot (bias toward player's class/build) or fully random?
    - Vendor items — do shops use the same generation system with a level/rarity cap?

---

## Open Questions

!!! question "Open Questions — Architecture"
    - Should bus/utility items be equippable or consumable (one-time use like D2 potions vs. persistent like EVE modules)?
    - Do utility items (drugs, medkits) have cooldowns, charges, or both?
    - Can items be traded between players in future multiplayer?
    - Item stash / bank — shared across characters or per-character?
    - Salvaging / disenchanting items for crafting materials?
    - Set items (matched sets with bonuses) — is this a rarity tier or a separate system?
