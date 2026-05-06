# Itemization

How gear works, what it does for the player, and why each piece matters. For weapon and offhand specifics see [Equipment](equipment.md). For augments, ammo, and schematics see [Gear Augmentation](gear-augmentation.md). For the item type hierarchy, rarity, and generation pipeline see [Item Architecture](item-architecture.md).

---

## Design Intent

Every piece of gear should answer a question the player is already asking: *"How do I want to play?"* A drop is exciting when it changes behavior, not just when its numbers are bigger. The itemization system is built around two layers:

1. **Behavior mods** — each gear slot can roll a mod that changes how a game mechanic works. A jetpack backpack and a phasing backpack both go in the same slot, but they create fundamentally different movement styles.
2. **Stat bonuses** — direct, readable numbers (damage, crit, speed) that scale the player's effectiveness. Stats are always relevant to the item type, so the player can evaluate a drop at a glance without comparing a wall of unrelated numbers.

Talents are the **build spine** — the player's deliberate choices about who their character is. Gear is the **build amplifier** — it enhances, modifies, and sometimes surprises. Finding a god-roll item that synergizes with your talent build should feel like a jackpot.

---

## Gear Slots

Every class uses the same eight equipment slots. There are no class-locked or origin-locked slots.

| Slot | Stat Domain | Role |
|------|-------------|------|
| Head | Crit chance | Critical strikes — the spike-damage axis |
| Chest | Health regeneration | Core survivability |
| Hands | Attack speed | Offensive tempo |
| Legs | Movement speed | Ground mobility |
| Feet | Traction / surface handling | Environmental navigation |
| Back (Backpack) | Inventory capacity | Storage and movement ability |
| Weapon (1H or 2H) | Damage + accuracy | Primary offense (accuracy is weapon-intrinsic; only weapons can roll hit chance) |
| Offhand | Utility / defense | Secondary ability (blocked by 2H weapons) |

Each slot's **stat domain** is the primary numeric bonus it provides. A pair of gloves always tells you about attack speed. Boots always tell you about traction. This keeps drops instantly readable — the player knows what a slot *does* without memorizing cross-slot stat interactions.

### Universal Rolls

Every equippable item can roll **+HP** and **+Resource** as secondary bonuses, regardless of slot. These are the only stats that appear across all item types. All other bonuses stay within the slot's domain.

### Domain-Adjacent Bonuses

Within their domain, items can roll related bonuses that stay thematically connected:

- **Armor pieces** (head, chest, hands, legs, feet) can roll damage reduction
- **Weapons** can roll stun chance, knockback (crit chance lives on the head slot)
- **Offhands** roll stats specific to their archetype (shield pool, blast radius, etc.)

The goal: a player picking up any item can evaluate it in a few seconds. If gloves only ever affect attack speed, damage reduction, HP, and resource — that's a four-stat comparison at most.

### Traction (Feet)

Traction is the boots stat domain. It's a single number 0–100 that governs how the player interacts with hostile ground — slip, slow, knockdown, and DoT pools (fire, acid, electric pools, etc.). Both axes use the **same staircased breakpoints**, so one roll tracks both:

| Traction | Movement immunity unlocked | DoT damage reduction |
|----------|----------------------------|----------------------|
| < 25 | — | 0% |
| 25–49 | Slip-down chance | 25% |
| 50–74 | + Movement slow on hostile ground | 50% |
| 75–99 | + Knockdown on cracked floor / spike pads | 75% |
| 100 | + Full stride, immune to all ground effects | 100% |

The staircase is intentional: every breakpoint reads as "a tier earned" and the numeric jump is the moment that matters. Continuous reduction would dilute the breakpoint identity. Only boots roll traction — total = boots traction, no cross-slot stacking — so a player gearing into traction is making an explicit "feet matter" commitment, not accidentally accumulating it from random armor.

Traction does **not** replace per-element resistance: a fire pool still does damage through `fire_resistance` like any fire damage. Traction layers on top as an additional reduction specifically for *ground-source* damage. A player with high fire resistance + low traction takes less damage from fire pools than from incoming fire projectiles, because both stats apply.

---

## Behavior Mods

Each gear slot (excluding weapons and offhands, which define behavior through their base type) can roll one **behavior mod** — a mechanical change to how a game system works. Mods are the identity layer of an item. Two chest pieces with identical stats but different mods play differently.

### Mod Design Principles

- **Mods change behavior, not just numbers.** "+10% jump height" is a stat. "Hold space to fly, draining resource" is a mod. Mods belong in the second category.
- **Each mod has a tradeoff.** A jetpack backpack has fewer inventory slots. Power always costs something — the player optimizes their own balance.
- **Mods are rollable with their own parameters.** A jetpack might drain 18 or 26 resource per second depending on the roll. The mod identity is fixed; the quality varies.
- **~4 mods per slot.** Enough variety to create meaningfully different loadouts, few enough that each mod is distinct and memorable.

