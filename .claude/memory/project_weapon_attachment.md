---
name: project_weapon_attachment
description: WeaponAttachment helper mounts visible weapon glb on X Bot right-hand bone for player + enemies; per-weapon grip offsets are placeholders that need in-game tuning
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`game/scripts/characters/weapon_attachment.gd` — static RefCounted helper. Idempotent `set_weapon(skeleton, weapon_base_id)` and enemy alias `set_weapon_for_enemy(skeleton, enemy_weapon_id)` mount/swap/clear a glb on a BoneAttachment3D parented to the skeleton's right-hand bone (`mixamorig_RightHand`, fallback `RightHand`). Player calls into it from `_on_equipment_changed(slot==&"weapon")` and the tail of `_apply_gender_appearance` (gender swap rebuilds the skeleton). Enemy calls from `_init_enemy` right after `_apply_class_mesh()` — done outside `_apply_class_mesh` so a pooled enemy that kept its mesh but changed class still gets the right weapon.

`_WEAPON_MODELS` keys on canonical `weapon_base_id` (`ranged_2h` → `plasma_rifle.glb`, etc.); `_ENEMY_WEAPON_ID_ALIAS` maps `EnemyClass.weapon_id` model-names (`blade`, `sledgehammer`, `sniper_rifle`) onto the canonical keys, because the two namespaces drifted before the wiring landed.

Auto-scale: model's longest AABB axis is fit to `_CLASS_TARGET_LENGTH` per weapon class (pistol 0.32m, rifle 0.95m, melee_1h 0.95m, melee_2h 1.25m). This normalises wildly different source-glb scales (laser_pistol ships at ±3 units, plasma_rifle at ±0.5, blade at ±0.66). After auto-scale, the per-weapon `_GRIP` dict adds `pos` / `rot` / `scale_mult` fine-tune — **all 11 weapons now tuned by hand via the live grip tuner.** The live tuner stays shipped (F9 inspect mode + T toggle) for future weapons.

**Grip tuner (F9 → T in inspect mode).** Static API on `WeaponAttachment` is mutable `_GRIP`, `bump_rotation(base_id, axis, delta_deg)`, `bump_position(base_id, axis, delta)`, `bump_scale(base_id, factor)`, `bump_muzzle(base_id, axis, delta)`, `reset_grip(base_id)`, `reapply_grip(skeleton, base_id)`, `dump_grip_to_console(base_id)`. PrototypeCamera handles the keybinds: J/L/U/O/H/K for rotation, arrows + ,/. for position, -/= for scale, 5/6/7/8/9/0 for muzzle offset, P dumps to console, Backspace resets. The HUD label shows live values.

**Per-weapon muzzle override.** `_GRIP[base_id].muzzle` (Vector3, defaults ZERO) lets the user override the AABB-corner heuristic with an explicit world-distance-along-rotated-axes offset from the model origin. Use when the AABB heuristic picks the wrong corner (laser pistol's dangling cables, smg's many sub-meshes, etc.). `get_muzzle_position(skel, aim_world)` reads the override via `_weapon_base_id_from_model(mount)` which pulls the base_id from a `set_meta(&"weapon_base_id", ...)` stamp on the model — the original `model.scene_file_path` lookup was empty on glb-instantiated PackedScenes.

**Missing-texture fallback.** Sniper glb ships geometry-only (~218 KB vs ~6 MB for the textured weapons). `_backfill_missing_materials(model)` walks the mounted model's MeshInstance3D surfaces and assigns a dark metal StandardMaterial3D to any surface that has no material at either the override or mesh-baked level. Reads as gunmetal instead of default-pink-white.

**Live debug marker.** PrototypeCamera builds a magenta sphere at world-space `get_muzzle_position(skel, player_forward)` while inspect + tune mode are both on. Lets the user see whether the override actually moves the muzzle (because the HUD numbers update regardless of whether the value flows through to the consumer — the marker is the source of truth).

After `set_weapon`, the player calls `_walk_player_visual_layers(mount, ...)` + `_apply_player_visual_layer_recursive(mount)` to put the weapon mesh on layer 2 + CHARACTER_BLOOD_LAYER + PLAYER_VISUAL_LAYER (matches the body). Enemy does the same minus the player visual layer. Without this the freshly-mounted model defaults to render layer 1, which would attract floor blood decals and self-shadow under equipped lights.

**MP note (acknowledged limitation):** for remote MP avatars, the player path reads the local `InventoryState.get_equipped(&"weapon")`, so remote peers show whatever weapon the local player holds — same as the pre-existing `_equipped_weapon_class()` animation gap. Enemy path replicates correctly because `enemy_class` is synced. Fix waits on full weapon-loadout replication; flag in the changelog when revisiting.

Related: [[project_xbot_character]] (shared X Bot skeleton); [[project_xbot_ragdoll]] (BoneAttachment3D survives ragdoll because it follows the bone, weapon stays in hand during death); [[project_looping_anim_hold]] (Phase 2 stance animations are why this had to exist — empty hand looked wrong against rifle-aim poses).
