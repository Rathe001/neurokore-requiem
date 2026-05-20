---
name: xbot-ragdoll
description: X Bot death = random Mixamo death animation + tween-knockback + lazy ragdoll on explosion. Solved differently than originally planned.
type: project
originSessionId: 82d6aba9-5758-48bf-8247-4867da37ca36
---
**Status (2026-05-19): resolved by abandoning physics-driven death.** Per-bone ragdoll setup still exists but is no longer the death visual — Godot 4.6.2's `PhysicalBoneSimulator` initialises every rigid body from the bone's REST pose (T-pose for Mixamo) regardless of any pre-start state we set, so corpses snapped to T-pose at activation. Six different workaround approaches all failed (`stop(true)`, `process_mode = DISABLED`, `pb.transform` pre-start, `set_bone_pose_*` lock, `pb.global_transform` post-start, `set_bone_rest` swap — each either didn't change the snap or introduced Jolt non-uniform-scale errors).

**Current death flow** (`PrototypeEnemy._die`):

1. **Random Mixamo death animation** from `XBotAnimations.random_death_anim()`. Six clips load into the library as `death_0`-`death_5`: "Death", "Death From The Front", "Death From Right", "Flying Back Death", "Standing Death Backward 01", "Standing Death Forward 01". Non-looping, holds final frame.
2. **Knockback tween** on the CharacterBody3D's `global_position` over `_KNOCKBACK_DURATION=0.55s`. X/Z slide is cubic ease-out (~0.9 m / kill_force, clamped to 15m), Y is a two-stage parabolic arc (quad-out up to peak, quad-in back down). Bodies actually launch and arc on big hits.
3. **Baseline knockback for normal weapons**: most weapon skills have `knockback = 0` by design (no mid-combat push). At kill time, if `knockback_strength <= 0`, the death code derives a baseline from damage: `clampf(damage * 0.4, 3.0, 25.0)`. Sniper-class hits get force ≈ 20; trash-mob chip damage gets force ≈ 3.
4. **Lazy ragdoll on explosion** — corpse joins `&"ragdoll_corpses"` group at death. `apply_explosion_impulse(origin, force)` lazily runs `XBotRagdoll.setup` + `activate` on first call, then `await get_tree().physics_frame` (apply_central_impulse on a body that hasn't yet been simulated is silently dropped), then applies impulse to every PhysicalBone3D with `force * mass * falloff * _EXPLOSION_FORCE_MULT(=8.0)` plus strong upward bias. The T-pose snap on activation is hidden by the immediate explosive motion.

**Group iteration was a separate bug**: `PrototypeGrenade._detonate` and `PrototypeProjectile`'s blast path both cast to `PrototypeRagdollCorpse` when walking the group, which silently filtered out X Bot enemies (which are `PrototypeEnemy`). Fixed by duck-typing — `c.has_method(&"apply_explosion_impulse")`. Both corpse types coexist in the same group.

**Player does NOT collide with corpses** — player.tscn `collision_mask = 195` (no layer 6 / Corpses bit 32). Bodies are visual-only against the player; explosions are the only interaction.

**What `XBotRagdoll.setup` / `activate` still does** (still used for lazy explosion ragdoll):

- `setup(skeleton)`: adds 20 PhysicalBone3D children with capsule shapes, anatomical mass (hips 12kg → hands 0.8kg), cone joints (swing 90°, twist 60°). Layer 6 (Corpses), mask 1 (World). Idempotent via `xbot_ragdoll_setup` meta. **No longer called from `_ready`** — invoked lazily by `apply_explosion_impulse` to save the per-enemy memory on living enemies. Cone-twist `bias` / `softness` / `relaxation` params are NOT set because Jolt rejects them with warnings — only `swing_span` and `twist_span`.
- `activate(skeleton, kill_from, kill_force)`: orthonormalizes each PB basis (Mixamo bind-matrix scale residue would otherwise spam Jolt warnings), syncs each `pb.transform` to bone global pose, calls `physical_bones_start_simulation`. Caller now passes `Vector3.ZERO, 0.0` for the impulse because we apply it ourselves per-bone in `apply_explosion_impulse`.

**New-mesh trap (2026-05-20)**: non-X-Bot Mixamo meshes (vanguard, alien, military_man, crypto, player_male, player_female) import with tiny non-uniform scale baked into the visual ancestor chain above the skeleton. Every PhysicalBone3D inherits that scale at attach AND at activation, spamming `_try_build_shape: Failed to correctly scale body` once per limb per spawn (5000+ in a short playtest). Per-PB counter-scale in `setup()` / `activate()` partially helps but ONLY for axis-aligned parent bases — Mixamo bone rotations break the component-wise inverse, and `physical_bones_start_simulation` overwrites the compensation every frame anyway, so the warning keeps spamming during sim.

**Real fix (2026-05-20)**: `XBotRagdoll.normalize_parent_chain_scale(skel, stop_at)` walks from the skeleton up through every Node3D ancestor (stopping before `stop_at`, usually the `Visual` node) and replaces any non-uniform basis with `orthonormalized().scaled(Vector3.ONE * avg_of_three_axis_scales)`. One-time at spawn (idempotent via `xbot_ragdoll_chain_normalized` meta). After this the parent chain is uniform forever, and Jolt sees uniform global scale on every PB child. Called from `PrototypeEnemy._apply_class_mesh` after the mesh swap and from `PrototypePlayer._apply_gender_appearance` after the gender swap. Per-PB counter-scale in `setup()` / `activate()` is still in place as a belt-and-suspenders fallback, but the chain normalize is what actually silences the warnings.

**Companion fix in the same file**: `XBotRagdoll.ensure_surface_materials(root)` recursively assigns a bland default `StandardMaterial3D` to any MeshInstance3D surface whose `get_active_material()` returns null. Silences the RenderingServer `material_casts_shadows: Parameter "material" is null` spam from FBX sub-meshes that imported without a material slot. Called from the same two swap paths.

**Tuning constants** in `prototype_enemy.gd`:
- `_KNOCKBACK_DURATION` (0.55s) — total launch duration
- `_KNOCKBACK_DISTANCE_PER_FORCE` (0.9 m/force) — slide distance
- `_KNOCKBACK_MAX_DISTANCE` (15m) — slide clamp
- `_KNOCKBACK_ARC_HEIGHT_PER_FORCE` (0.22 m/force) — peak arc height
- `_KNOCKBACK_ARC_HEIGHT_MAX` (5m) — arc clamp
- `_EXPLOSION_FORCE_MULT` (8.0) — explosion impulse scale on top of force × mass × falloff

**If returning to physics ragdoll** (e.g. Godot fixes the rest-pose-init quirk in a future version): the lazy-activate path in `apply_explosion_impulse` already does it. Move the `XBotRagdoll.setup` + `activate` call to fire on death anim finish instead of explosion to make corpses pushable by player movement.
