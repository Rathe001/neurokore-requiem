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
