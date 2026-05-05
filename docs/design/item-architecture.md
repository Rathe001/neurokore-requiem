# Item Architecture

The structural layer for how items are built, rolled, and categorized. For what each slot *does* and how behavior mods work, see [Itemization](itemization.md). For weapon/offhand/armor identity, see [Equipment](equipment.md). For augments, ammo, and schematics, see [Gear Augmentation](gear-augmentation.md).

---

## Item Hierarchy

Every item has a **main type** (the bucket) and a **sub type** (the specific form). The bucket determines which slot it goes in; the sub type drives flavor, base stats, and which affixes and mods can roll on it.

| Main Type | Example Sub Types | Slot |
|---|---|---|
| 1H Weapon | Pistol, Revolver, SMG, Combat Knife, Shock Baton, Ion Sidearm | Weapon |
| 2H Weapon | Assault Rifle, Shotgun, Sniper Rifle, Sledgehammer, Chainsaw, Drone Control Module | Weapon (locks offhand) |
| Offhand | Buckler, Grenade, Sidearm, Shield Generator, Disruptor, Stealth Module | Offhand |
| Head Armor | Helmet, Hood, Visor | Head |
| Chest Armor | Vest, Jacket, Plate Rig, Hardsuit | Chest |
| Hands | Work Gloves, Gauntlets, Interface Gloves | Hands |
| Leg Armor | Greaves, Cargo Pants, Exo-Leggings | Legs |
| Boots | Runners, Stompers, Mag-Boots | Feet |
| Backpack | Field Pack, Cargo Frame, Thruster Rig | Back |

---

## Equipment Slots

| Slot | All Classes | Notes |
|---|---|---|
| Weapon | Yes | 1H or 2H. 2H locks offhand. |
| Offhand | Yes | Blocked when 2H weapon equipped. |
| Head | Yes | |
| Chest | Yes | |
| Hands | Yes | |
| Legs | Yes | |
| Feet | Yes | |
| Back | Yes | Grants inventory capacity. |

---

## Weight System

Every item has a **weight** value. Total equipped weight affects player movement speed.

- Below a **carry threshold**: no penalty (full speed).
- Above the threshold: movement speed decreases proportionally to how far over the limit the player is.
- The carry threshold can be modified by talent nodes and potentially augments.
- Weight is a property of every equippable item, not just armor. A sledgehammer is heavier than a combat knife. A plate rig is heavier than a vest. Even a backpack has weight.

This replaces the binary light/heavy armor system. There is no armor "weight class" — instead, each armor piece simply has a weight value. A player who equips all low-weight gear moves at full speed. A player who stacks heavy armor and a 2H LMG moves noticeably slower. The player optimizes their own trade-off.

!!! question "Open Questions — Weight"
    - What's the right speed-loss curve (linear, stepped, exponential)?
    - Should weight affect dodge/roll speed if those mechanics exist?
    - Visual indicator on character sheet for current weight vs. threshold?

---

## Item Properties

Each item carries enough state to identify it (id, name, glyph, rarity), gate it (item level), and drive its mechanics. The exact field set lives on the `Item` resource — this doc covers what *kinds* of properties exist per category.

- **Weapons** carry damage stats, attack speed, accuracy, crit, range, a fire skill, and (for 2H) optionally an alt-fire.
- **Offhands** carry a fire skill that becomes the player's RMB. Active offhands (shield, grenade) carry archetype-specific stats — pool, reduction, duration, cooldown.
- **Armor** (head, chest, hands, legs, feet) carries a base stat in its slot's domain (see [Itemization — Gear Slots](itemization.md#gear-slots)), damage reduction, and optionally a behavior mod.
- **Backpacks** grant an inventory bonus, a behavior mod, and base stats.

All equippable items can roll **+HP** and **+resource** as secondary bonuses.

Augment slots are an additional property gated by item level + rarity (see [Augment Slots](#augment-slots) below).

---

## Power Budget & Modifiers

### Item Level

When an item drops, its **item level** is rolled based on:

- The **player's level** (floor)
- The **enemy's level** that dropped it (anchor)
- A small random variance (so drops aren't always exactly the enemy's level)

Item level determines the **power budget** available to the item — higher item level = higher total budget to distribute across base stats, mod quality, and affixes.

### Power Budget

Each item's total stat power is constrained by a budget. The budget is spent across:

1. **Base stat roll** — the slot's primary domain stat
2. **Mod quality** — the rolled parameters of the behavior mod (resource drain rate, cooldown, etc.)
3. **Affix count and quality** — prefix/suffix bonuses

A powerful mod consumes more budget, leaving less room for strong base stats or affixes. This prevents any single item from being the best at everything — every piece has internal tradeoffs regardless of what rolled.

### Rarity & Modifier Counts

Items can roll **modifiers** from prefix and suffix pools. Rarity determines how many modifiers an item carries.

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

The affix pool is intentionally extensible. A representative sample:

**Weapon prefixes** — base damage, crit chance, attack speed, elemental damage, hit chance, pierce.
**Weapon suffixes** — range, knockback, lifesteal, reduced resource cost, cooldown reduction.
**Armor prefixes** — damage reduction, max health, domain stat bonus (e.g., extra attack speed on gloves).
**Armor suffixes** — elemental resistance, max health, regen, +resource.

---

## Augment Slots

Augment slots are determined at drop time by **item level** and **rarity**.

- Higher item level = higher chance of rolling augment slots.
- Higher rarity = more potential slots.
- A low-level common *can* roll an augment slot, but it's very unlikely.
- Legendaries have fixed augment slots designed per item.

**Augments do not scale.** A laser sight is a laser sight — there is no "Laser Sight II". The value of an augment comes from how well it synergizes with the item's rolled stats, mod, and the player's build, not from finding a higher-level version.

See [Gear Augmentation](gear-augmentation.md) for the full augment system (schematics, field augments, ammo types).

---

## Item Generation

When an enemy dies:

1. Roll whether something drops (drop chance).
2. Roll the item's main type + sub type (weighted by enemy type, zone, etc.).
3. Roll its item level (player level + enemy level + variance).
4. Roll its rarity (separate algorithm with magic-find, zone modifiers, etc.).
5. Determine power budget from item level and rarity.
6. Roll behavior mod from the slot's mod pool (if applicable).
7. Roll mod parameters against the power budget.
8. Roll combat affixes (prefix/suffix pool) according to rarity, spending remaining budget.
9. Roll +HP and +resource secondary bonuses.
10. Roll augment slot count (item level + rarity weighted).
11. Roll weight (base weight for sub type + variance from modifiers).
12. Apply loot affinity bias (subtle origin-flavored mod weighting).
13. Spawn the pickup in the world.

!!! question "Open Questions — Item Generation"
    - Magic find (MF%) — does it exist? If so, is it a gear affix, talent node, or both?
    - Zone-specific drop tables (certain sub types only drop in certain areas)?
    - Can enemies drop items above the player's level (incentivizing punching up)?
    - Smart loot (bias toward player's build) or fully random beyond loot affinity?
    - Vendor items — do shops use the same generation system with a level/rarity cap?

---

## Open Questions

!!! question "Open Questions — Architecture"
    - Do consumable items exist (medkits, drugs) and if so, how are they carried/slotted?
    - Can items be traded between players in future multiplayer?
    - Item stash / bank — shared across characters or per-character?
    - Salvaging / disenchanting items for crafting materials?
    - Set items (matched sets with bonuses) — is this a rarity tier or a separate system?
    - Should mods be rerollable at a crafting station, or locked at drop?
