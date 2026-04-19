# Skill Tree

## Accessibility

The skill tree is locked and invisible until the player learns their first skill from the Level 1 rep encounter.

At that moment:

1. The skill tree opens automatically
2. The learned skill flashes into its position in the tree
3. The skill is assigned to the **1** hotkey

This makes the skill tree feel earned rather than presented — the player discovers it through play, not through a menu.

---

## Basic Attacks

Two basic attacks are available to every spec and the base class from the start of the game, before any rep encounter. They are not spec skills — they use the player's equipped weapons directly and require no resource.

| Input | Attack | Behavior |
|---|---|---|
| Left click | **Single target** | Attacks one enemy with the equipped weapon |
| Right click | **AoE** | Attacks nearby enemies with the equipped weapon |

Because basic attacks exist before the first rep encounter, the player can attempt to fight the first enemy. This fight is designed to be unwinnable — the enemy is too strong for basic attacks alone — but the player having the option to try makes the rep save more meaningful than pure scripted helplessness.

### Weapon Dependency

Basic attack behavior, range, and damage type are determined entirely by the equipped weapon. A player with a melee weapon and a player with a ranged weapon will experience fundamentally different basic attacks against the same enemy.

### Skill Tree Modifications

Basic attacks can be modified through skill tree nodes. Examples of the kinds of changes nodes might introduce:

- AoE radius increase
- Single target gains a lifesteal component
- Single target chains to a second nearby enemy
- AoE applies a status effect based on spec identity

These nodes allow basic attacks to remain relevant at all stages of the game rather than becoming obsolete once spec skills are unlocked.

---

## Tutorial Progression

The starting zone teaches the skill system through play across four phases. See [Starting Zones](starting-zones.md) for the full narrative context of each rep encounter.

### Phase 1: Basic Attacks Only (Pre-Level 1 rep encounter)

The player begins with no spec skills and no visible skill tree. Basic attacks are available but insufficient against the first enemy encounter. The player is overwhelmed — the Level 1 rep saves them, then teaches the first spec skill. The skill tree opens for the first time.

### Phase 2: One Skill Per Level (Levels 1–3)

Each subsequent rep encounter follows the same structure: save moment → skill taught → resource indicator revealed. By the end of Level 3, the player has:

- 3 spec skills, one per spec
- 3 resource indicators, one per spec

The goal is to give the player a practical feel for what each spec's resource system demands before they make a permanent choice.

### Phase 3: The Proving Ground (Level 4)

Level 4 is cleared using all three skills. No new abilities are introduced. This level exists to let the player internalize the three skill styles together before the Confrontation forces a permanent choice.

### Phase 4: After Spec Selection

When the player chooses a spec at the [Confrontation](starting-zones.md#the-confrontation):

- The two unchosen skills are **permanently removed**
- Their resource indicators disappear from the HUD
- The chosen spec's skill and resource indicator remain as the foundation for further progression

**Base class exception:** Players who take the base class path retain all three skills and all three resource indicators. This is the mechanical reward for the hardest path — breadth over depth.

---

## The Six Starting Skills

Each skill is taught immediately after the rep's save moment — the ability the player receives is a direct reflection of what they just witnessed.

**Cyborg**

| Spec | Skill | Description | Resource |
|---|---|---|---|
| Forged | **Buzzsaw** | Melee arc attack. Deals slicing damage and applies a bleed DoT. | Power Grid |
| Automaton | **Autoturret** | Toggle. A turret forms on the player's shoulder and auto-attacks nearby enemies for small/medium piercing damage. Consumes 90% of Bandwidth while active — the drain is intentional, so the player immediately understands what the resource does. | Bandwidth |
| Polymath | **DDoS** | Large single-target damage. Deals bonus damage vs. mechanical enemies. | Memory + CPU |

**Human**

| Spec | Skill | Description | Resource |
|---|---|---|---|
| Survivalist | **IED** | Scavenge nearby corpses or destructibles to craft an improvised grenade dealing medium AoE damage. Damage type is determined by what was scavenged. | Adrenaline |
| Gentleman / Lady | **Malice** | Attack with the equipped weapon for bonus damage. Each consecutive hit deals additional damage on top of the last. | Composure |
| Enculted | **Blaspheme** | Curse a target. Flesh-based enemies take increased damage and deal reduced damage for the curse's duration. | Sanity |

---

## Skill Hotkeys

| Hotkey | Assignment |
|---|---|
| Left click | Basic single target attack |
| Right click | Basic AoE attack |
| 1 | First rep skill (assigned automatically on unlock) |
| 2–? | Subsequent skills (TBD) |

---

## Open Questions

!!! question "Open Questions"
    - How many hotkey slots does each spec have beyond slot 1?
    - Are skill tree nodes unlocked through leveling, currency, or both?
    - Can nodes be refunded within a spec, or is the tree permanent once committed?
    - Do basic attacks have any visual variation per spec, or are they visually identical across all specs?
    - Does the AoE basic attack behave differently for melee vs. ranged weapons (e.g., melee = spin, ranged = burst fire)?
