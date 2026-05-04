# Status

This is an early prototype. Code is the source of truth for what currently works — `git log` and the scripts under `game/scripts/` are more accurate than any status writeup could stay.

## Open design areas

These are intent gaps, not implementation gaps. They influence what we choose to build next; they're written here so future sessions don't have to re-derive them.

- **Origin-class tier perks.** Specialist class perks (Exile, Amalgamation, Drone Swarm, IED, Telekinesis, Doomsayer) define their identities; balanced Analog / Cyborg need their own perks. The intent is "balance has its own reward," but the specific perks haven't been designed.
- **Class-specific stat functions.** Each class's main stat scales damage; most also need a non-damage mechanical function tied to class fantasy (Forged's "extra arms" is the precedent — others TBD).
- **Opposing-stat distortion.** The friction model says opposing stats *distort* rather than punish. What that distortion looks like per-class hasn't been written.
- **Soul / Interface governance.** Derived stats need a load-bearing role beyond "average of three kore stats" — candidates include resilience for Soul, cooldown smoothing for Interface.
- **Visual metamorphosis pipeline.** Mesh kits, shader channels, VFX layers per class — how the art system actually delivers tier-driven body transformation.
- **Progression / leveling cadence.** XP curve, talent point cadence, level cap behavior.
- **Economy / crafting.** Currency sinks, vendor model, schematic system, augment integration.
- **End-game loop.** What does the game look like after the campaign? Endless? Procgen mod-stacking? Trial-and-build?
- **Death / failure.** Permadeath? Run-based? Checkpoint? Has narrative weight implications.
- **Morality system.** [On hold](design/morality-system.md). May resurface as a hidden narrative system rather than a player-facing axis.
