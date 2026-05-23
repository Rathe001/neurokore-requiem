---
name: project_shell_casing_eject
description: "Spent shells eject from the gun on fire — captured shotgun mesh + procedural cylinders for sniper/lmg/smg, scripted ballistic arc, per-weapon delays."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`ShellCasing` (`game/scripts/characters/shell_casing.gd`) — scripted `Node3D` with mesh + manual ballistics (no RigidBody3D — casings are visual flair and shouldn't tie up Jolt during a firefight). Lifetime 3.5s, alpha fade starts at 2.5s.

Brass material with a brief emission "hot from firing" peak (2.5× energy) that decays to zero over 80ms — visible flash at the muzzle, then pure metallic specular afterwards. The casing reads against dark floors via the level's PBR roughness/specular response without persistent glow.

Bounces on the floor with `BOUNCE_DAMP = 0.25` / `HORIZONTAL_DAMP = 0.4` — settles within a couple of hops. Ground plane is wrist_y - 1.5m (approximate floor for an X Bot rig); on stairs / raised platforms casings may hover or sink slightly. If that becomes a problem, swap to a downward raycast on spawn.

**WeaponAttachment** owns the spawn pipeline:
- `_HIDDEN_MESHES` — on attach, hide the shotgun's `bullet` sub-mesh (the embedded casing under the breech) and capture its Mesh resource for reuse.
- `_EJECT_VARIANTS` — `shotgun_2h → shotgun_capture`, `sniper_2h → sniper`, `lmg_2h → lmg`, `smg_1h → smg`. Energy weapons (laser/plasma/accelerator/taser), RPG, and melee aren't in the dict — they don't eject.
- `_EJECT_DELAYS` — shotgun 0.5s (pump-action sell), others 0.0s (instant). When delay ≤ 0, `_spawn_casing` runs synchronously; otherwise SceneTreeTimer with `instance_from_id` capture (see [[project_lambda_capture_freed]]).
- Procedural cylinders for sniper / lmg / smg, sized in that order. Built lazily on first request and cached.

`PlayerCombat._eject_casing(weapon)` is called immediately after every `CombatVisuals.spawn_muzzle_flash` in the 5 firing paths (projectile, hitscan, projectile_exact, shotgun, hitscan_exact). For weapons not in `_EJECT_VARIANTS`, the call is a no-op.

Related: [[project_weapon_attachment]] (the mount system underneath), [[project_lambda_capture_freed]] (SceneTreeTimer + instance_from_id pattern).
