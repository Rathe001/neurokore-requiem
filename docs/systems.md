# Systems

Combat, itemization, equipment, and the design intent behind them. Code under `game/scripts/` is authoritative for current numbers and field names — this doc explains the *why*.

## Combat

D2-style: deliberate, weighted, build-dependent. Combat should feel impactful, not floaty. Player scale is smaller than D2; the extra screen real estate exists so end-game horde density and oversized bosses both stay readable.

### Targeting modes

Every skill resolves hits through one of four targeting shapes. Each gets a clear ground telegraph so the player can read the threat / opportunity without inspection.

| Mode | Behavior | Telegraph |
|---|---|---|
| Cone | All enemies in a cone in the facing direction. Melee default. | Cone outline on ground |
| Radial AoE | All enemies within a radius. | Circle outline on ground |
| Projectile | A travelling projectile that hits the first enemy on contact and self-destructs at max range. | Line on ground |
| Hitscan | Instant ray with a narrow cone clipped to wall distance. Hits the closest enemy along the ray. | Line on ground + beam flash |

Weapon archetype determines which mode its skill uses. Melee weapons use cone or radial AoE; ranged weapons use projectile or hitscan. Targeting mode, damage, range, and cooldown all live with the skill — swapping weapons changes combat behavior entirely. A pipe wrench reads completely differently than a shock baton.

### Damage pipeline

One shared resolution path regardless of mode:

```
accuracy roll → hit/miss → crit roll → base damage roll → gear bonus multiplier → crit multiplier
```

Centralized so weapon-affix balancing affects every mode equally.

### Point-blank ranged penalty

Ranged attacks (hitscan and projectile) check distance from fire origin to target. Inside the melee threshold (~2.5m), accuracy is halved. Cone and AoE skills are exempt. Charging into a ranged enemy is a viable counter — their bolts miss more often.

Counter-play differentiation: Survivalist sprints to disengage before firing; Count can spec the **Point Blank** talent to waive the penalty for player-fired shots only.

### Signature quirks (per-archetype passives)

Every weapon archetype has *one* iconic passive that fires automatically while equipped — a "thing the weapon does" beyond raw stat differences. Stats alone make weapons interchangeable; a quirk makes the pickup feel like an actual choice. Players don't need to memorize the list — the HUD's quirk reminder widget (under the minimap) surfaces the play tip for currently-equipped weapons.

Design intent is that each quirk is *cheap to learn, possible to exploit*. A new player benefits passively; a learned player builds positioning + cadence around it.

| Archetype | Quirk |
|---|---|
| 1H knife | **Backstab** — hits from behind enemy facing deal +50% |
| 2H hammer | **Wind-Up** — first hit after 1s standing still deals +75% |
| Laser pistol | **Charged Shot** — first shot after 1s+ idle deals 1.5× |
| Plasma rifle | **Pierce** — bolts pass through one enemy |
| SMG | **Penetration** — every 5th shot deals 2× |
| LMG | **Heat** — sustained fire stacks +10%/shot, max +50%, decays after 1s of no fire |
| Sniper | **First Mark** — first shot on a fresh target deals +50% (5s freshness window per target) |
| RPG | **Concussive** — every enemy in the blast is staggered |
| Shotgun | **Point Blank** — pellets hitting within 2m deal +50% |
| Charged Arc Taser | **Static Build** — every 10th hit on an enemy releases at 3× (per-target counter) |
| Energy Accelerator | **Resonance** — held stream ramps damage to +30%, resets on release |

The canonical reminder strings live in `WeaponQuirkPanel.QUIRK_TIPS`. Implementation lives across `PlayerCombat` (per-shot or per-cast quirks), `PrototypePlayer` (player-side stack trackers like LMG heat / Accelerator resonance / hammer wind-up), `PrototypeEnemy` (per-target counters like Sniper First Mark / Taser Static Build), and `PrototypeProjectile` (bullet-level quirks like Plasma Pierce / Shotgun Point Blank distance).

