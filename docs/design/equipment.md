# Equipment

For item properties, rarity, power budgets, and generation see [Item Architecture](item-architecture.md). For behavior mods and slot stat domains see [Itemization](itemization.md).

## Weapon Types

Weapons are categorized by **damage type** and **handling** (1H or 2H). Damage type determines what enemies are vulnerable or resistant to. Handling determines whether the offhand slot is available.

- **1H weapons** define Fire only. Alt Fire comes from the offhand.
- **2H weapons** always define Fire. Alt Fire is **optional** — a sledgehammer has no alt fire, but an M4 has a grenade launcher. Augments can add an alt fire to weapons that don't have one natively.

The weapon type list will grow significantly over time. Each new weapon type should change the player's tactical approach, not just provide different numbers.

## Damage Types

### Energy

Powered by cells or capacitors. Clean, precise, futuristic.

| Weapon | Handling | Fire | Alt Fire (2H) | Notes |
|---|---|---|---|---|
| Laser Pistol | 1H | Focused beam (single target) | — | Fast, low damage per hit |
| Plasma Rifle | 2H | Plasma bolt | Charged shot (slow, high damage) | Overheats on sustained fire |
| Pulse Cannon | 2H | Rapid pulse volley | EMP burst (disables mechanicals) | Heavy, slow movement while firing |
| Ion Sidearm | 1H | Short-range arc | — | Chains between nearby targets |

### Kinetic

Conventional firearms and projectile weapons. Familiar, reliable, loud.

| Weapon | Handling | Fire | Alt Fire (2H) | Notes |
|---|---|---|---|---|
| Pistol | 1H | Semi-auto shot | — | Balanced starter |
| Revolver | 1H | Heavy single shot | — | High damage, slow fire rate, long reload |
| Shotgun | 2H | Buckshot cone | Slug (single straight shot) | Ammo type changes cone vs. slug |
| Assault Rifle (M4) | 2H | Full auto | 3-round burst | Versatile mid-range |
| Battle Rifle (M16A2) | 2H | Full auto | 3-round burst | Higher damage, more recoil |
| SMG | 1H | Rapid fire | — | High fire rate, low damage, wide spread |
| LMG | 2H | Sustained full auto | — (no alt fire) | Huge magazine, movement penalty |
| Sniper Rifle | 2H | Scoped single shot | Quick-scope (faster, less accurate) | Extreme range, very slow fire rate |

### Elemental

Weapons that deal damage through environmental effects. Each element has a signature status effect.

| Element | Status Effect | Visual |
|---|---|---|
| Cryo | Slow, then Freeze (stacking) | Ice crystals, blue tint on target |
| Fire | Burn DoT | Flames, orange glow |
| Electric | Stun + chain to nearby targets | Arcing lightning, sparks |
| Toxic | Poison DoT + reduced healing | Green fumes, dripping particles |

Elemental weapons follow the same 1H/2H structure as energy and kinetic — the element determines the damage type and status effect, not the weapon form factor.

| Weapon | Handling | Example |
|---|---|---|
| Elemental Pistol | 1H | Cryo Pistol — short-range frost jet |
| Elemental Rifle | 2H | Fire Rifle — incendiary bolt with burn DoT |
| Elemental Launcher | 2H | Electric Launcher — lobs a Tesla orb (Fire), chain lightning burst (Alt Fire) |

### Melee

No magazine, no reload. Melee weapons use the same Fire / Alt Fire system but with contact-range skills.

| Weapon | Handling | Fire | Alt Fire (2H) | Notes |
|---|---|---|---|---|
| Pipe Wrench | 1H | Swing | — | Starter weapon |
| Combat Knife | 1H | Quick stab | — | Fast, low damage, applies bleed |
| Shock Baton | 1H | Strike (electric) | — | Stun on hit |
| Sledgehammer | 2H | Overhead slam | Wide sweep (AoE arc) | Slow, massive knockback |
| Chainsaw | 2H | Sustained cut (hold Fire) | Rev (brief damage boost) | DPS-focused, close range |
| Vibroblade | 2H | Slash combo | Thrust (long reach, single target) | Balanced 2H melee |

### Class-Specific

Weapons gated by **talent tree progression**, not stat distribution. A player must have invested deep enough in a specific class's talent tree to equip the weapon. This creates meaningful build commitment — the weapon rewards players who have specialized.

