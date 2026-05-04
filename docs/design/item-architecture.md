# Item Architecture

The intent layer for how items work. For weapon/offhand/armor identity, see [Equipment](equipment.md). For augments, ammo, and schematics, see [Gear Augmentation](gear-augmentation.md).

---

## Item Hierarchy

Every item has a **main type** (the bucket) and a **sub type** (the specific form). The bucket determines which slot it goes in; the sub type drives flavour, sub-stats, and which affixes can roll on it.

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
| Recon | Flashlight, Lantern, Radar, UV Light | Recon |
| Utility | Medkit, Illicit Drugs, Family Heirloom | Utility slot (Analog origin, via belt) |
| Bus | Tracking Upgrade, Drone Control Range Upgrade, Bandwidth Optimizer | Bus slot (Cyborg origin, via mainboard) |

### Origin-Specific Slot Systems

| Origin | Expansion Slot | Sub-Slots | Inspiration |
|---|---|---|---|
| Analog | Belt | Utility slots (consumables, drugs, heirlooms, tools) | Utility belt — quick-access field items |
| Cyborg | Mainboard | Bus slots (system upgrades, modules, firmware) | EVE Online — fitting modules to a ship |

The belt grants utility slots; the mainboard grants bus slots. Both work identically — the expansion item determines how many sub-slots are available.

**Origin-locked.** Belts and utility items can only be equipped by Analog classes. Mainboards and bus items can only be equipped by Cyborg classes. These items still drop for all players (trade value, future multiplayer), but cannot be used by the wrong origin.

---

## Equipment Slots

| Slot | All Classes | Notes |
|---|---|---|
| Weapon | Yes | 1H or 2H. 2H locks offhand. |
| Offhand | Yes | Blocked when 2H weapon equipped. |
| Head | Yes | |
| Chest | Yes | |
| Gloves | Yes | |
| Boots | Yes | |
| Backpack | Yes | Grants inventory capacity. |
| Recon | Yes | Light sources, scanners, UV — see Recon-specific section. |
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
    - What's the right speed-loss curve (linear, stepped, exponential)?
    - Should weight affect dodge/roll speed or stamina if those mechanics exist?
    - Visual indicator on character sheet for current weight vs. threshold?

---

## Item Properties

Each item carries enough state to identify it (id, name, glyph, rarity), gate it (item level, origin lock), and drive its mechanics (damage range for weapons, DR for armor, light type for recon, etc.). The exact field set lives on the `Item` resource — this doc only covers what *kinds* of properties exist per category.

- **Weapons** carry damage stats, attack speed, accuracy, crit, range, a fire skill, and (for 2H) optionally an alt-fire.
- **Offhands** carry a fire skill that becomes the player's RMB. Active offhands (shield, grenade) carry archetype-specific stats — pool, reduction, duration, cooldown.
- **Armor** carries damage reduction and optional resistance to a damage type.
- **Backpacks** always grant an inventory bonus; rarity layers extra modifiers on top.
- **Belt / Mainboard** grant a sub-slot count.
- **Recon** items carry a light type, range, energy, and color.

