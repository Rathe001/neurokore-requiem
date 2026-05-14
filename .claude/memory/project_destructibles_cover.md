---
name: Destructible clutter + cover invariants
description: Destructible collision height is decoupled from mesh size; cover props block both crouch AND standing fire; projectile sweep raycast routes PILLAR-layer hits to damage path
type: project
---

The cover + clutter system landed in v0.3.0. Three invariants that bit us during development and aren't obvious from reading any single file:

**Destructible collision is invisible-tall.** `ClutterBuilder._make_destructible_shape` always builds a 1.6m-tall shape regardless of the visual mesh height (set via `DESTRUCTIBLE_COLLISION_HEIGHT`). Otherwise player fire at 1.0m flies clean over a 0.7m crate and the prop never breaks. Mesh size and collision size are intentionally separate — don't unify them.

**Layer flow (revised 2026-05-14):** Destructibles sit on `PILLAR (128)` only — NOT on `ENEMY (2)`. Indestructible cover sits on `WORLD (1) | PILLAR (128)`. Enemy mask drops PILLAR specifically so enemies physically phase through destructible clutter (they were getting stuck on knee-high chairs whose 1.6m bullet-catch column was a wall to the AI). Player mask was bumped to include PILLAR so the player still bumps cover. Cover-blocking-LOS still works for everyone since the LosCuller's combat ray masks PILLAR. The `provides_cover` flag on the destructible def is now decorative — every destructible has the same 1.6m chest-height collision, so all of them block bullets and combat LOS at standing height.

**Projectile sweep raycast routes PILLAR hits through `_on_body_entered`.** `prototype_projectile.gd:_physics_process` does a per-frame sweep raycast against `PROJECTILE_WORLD_MASK = WORLD | PILLAR` to prevent thin-wall tunneling. When that sweep's collider is in the projectile's `target_group` (i.e. a destructible in `&"enemies"`), it forwards to `_on_body_entered` so damage actually lands — otherwise the prop would block bullets but never take damage. If you add another "shootable thing on PILLAR layer," it needs to be in the appropriate target group (`&"enemies"` for player-shootable) or this routing silently skips it.

**Why:** Player projectiles spawn at 1.0m chest height. Visual props need to stay short (0.4-0.9m) to read as cover-able. The bullet-catch column is the bridge.

**How to apply:** New destructible types go through `ClutterBuilder._create_destructible` — don't hand-build the collision shape. Adding a new shootable static body (turret, terminal-with-HP, etc.) needs `&"enemies"` group membership plus a `take_damage` method, or the sweep raycast will treat it as wall. Putting any new "enemies should physically phase through this" prop on PILLAR-only follows the same pattern; if you want a prop that blocks enemy movement (hard obstacle), put it on WORLD too like indestructible cover.
