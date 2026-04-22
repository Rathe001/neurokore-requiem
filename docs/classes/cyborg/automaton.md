# Automaton *(mid-range)*

**Fantasy:** command the machine through AI scripting and a fleet of drones. Set conditions, automate responses, build a system that fights alongside you.

**Attribute:** Optimization — precision and efficiency of machine control. Opposes Ingenuity. See [Attribute System](../../design/attribute-system.md).

**Tier perks:** Stacking Optimization unlocks additional drones per tier. See [Stat Identity](../../design/attribute-system.md#stat-identity--tier-perks--visual-metamorphosis).

**Resource: Bandwidth** — caps how many drones/scripts can run simultaneously.

- **Drones are the physical expression of scripts** — each script runs on a drone. The drone type determines what the script can do. Losing a drone means losing that script until redeployed.
- **Scripts are loot items** — each defines a condition/response pair (e.g. `IF surrounded by 3+ enemies → shockwave`). Finding a new script reshapes your build.
- **Drone chassis and components are also loot** — drone items + script items together define the build. Finding a rare drone blueprint is the equivalent of a D2 runeword enabler.
- **Script decay → drone damage** — scripts degrade because drones take damage in combat. You're actively managing a fleet under fire.
- **Overflow/crash:** running too many scripts/drones risks cascade failure. High risk, high reward ceiling.

### Drone Types

| Drone | Role |
|---|---|
| Combat | Offensive, prioritize targets |
| Swarm | Large numbers of small, weak micro-drones. Fits end-game horde scale. |
| Shield | Orbit the player and intercept incoming projectiles |
| Repair | Sustain and healing utility |
| Recon | Extend vision range, reveal enemies, mark targets |
| EMP/Hack | Disable enemy augmentations or temporarily take control of enemies |

!!! question "Open Questions"
    - Permanent companions vs. deployed/recalled on demand?
    - Is there a default starter drone, or is the fleet built entirely through loot?
    - Visual style of drones: sleek corporate hardware, cobbled junk drones, or something more organic/grotesque?