| Weapon | Class Gate | Handling | Fire | Alt Fire | Notes |
|---|---|---|---|---|---|
| Drone Control Module | Automaton | 2H | Direct drone attack on target | Recall / reposition drones | Weapon is the interface for the drone swarm |
| Ancient Text | Enculted | 1H | Channel curse at target | — | Slow, powerful |
| Exo-Gauntlet | Forged | 1H | Augmented punch | — | Melee |
| Scavenger's Multi-Tool | Survivalist | 1H | Context-dependent (melee near, throws far) | — | Adapts to range |
| Etiquette Piece | Count/Countess | 1H | Precise strike (bonus crit) | — | Low base damage, high crit multiplier |
| Synthesis Staff | Polymath | 2H | Arcane bolt | Overload pulse (AoE) | Hybrid energy/elemental |

## Offhands

Offhands occupy the offhand slot when using a 1H weapon. Each offhand's `fire_skill` becomes the player's **Alt Fire**. Offhands are never "just stat sticks" — they always provide an active Alt Fire ability.

Most offhands fall into one of three archetypes:

- **Active hold** — RMB held while the effect is sustained (full block, beam, channel). Strong but committal.
- **Toggled buff** — RMB taps to grant a persistent player-side buff with its own pool / duration / cooldown.
- **Triggered fire** — RMB fires once per press at the cursor (grenade, sidearm shot).

| Offhand | Archetype | Effect | Notes |
|---|---|---|---|
| Active Shield | Active hold | Hold RMB to fully block incoming damage and knockback up to a pool, then breaks | Movement penalty while held; pool persists across release/press; cooldown only on break |
| Amplification Shield | Toggled buff | Tap RMB to apply a partial damage + knockback reduction over a long duration | Pool drains from absorbed damage; cooldown only on break (free re-cast on natural expiry) |
| Buckler / Riot Shield | Triggered fire | Shield bash — short-range knockback cone | Starter offhand. Melee. |
| Grenade | Triggered fire | Throw grenade at cursor (AoE on impact) | Arcing projectile with max range. Subtype variants (frag, incendiary, cluster, stun). |
| Sidearm | Triggered fire | Quick shot from a secondary 1H ranged weapon | Lower damage than main hand. |
| Disruptor | Triggered fire | EMP pulse (disables mechanical enemies briefly) | Short range AoE. |
| Stealth Module | Toggled buff | Brief invisibility + movement speed | Breaks on attack or taking damage. |
| Drone Relay | Triggered fire | Command drone to attack (single target) | Automaton-themed. One drone instead of a swarm. |
| Cursed Totem | Triggered fire | Apply curse DoT at range | Enculted-themed. Frees main hand for a generic weapon. |

## Armor

Armor pieces (head, chest, hands, legs, feet) provide **damage reduction** and contribute to the player's total **weight**. Each armor slot also has a **stat domain** and a pool of **behavior mods** — see [Itemization](itemization.md) for details.

There are no discrete armor weight classes — every piece simply has a weight value. Heavier armor tends to have higher DR; lighter armor keeps the player fast. The player decides their own trade-off by mixing pieces.

See [Item Architecture — Weight System](item-architecture.md#weight-system) for how weight affects movement speed.

### Armor Augments

| Augment | Effect | Notes |
|---|---|---|
| Pockets | +N inventory slots | Stacks with backpack bonus. Available on chest and boots. |
| Reinforcement | Increased damage reduction | Flat DR bonus. |
| Custom Tailored | Reduced weight | Makes the piece lighter, effectively increasing speed. |
| Insulated Lining | Elemental resistance (specific) | Reduces damage from one element (cryo, fire, electric, toxic). |
| Reflective Coating | Energy resistance | Reduces energy weapon damage. Visual shimmer. |
| Kinetic Weave | Kinetic resistance | Reduces ballistic damage. |

!!! question "Open Questions — Armor"
    - Class-specific armor sets (gated by talent depth like weapons)?
    - Should some augments add weight (reinforcement makes the piece heavier)?

---

## Damage Type Interactions

!!! question "Open Questions — Damage Type System"
    - Do enemies have explicit resistances/vulnerabilities per damage type?
    - Is there a rock-paper-scissors layer, or just flat resist/vulnerability values?
    - Do elemental status effects stack with weapon augment effects?
    - How does damage type interact with ammo type augments?

## Rarity and Base Types

Each weapon category contains multiple **base types** at different rarity tiers. Higher rarity weapons have:

- Higher base damage
- More augment slots
- Better innate stats (fire rate, magazine size, reload speed)
- Unique augment compatibility (legendary weapons may have a built-in augment that can't be removed)

!!! question "Open Questions — Rarity"
    - How many rarity tiers? (Common / Uncommon / Rare / Legendary / Unique?)
    - Do rarity tiers affect drop pool or just stat ranges?
    - Can class-specific weapons drop at all rarities?