### Mod Pools (Representative)

These are examples of the design space per slot, not a final list. Each mod should feel like a different answer to the slot's core question.

**Back (Backpack)** — *"How do I move through vertical space?"*

| Mod | Behavior | Tradeoff |
|-----|----------|----------|
| Jetpack | Hold space to fly (resource drain) | Fewer inventory slots |
| Antigravity | No jump; resource auto-drains over pits instead of falling | Constant resource pressure over hazards |
| Thrusters | Double jump | — |
| Phasing | Ignore enemy collision while airborne | — |

**Feet** — *"How do I interact with surfaces?"*

| Mod | Behavior | Tradeoff |
|-----|----------|----------|
| Mag-Boots | Immune to pit falls and slippery surfaces | Reduced movement speed |
| Silent Step | No footstep audio; enemies have reduced detection range | — |
| Impact Landing | AoE damage on landing from height | — |
| Ice Grip | Full traction on slippery surfaces; sprint on ice | — |

**Head** — *"What do I see?"*

| Mod | Behavior | Tradeoff |
|-----|----------|----------|
| Threat Detection | Enemy HP bars visible at longer range | — |
| Weak Point Scan | Increased crit chance vs. scanned target | Scan takes time to lock |
| Peripheral Vision | Wider targeting cone for cone-type attacks | — |
| Radar Pulse | Briefly reveals enemies through walls on cooldown | — |

**Chest** — *"How do I survive sustained pressure?"*

| Mod | Behavior | Tradeoff |
|-----|----------|----------|
| Reactive Plating | Damage reduction spike on hit, decays over time | Lower base DR |
| Nanite Repair | Regen rate increases when stationary | No regen while moving |
| Kinetic Absorb | Portion of damage taken converts to resource | Lower max HP |
| Second Wind | Auto-heal burst when HP drops below a threshold (long cooldown) | — |

**Hands** — *"How do I deliver attacks?"*

| Mod | Behavior | Tradeoff |
|-----|----------|----------|
| Steady Aim | First shot after pause has increased accuracy and crit | Only benefits deliberate play |
| Quick Reload | Drastically reduced reload time | — |
| Charged Strikes | Hold fire to charge, release for boosted damage | Slower attack cadence |
| Multi-Strike | Melee attacks hit in a wider arc | Reduced single-target damage |

**Legs** — *"How do I control my positioning?"*

| Mod | Behavior | Tradeoff |
|-----|----------|----------|
| Sprint Burst | Shift for a burst of speed (resource cost) | — |
| Slide | Crouch while moving to slide through enemies | — |
| Strafe Boost | Increased speed while moving perpendicular to aim | — |
| Dodge Roll | Tap movement key twice to roll with brief invulnerability | Cooldown between rolls |

### Cross-Slot Synergies

Mods across different slots can create emergent playstyles that neither piece enables alone. These are discovered, not designed — the system should produce interesting combinations naturally:

- **Phasing (back) + Impact Landing (feet)** — dive through enemies, land with AoE
- **Jetpack (back) + Steady Aim (hands)** — aerial sniper, hovering for precision shots
- **Slide (legs) + Kinetic Absorb (chest)** — slide into danger, convert incoming hits to resource
- **Sprint Burst (legs) + Silent Step (feet)** — fast repositioning without alerting enemies

The player who discovers a synergy that works with their talent build has found their *build identity* — and that moment is what makes loot-driven games compelling.

---

## Sprint

Sprint is a universal movement mechanic available to all players. Hold the sprint key for a burst of speed at the cost of resource drain.

Sprint can be modified by gear mods (sprint speed, sprint cost reduction, sprint on specific surfaces) and talent nodes. It serves as another resource-spending decision point: do I sprint to reposition, or save that resource for my next ability?

---

## Class Interactions

### Class-Restricted Mods

Some mods are restricted to specific classes or origins. A Cyborg-only chest mod like "Nanite Repair" reinforces the fantasy that augmented bodies heal differently. Class restrictions should be rare — most mods are universal.

### Class-Granting Mods

Extremely rare items can grant access to a specific talent from another class (e.g., "Grants Enculted Tier III, Node 4"). These are chase items — finding one as a non-Enculted player opens a build path that's normally impossible. They should be rare enough to feel legendary, not common enough to blur class boundaries.

### Loot Affinity

Drop tables are subtly biased toward the player's origin. Analog characters see more organic/kinetic-flavored mods; Cyborg characters see more tech/energy-flavored mods. Both origins can equip either — the bias creates a soft identity without hard-locking content. Finding an off-origin god roll is a moment, not a frustration.

