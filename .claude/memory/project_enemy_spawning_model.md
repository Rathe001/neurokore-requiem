---
name: Enemy spawning follows D2 model, not horde-streaming
description: Levels have pre-placed enemies at load time, no runtime respawn, fully clearable — architectural constraint that rules out Vampire Survivors-style streaming systems
type: project
originSessionId: 22dbe090-8006-4f89-8d5b-a0309affea09
---
Enemies are placed at level load and do not respawn during play. Players can fully clear a level.

**Why:** Diablo 2 style is the reference. This is a deliberate design choice confirmed 2026-04-19 after user played the prototype's timer-based horde spawner and noted the real model is different. The "horde density" platform concern (per `docs/design/platform.md`) is about enemy *counts* on screen, not continuous streaming.

**How to apply:**
- The current `EnemySpawner` in `game/scenes/world.tscn` is a temporary density stress-test, not the target architecture. Don't build features on top of it that assume continuous spawning.
- Future enemy systems should assume: placement-at-load, defeated-stays-defeated, level-complete-when-cleared.
- Pooling/spatial-partitioning work for horde density still matters, but the pool fills from level data, not a streaming source.
- If persisting cleared state across save/load comes up, that belongs with this model too.