### Melee combo

Each melee swing within 1.5s of the previous one advances a 3-step combo. The chain resets on timeout, weapon swap, or non-melee weapon switch.

| Step | Cone width | Damage | Knockback | Finisher |
|---|---|---|---|---|
| 1 | authored | 1.0× | 1.0× | — |
| 2 | 1.5× wider | 1.25× | 1.5× | — |
| 3 | 350° (almost full sweep) | 1.6× | 2.5× | **status applied** |

The step-3 finisher applies a status that differs by weapon kind:
- **1H knives** stack a **bleed** debuff — % max-HP damage-over-time, stacks up to 5. Body-horror tone made explicit; pressure compounds the longer the player stays engaged on a single target.
- **2H hammers** apply a brief **stun** (0.6s) plus a ground-impact ring visual + camera shake for the heavy-feel sell.

Why a combo system at all: pre-combo melee was "spam LMB, hit cone, damage." The combo introduces a *rhythm* — staying engaged with one target builds toward the finisher, then resets. Encourages target selection over crowd-spam, gives 1H and 2H distinct identities at the finisher tier, and creates a natural cadence that makes melee feel weighted instead of mechanical.

Plus **hitstop** on every melee connect: the swing animation freezes for ~60ms when a hit lands. Per-player (anim_player.speed_scale, not Engine.time_scale), so MP-safe. Sells the weight of every individual hit; without it, melee reads as "input → damage number" with no physical feedback.

## Itemization

Every piece of gear should answer a question the player is already asking: *"How do I want to play?"* A drop is exciting when it changes behavior, not just when its numbers are bigger.

> **Talents are the build spine — the player's deliberate choices about who their character is. Gear is the build amplifier — it enhances, modifies, and sometimes surprises.**

The system is built around two layers:

1. **Behavior mods** — each gear slot can roll a mod that changes how a game mechanic works. A jetpack backpack and a phasing backpack both go in the same slot, but they create fundamentally different movement styles.
2. **Stat bonuses** — direct, readable numbers that scale the player's effectiveness. Stats are always relevant to the item type, so the player can evaluate a drop at a glance without comparing a wall of unrelated numbers.

### Gear slots

Every class uses the same eight slots. No class-locked or origin-locked slots.

| Slot | Stat domain | Role |
|---|---|---|
| Head | Crit chance | Spike-damage axis |
| Chest | Health regeneration | Core survivability |
| Hands | Attack speed | Offensive tempo |
| Legs | Movement speed | Ground mobility |
| Feet | Traction | Environmental navigation |
| Back (Backpack) | Inventory capacity | Storage and movement ability |
| Weapon (1H or 2H) | Damage + accuracy | Primary offense (accuracy is weapon-only) |
| Offhand | Utility / defense | Secondary ability (blocked by 2H) |

Slot domains keep drops instantly readable — gloves always tell you about attack speed; boots always tell you about traction. Universal rolls (`+HP`, `+resource`) appear on every equippable item; everything else stays inside the slot's domain or its domain-adjacent neighbors (armor pieces can roll damage reduction; weapons can roll stun chance and knockback; offhands roll stats specific to their archetype).

### Traction (boots only)

Traction is a single number 0–100 that governs how the player interacts with hostile ground — slip, slow, knockdown, and DoT pools. Both axes use the same staircased breakpoints, so one roll tracks both:

| Traction | Movement immunity unlocked | DoT damage reduction |
|---|---|---|
| < 25 | — | 0% |
| 25–49 | Slip-down chance | 25% |
| 50–74 | + Movement slow on hostile ground | 50% |
| 75–99 | + Knockdown on cracked floor / spike pads | 75% |
| 100 | + Full stride, immune to all ground effects | 100% |

The staircase is intentional: every breakpoint reads as "a tier earned" and the numeric jump is the moment that matters. Continuous reduction would dilute the breakpoint identity. **Only boots roll traction** — total = boots traction, no cross-slot stacking — so a player gearing into traction is making an explicit "feet matter" commitment, not accidentally accumulating it.