Augment slots are an additional property gated by item level + rarity (see [Augment Slots](#augment-slots) below).

### Recon

Recon items provide visibility in dark zones (see [Lighting](../world/lighting.md)). Each recon item has a **type** that determines how it functions.

| Recon Type | Behavior | Use Case |
|---|---|---|
| Directional | Narrow directed beam in facing direction | Default. Good range, limited coverage. Reveals what you're looking at. |
| Radiant | 360-degree glow around the player | Shorter range, but no blind spots. Good for melee builds that need awareness in all directions. |
| Scanner / Radar | HUD overlay with rotating sweep; reveals enemy blips through walls | Tactical awareness — see threats through cover. Doesn't illuminate the environment. Some enemies may be immune (shielded, cloaked). |
| UV | Reveals hidden markings, traps, loot, secret doors | Exploration tool. Emits a faint purple light but primarily reveals objects in dedicated UV-hidden groups. |

Recon items follow standard rarity and item level. Higher rarity gets better range / energy and may roll prefixes/suffixes.

!!! question "Open Questions — Recon"
    - Battery / fuel resource, or always on when equipped?
    - Equip multiple types and swap between them, or one slot?
    - Are advanced types (Scanner, UV) gated by item level, rarity, or tier perk?
    - Scanner blip persistence after toggling off (residual awareness)?
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

### Rarity & Modifier Counts

Items can roll **modifiers** from prefix and suffix pools. Each modifier adds stats (attributes, DR, speed, crit, etc.) from a budget determined by item level.

| Rarity | Color | Modifier Density | Augment Slots |
|---|---|---|---|
| Common | Gray | None | Very rare |
| Uncommon | Green | One affix (prefix OR suffix) | Low chance |
| Rare | Blue | Prefix + suffix | Moderate chance |
| Epic | Purple | Prefix + suffix + a unique non-stat special modifier | Higher chance |
| Legendary | Orange | Hand-crafted; fixed identity | Fixed (designed per item) |

- **Prefixes** and **suffixes** draw from pools appropriate to the item's main type and sub type. A weapon prefix pool is different from an armor prefix pool.
- **Epic special modifiers** are non-stat — a unique mechanical effect (e.g., "kills restore HP", "Fire skill has a chance to not consume ammo", "enemies killed explode"). The exact list grows with the affix table.
- **Legendaries** are entirely hand-authored. Fixed stats, fixed name, fixed special effects. These are chase items with specific identities — not random rolls.

### Affix Flavor

The affix pool is intentionally extensible — we'll keep adding entries as systems come online. A representative sample of what each pool contains:

**Weapon prefixes** — base damage, crit chance, attack speed, elemental damage, hit chance, pierce.
**Weapon suffixes** — range, knockback, lifesteal, reduced resource cost, cooldown reduction.
**Armor prefixes** — damage reduction, max health, movement speed, carry capacity.
**Armor suffixes** — elemental resistance, max health, regen.

Class attribute stats (Orthodoxy, Ambition, etc.) are **not** in this pool — they roll in the separate class-stat slot system below.

### Class Attribute Stats on Items

Items can roll bonuses to the six rollable class attribute stats — Orthodoxy, Ambition, Deviation, Optimization, Ingenuity, Clarity — as a **separate slot system** independent of the prefix/suffix affix budget. The number of class stat slots an item may carry is gated by item level: early-game items carry one, late-game items can carry several.

Class stat slots are **additive** to prefix/suffix slots. A blue mid-game chest could carry one prefix + one suffix + a class stat roll or two. Combat-side affixes (crit, pierce, attack speed, etc.) live entirely in the prefix/suffix pools and never compete with class identity for budget.

Tier perks fire on the player's **aggregate** equipped class-stat totals (see [Attribute System](attribute-system.md)). Multi-stat late-game items therefore don't inflate tier perk magnitudes — they relax slot economy, letting endgame players trade gear slots for hybrid builds (e.g. three hybrid items reaching deep one stat + a meaningful second stat instead of needing five mono-stat items). This is the intended endgame power lever.

Swapping a piece whose class-stat rolls differ can cross tier thresholds — hence the [gear swap confirmation dialog](attribute-system.md).

---

## Augment Slots

Augment slots are determined at drop time by **item level** and **rarity**.

- Higher item level = higher chance of rolling augment slots.
- Higher rarity = more potential slots.
- A low-level common *can* roll an augment slot, but it's very unlikely.
- Legendaries have fixed augment slots designed per item.

**Augments do not scale.** A laser sight is a laser sight — there is no "Laser Sight II". The value of an augment comes from how well it synergizes with the item's rolled stats and the player's build, not from finding a higher-level version. The player sees an item drop and thinks about *which* augment would make it great, not *which level* of augment to slot.

See [Gear Augmentation](gear-augmentation.md) for the full augment system (schematics, field augments, ammo types).

---

## Item Generation

When an enemy dies:

1. Roll whether something drops (drop chance).
2. Roll the item's main type + sub type (weighted by enemy type, zone, etc.).
3. Roll its item level (player level + enemy level + variance).
4. Roll its rarity (separate algorithm with magic-find, zone modifiers, etc.).
5. Roll combat affixes (prefix/suffix pool) according to rarity.
6. Roll class attribute stat slots (additive to affixes).
7. Roll values for each affix and class stat (bounded by item level budget).
8. Roll augment slot count (item level + rarity weighted).
9. Roll weight (base weight for sub type + variance from modifiers).
10. Spawn the pickup in the world.

!!! question "Open Questions — Item Generation"
    - Magic find (MF%) stat — does it exist? If so, is it an attribute, gear affix, or both?
    - Zone-specific drop tables (certain sub types only drop in certain areas)?
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
