# Status

This is an early prototype. Code is the source of truth for what currently works — `git log` and the scripts under `game/scripts/` are more accurate than any status writeup could stay.

## Open design areas

These are intent gaps, not implementation gaps. They influence what we choose to build next; they're written here so future sessions don't have to re-derive them.

- **Origin-class tier perks.** Specialist class perks (Exile, Amalgamation, Drone Swarm, IED, Telekinesis, Doomsayer) define their identities; origin Analog / Cyborg need their own perk ladders for the 5-tier system. The intent is "breadth has its own reward," but the specific perks haven't been designed.
- **Talent tree structure.** How many nodes per tier? What's the branching shape? Are there hard gates between tiers or soft progression? The 5-tier (I–V) framework is decided; the tree topology isn't.
- **Behavior mod pools.** Each gear slot needs ~4 mods designed. Backpack is the most fleshed out; other slots have representative examples but need full design passes. See [Itemization](design/itemization.md).
- **Visual metamorphosis pipeline.** Mesh kits, shader channels, VFX layers per class — how the art system actually delivers tier-driven body transformation. Now driven by talent depth rather than stat distribution.
- **Progression / leveling cadence.** XP curve, talent point cadence, level cap behavior.
- **Economy / crafting.** Currency sinks, vendor model, schematic system, augment integration.
- **End-game loop.** What does the game look like after the campaign? Endless? Procgen mod-stacking? Trial-and-build?
- **Death / failure.** Permadeath? Run-based? Checkpoint? Has narrative weight implications.
- **Morality system.** [On hold](design/morality-system.md). May resurface as a hidden narrative system rather than a player-facing axis.
- **Power budget tuning.** The budget-per-item-level curve needs to be designed and a simulation tool built to catch balance outliers before they reach players.