Traction does not replace per-element resistance. A fire pool still does damage through `fire_resistance` like any fire damage; traction layers on top as an additional reduction specifically for *ground-source* damage.

### Behavior mods *(design intent — not yet implemented)*

Each gear slot (excluding weapons and offhands, which define behavior through their base type) can roll one **behavior mod**. Mods are the identity layer — two chest pieces with identical stats but different mods play differently.

Principles: **mods change behavior, not just numbers**; **each mod has a tradeoff** (a jetpack backpack has fewer inventory slots — power costs something); **mods are rollable with their own parameters** (a jetpack might drain 18 or 26 resource per second depending on the roll); **~4 mods per slot** for variety without dilution.

Cross-slot synergies are emergent, not designed. A player who discovers a mod combination that works with their talent build has found their *build identity* — and that moment is what makes loot-driven games compelling.

### Power budget

Every item is generated against a power budget determined by item level and rarity. The budget is spent across base stat roll, mod quality, and affix count/quality. A powerful mod consumes more budget, leaving less room for strong stats or affixes. This single mechanism prevents degenerate items — every piece is internally balanced regardless of what specifically rolled.

## Item architecture

| Main type | Example sub types | Slot |
|---|---|---|
| 1H Weapon | Pistol, Revolver, SMG, Combat Knife, Shock Baton | Weapon |
| 2H Weapon | Assault Rifle, Shotgun, Sniper Rifle, Sledgehammer, Chainsaw | Weapon (locks offhand) |
| Offhand | Grenade, Sidearm, Shield Generator | Offhand |
| Head Armor | Helmet, Hood, Visor | Head |
| Chest Armor | Vest, Jacket, Plate Rig, Hardsuit | Chest |
| Hands | Work Gloves, Gauntlets, Interface Gloves | Hands |
| Leg Armor | Greaves, Cargo Pants, Exo-Leggings | Legs |
| Boots | Runners, Stompers, Mag-Boots | Feet |
| Backpack | Field Pack, Cargo Frame, Thruster Rig | Back |

### Weight system

Every item has a weight value. Total equipped weight affects movement speed: below the carry threshold, no penalty; above it, speed decreases proportionally. There is no armor "weight class" — each piece simply has a weight value, and the player optimizes their own trade-off.

### Rarity and modifiers

| Rarity | Color | Modifier density | Augment slots |
|---|---|---|---|
| Common | Gray | None | Very rare |
| Uncommon | Green | One affix (prefix OR suffix) | Low chance |
| Rare | Blue | Prefix + suffix | Moderate chance |
| Epic | Purple | Prefix + suffix + a unique non-stat special modifier | Higher chance |
| Legendary | Orange | Hand-crafted; fixed identity | Fixed (designed per item) |

Prefixes and suffixes draw from pools appropriate to the item's main type and sub type. Epic special modifiers are non-stat — unique mechanical effects ("kills restore HP", "Fire skill has a chance to not consume ammo"). Legendaries are entirely hand-authored.

Augment slots roll at drop time, weighted by item level and rarity. Augments do not scale — a laser sight is a laser sight, no "Laser Sight II". Their value comes from synergy with the item's stats, mod, and the player's build.

### Item-level effectiveness curve

Items don't get statically replaced when the player outlevels them. Every item carries an `item_level` rolled at generation, and the player's level determines an **effectiveness multiplier** applied to all combat-power stats on that item. This single mechanism replaces stat-squish patches — numerical ranges stay bounded because old items decay smoothly rather than being inflated past.

| Player vs. ilvl | Multiplier | Behavior |
|---|---|---|
| ilvl == player level | 1.00× | Drop is "for you" — hits its rolled values exactly |
| ilvl > player level | up to 1.50× ceiling | Linear boost, +1% per level above |
| ilvl < player level | asymptotic toward 0.30× floor | `1 / (1 + delta * 0.05)`. Never reaches zero — favorite items stay weakly viable |

