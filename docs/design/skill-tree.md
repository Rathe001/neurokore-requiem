# Skill Tree

## Accessibility

The skill tree is locked and invisible until the player learns their first skill from the Level 1 rep encounter.

At that moment:

1. The skill tree opens automatically
2. The learned skill flashes into its position in the tree
3. The skill is assigned to the **1** hotkey

This makes the skill tree feel earned rather than presented — the player discovers it through play, not through a menu.

---

## Fire & Alt Fire

Two weapon-based attacks are available to every class from the start of the game, before any rep encounter. They are not class skills — they come from the player's equipped gear and require no resource.

| Input | Attack | Source |
|---|---|---|
| Left click | **Fire** | Weapon's `fire_skill` (1H or 2H) |
| Right click | **Alt Fire** | Offhand's `fire_skill` (1H weapon) **or** weapon's `alt_fire_skill` (2H weapon, if present) |

Weapons are either **one-handed** or **two-handed**:

- **1H weapon** — defines only Fire. Alt Fire comes from whatever is in the offhand slot (shield bash, grenade toss, sidearm shot, etc.). The offhand item carries its own `fire_skill` that becomes the player's Alt Fire.
- **2H weapon** — always defines Fire. Alt Fire is **optional** — an M4 carbine has an underslung grenade launcher, but a sledgehammer has no alt fire. Augments can add an alt fire to 2H weapons that lack one natively. Equipping a 2H weapon displaces the offhand and locks the slot.

Each weapon and offhand carries its own `Skill` resources that define damage, range, targeting mode, cooldown, and knockback. Swapping gear changes your basic combat behavior immediately — a pipe wrench fires differently than a shock baton, a buckler alt-fires differently than a pistol offhand.

Because Fire and Alt Fire exist before the first rep encounter, the player can attempt to fight the first enemy. This fight is designed to be unwinnable — the enemy is too strong for weapon attacks alone — but the player having the option to try makes the rep save more meaningful than pure scripted helplessness.

### Weapon & Offhand Dependency

Fire and Alt Fire behavior, range, and damage type are determined entirely by equipped gear. A player with a melee weapon and a player with a ranged weapon will experience fundamentally different attacks against the same enemy. A 1H melee weapon paired with a grenade offhand plays completely differently than a 2H rifle with a built-in launcher — even though both use the same Fire / Alt Fire inputs. See [Equipment](equipment.md) for the full weapon, offhand, and armor taxonomy.

### Skill Tree Modifications

Fire and Alt Fire can be modified through skill tree nodes. Examples of the kinds of changes nodes might introduce:

- Alt Fire radius increase
- Fire gains a lifesteal component
- Fire chains to a second nearby enemy
- Alt Fire applies a status effect based on class identity

These nodes allow weapon attacks to remain relevant at all stages of the game rather than becoming obsolete once class skills are unlocked.

Fire and Alt Fire can also be altered by [gear augments](gear-augmentation.md) — e.g., a laser sight augment adds a targeting beam, a bayonet changes a ranged weapon's melee fallback. Skill tree nodes and augments stack.

!!! note "Skill tree vs. tier perks"
    Skill tree nodes are a separate system from [stat identity tier perks](attribute-system.md#stat-identity--tier-perks--visual-metamorphosis). Skill tree nodes are unlocked through progression within the chosen class. Tier perks are driven by attribute distribution (gear) and can be gained or lost at any time. The skill tree *does* interact with attributes through the [team stat scaling mechanic](attribute-system.md#team-stat-scaling--skill-tree-mechanic) (lowest/average/highest).

---

## Tutorial Progression

The starting zone teaches the skill system through play across four phases. See [Starting Zones](starting-zones.md) for the full narrative context of each rep encounter.

### Phase 1: Fire & Alt Fire Only (Pre-Level 1 rep encounter)

The player begins with no class skills and no visible skill tree. Fire and Alt Fire are available from equipped gear but insufficient against the first enemy encounter. The player is overwhelmed — the Level 1 rep saves them, then teaches the first class skill. The skill tree opens for the first time.

### Phase 2: One Skill Per Level (Levels 1–3)

Each subsequent rep encounter follows the same structure: save moment → skill taught → resource indicator revealed. The player only encounters the three reps of their starting origin. By the end of Level 3, the player has:

- 3 class skills, one for each specialized class of their origin
- 3 resource indicators, one for each specialized class of their origin

The goal is to give the player a practical feel for what each class's resource system demands before they make a permanent choice.

### Phase 3: The Proving Ground (Level 4)

Level 4 is cleared using all three skills. No new abilities are introduced. This level exists to let the player internalize the three skill styles together before the Confrontation forces a permanent choice.

### Phase 4: After Class Selection

When the player chooses a class at the [Confrontation](starting-zones.md#the-confrontation):

- The two unchosen skills are **permanently removed**
- Their resource indicators disappear from the HUD
- The chosen class's skill and resource indicator remain as the foundation for further progression

**Origin class exception:** Players who take the origin class path retain all three skills and all three resource indicators. This is the mechanical reward for the hardest path — breadth over depth.

---

## The Six Starting Skills

Each skill is taught immediately after the rep's save moment — the ability the player receives is a direct reflection of what they just witnessed.

**Cyborg-origin**

| Class | Skill | Description | Resource |
|---|---|---|---|
| Forged | **Buzzsaw** | Melee arc attack. Deals slicing damage and applies a bleed DoT. | Power Grid |
| Automaton | **Autoturret** | Toggle. A turret forms on the player's shoulder and auto-attacks nearby enemies for small/medium piercing damage. Consumes 90% of Bandwidth while active — the drain is intentional, so the player immediately understands what the resource does. | Bandwidth |
| Polymath | **DDoS** | Large single-target damage. Deals bonus damage vs. mechanical enemies. | TBD |

**Human-origin**

| Class | Skill | Description | Resource |
|---|---|---|---|
| Survivalist | **IED** | Scavenge nearby corpses or destructibles to craft an improvised grenade dealing medium AoE damage. Damage type is determined by what was scavenged. | Adrenaline |
| Gentleman / Lady | **Malice** | Attack with the equipped weapon for bonus damage. Each consecutive hit deals additional damage on top of the last. | Composure |
| Enculted | **Blaspheme** | Curse a target. Flesh-based enemies take increased damage and deal reduced damage for the curse's duration. | TBD |

---

## Skill Hotkeys

| Hotkey | Assignment |
|---|---|
| Left click | Fire (weapon primary) |
| Right click | Alt Fire (offhand or weapon secondary) |
| 1 | First rep skill (assigned automatically on unlock) |
| 2–? | Subsequent skills (TBD) |

---

## Open Questions

!!! question "Open Questions"
    - How many hotkey slots does each class have beyond slot 1?
    - Are skill tree nodes unlocked through leveling, currency, or both?
    - Can nodes be refunded within a class, or is the tree permanent once committed?
    - Do Fire/Alt Fire have any visual variation per class beyond what the weapon defines?
    - Should certain offhand types be restricted to specific classes (e.g., only Enculted can use cursed offhands)?
