# Automaton *(mid-range)*

**Fantasy:** command the machine through AI scripting and a fleet of drones. Set conditions, automate responses, build a system that fights alongside you.

**Attribute:** Optimization — precision and efficiency of machine control. Opposes Ingenuity. See [Attribute System](../../design/attribute-system.md).

**Tier perks — Drone Swarm.** **2 / 3 / 5** untargetable hover drones wander semi-randomly near the player and auto-fire on enemies in range. Drones collide with walls (won't shoot through them) but are invulnerable. Damage scales with Optimization. Future Mainboard chips will modify drone behavior.

**Resource: Bandwidth** — caps how many drones/scripts can run simultaneously.

- **Drones as script hosts** — each script runs on a drone; drone type defines what scripts it can run. Losing a drone loses that script until redeployed.
- **Scripts are loot** — condition/response pairs (e.g. `IF surrounded by 3+ → shockwave`). Drone chassis are loot too — chassis + script together define the build.
- **Overflow/crash:** running too many risks cascade failure. High risk ceiling.

> Drone types (combat / swarm / shield / repair / recon / EMP) are design space — current implementation is one generic combat drone. Drone-type variety is an open question.