The multiplier touches **power**: weapon damage rolls, attack speed, crit chance, accuracy, all stat-modifier bonuses (HP, damage reduction, knockback, resistances, shield pool). It does **not** touch:

- **Storage stats** (`inventory_bonus` on backpacks) — bag size shouldn't shrink as the player levels.
- **Feel/flavor stats** (`weapon_range`, `blast_radius`, light parameters) — these define what a weapon *is*, not how powerful it is.
- **Behavior mods** — a jetpack works as a jetpack regardless of ilvl gap. Mods are *identity*; the multiplier touches *power*.

Code-side: read combat values via `Item.get_effective_modifier()` or the typed `effective_*()` accessors. Storage and flavor reads stay on the raw `get_modifier()` path.

**Why this shape:** no stat bloat or squish (numbers stay bounded), build retention (favorite items stay viable longer), and a meaningful endgame chase (above-cap ilvl drops become the prize without breaking the base curve). The 30% floor is intentional — aggressive linear decay would punish novelty.

### Reforging (not yet implemented)

Players can pay credits at an NPC or station to **reforge** a selected item, raising its `item_level` to match the player's current level and restoring its effectiveness to 100%. This lets strong early drops stay relevant indefinitely — a well-rolled rare from floor 1 can be carried into endgame if the player invests credits to keep it current. The cost should scale with the level gap so reforging a slightly outdated item is cheap, but jumping a 20-level gap is a deliberate investment.

## Equipment

### Weapons

Categorized by **damage type** (energy / kinetic / elemental / melee, plus class-specific weapons gated by talent depth) and **handling** (1H or 2H). Damage type determines what enemies are vulnerable or resistant to. Handling determines whether the offhand slot is available.

- **1H weapons** define Fire only. Alt Fire comes from the offhand.
- **2H weapons** always define Fire. Alt Fire is *optional* — a sledgehammer has no alt fire, but an M4 has a grenade launcher. Augments can add an alt fire to weapons that don't have one natively.

Currently four base weapon types exist (`melee_1h`, `ranged_1h`, `melee_2h`, `ranged_2h`). Named sub-types (Pistol, SMG, Combat Knife, etc.) are future work — each new weapon type should change the player's tactical approach, not just provide different numbers.

### Offhands

Occupy the offhand slot when using a 1H weapon. Each offhand's `fire_skill` becomes the player's **Alt Fire**. Offhands are never just stat sticks — they always provide an active ability. Three archetypes:

- **Active hold** — RMB held while the effect is sustained (full block, beam, channel). Strong but committal.
- **Toggled buff** — RMB taps to grant a persistent player-side buff with its own pool / duration / cooldown.
- **Triggered fire** — RMB fires once per press at the cursor (grenade, sidearm shot).

This taxonomy is enforced in `prototype_player.gd`'s offhand handling — new offhands should slot into one of the three.

### Skill system: Fire and Alt Fire

Two weapon-based attacks available to every class from the start, before any class skills. They come from equipped gear and require no resource.

| Input | Attack | Source |
|---|---|---|
| Left click | **Fire** | Equipped weapon's primary skill |
| Right click | **Alt Fire** | Offhand skill (1H weapon) **or** weapon's secondary (2H, if it has one) |

LMB and RMB use independent busy flags (`_lmb_busy` and `_skill_busy`) — a player holding LMB to attack can also tap RMB without one cancelling the other.

Fire and Alt Fire can be modified by skill tree nodes (lifesteal on Fire, chained AoE on Alt Fire, status effects keyed to class identity) and by gear augments (laser sights, bayonets). Skill nodes and augments stack.

### Armor

Head, chest, hands, legs, feet. Each carries damage reduction and contributes to player weight. Each armor slot has a stat domain (see Itemization) and a pool of behavior mods. No discrete weight classes — heavier armor tends to have higher DR; lighter armor keeps the player fast. The player decides their own trade-off by mixing pieces.