---

## Power Budget

Every item is generated against a **power budget** determined by item level and rarity. The budget is spent across:

1. **Base stat roll** — the slot's primary domain stat (attack speed on gloves, movement speed on legs)
2. **Mod quality** — the rolled parameters of the behavior mod (resource drain rate, cooldown, radius)
3. **Affix count and quality** — prefix/suffix bonuses (damage reduction, +HP, +resource)

A powerful mod consumes more budget, leaving less room for strong base stats or affixes. A jetpack with low resource drain *must* have weaker base stats. This single mechanism prevents degenerate items — every piece is internally balanced regardless of what specific mod or affixes rolled.

The budget scales with item level and is multiplied by rarity tier. Higher-level, rarer items have more total budget to distribute, but the tradeoff structure remains. There is no level where an item can be the best at everything simultaneously.

---

## Effectiveness Curve (Item Level Scaling)

Items don't get statically replaced when the player outlevels them. Every item carries an `item_level` (rolled at generation time) and the player's level determines an **effectiveness multiplier** applied to all combat stats and gear bonuses on that item. This single mechanism replaces the need for stat squish patches — numerical ranges stay bounded because old items decay smoothly rather than being inflated past.

### The Curve

| Player vs. ilvl | Multiplier | Behavior |
|------|------|------|
| ilvl == player level | 1.00× | Drop is "for you" — hits its rolled values exactly |
| ilvl > player level (above-cap drops from endgame content) | 1.00× → 1.50× ceiling | Linear boost, +1% per level above |
| ilvl < player level | asymptotic toward 0.30× floor | `1 / (1 + delta * 0.05)`. Never reaches zero — favorite items stay weakly viable |

A few example values for player level 50:
- ilvl 50 → 100% (no change)
- ilvl 40 → 67% (1 / (1 + 0.5))
- ilvl 30 → 50%
- ilvl 10 → 33% (just above the 30% floor)
- ilvl 0 (starter) → 29% → clamped to 30% floor

For a player at the level cap (100):
- ilvl 100 → 100%
- ilvl 120 → 120%
- ilvl 150 → 150% (hits ceiling — the endgame chase)

### Scope

The multiplier applies to **every** combat-power stat: weapon damage rolls, attack speed, crit chance, accuracy, all stat-modifier bonuses (HP, damage reduction, knockback, resistances, shield pool, etc.). It does **not** apply to:

- **Storage stats** (`inventory_bonus` on backpacks) — bag size shouldn't shrink as the player levels.
- **Feel/flavor stats** (`weapon_range`, `blast_radius`, light parameters) — these define what a weapon *is*, not how powerful it is.
- **Behavior mods** — a jetpack works as a jetpack regardless of ilvl gap. Mods are *identity*; the multiplier touches *power*.

Code-side: read combat values via `Item.get_effective_modifier()` or the typed `effective_*()` accessors (`effective_damage_min/max`, `effective_attack_speed`, etc.). Storage and flavor reads stay on the raw `get_modifier()` path.

### Starter Gear

The player gets a baseline kit on character creation rolled at `item_level = 0`. With every world drop generating at `ilvl >= 1`, starter gear is always strictly weaker than anything found — players are never naked, but the first drop is meaningful. Starter pieces sit at the 30% floor for most of leveling, replaced gradually as the player gears up.

### Recipes / Rescaling

A planned crafting interaction lets the player **bring an item up to their current level** in exchange for resources. This is the answer to "I love this drop but I'm now too high-level for it" — instead of replacing the item, the player invests to keep it relevant. Recipe details TBD; the underlying system already supports it (just needs a craft action that bumps `item.item_level` to `PlayerState.level`).

### Why This Shape

- **No stat bloat / squish.** Numbers don't grow with player level, the multiplier does. Stat ranges stay readable across the lifetime of the game.
- **Build retention.** Players can keep favorite items longer; gear churn becomes a choice, not a treadmill.
- **Endgame chase.** Above-cap ilvl drops (from maps/ubers) become the meaningful prize without breaking the base game's curve.
- **Soft, not punishing.** The 30% floor means a beloved low-ilvl unique still functions for experimentation. Aggressive linear decay would punish novelty.

---

## Open Questions

!!! question "Open Questions"
    - What is the right number of mods per slot? Starting assumption is ~4, but some slots may warrant more.
    - Should mods be rerollable at a crafting station, or is the mod locked at drop time?
    - Can the same mod appear at different rarities with different parameter ranges?
    - How does the power budget interact with legendary items (which are hand-crafted)?
    - Should certain mod combinations be explicitly prevented, or does the one-mod-per-slot rule provide enough natural exclusivity?
    - Simulation tooling: when should we build the stat simulation tool that generates random loadouts and checks for balance outliers?
