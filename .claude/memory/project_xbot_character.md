---
name: xbot-character-pipeline
description: "Mixamo X Bot is the humanoid mesh + animation source for player and enemies. FBX-per-clip + shared BoneMap + runtime AnimationLibrary merge. Per-FBX retarget config sits in each .fbx.import's _subresources."
type: project
---

**Source.** Mixamo's free X Bot humanoid + animation packs power
the player and humanoid enemies. The mesh + BoneMap live in
`game/assets/characters/x_bot/`; animation FBXs live in
`game/assets/animations/<category>/` (core, deaths, melee 1h,
melee 2h, ranged 1h, ranged 2h, skills, unarmed, misc, gestures,
swimming).

All animation FBXs downloaded **"Without Skin"** so they're
motion-only (~10× smaller than skinned).

**Bone naming.** Godot 4.6's ufbx importer (`fbx/importer=0`) reads
Mixamo's `mixamorig:Bone` names and rewrites `:` to `_`, so runtime
bone names are `mixamorig_Hips`, `mixamorig_LeftArm`, etc. ufbx
handles cm→m unit conversion natively, so `nodes/root_scale=1.0`
is correct — explicitly setting 0.01 (the old FBX2glTF habit) makes
a 1.78cm enemy invisible at iso distance.

**BoneMap.** `x_bot_bonemap.tres` maps every humanoid profile bone
to its `mixamorig_*` counterpart. Assigned per-FBX via the
`.fbx.import` file's `_subresources["nodes"]["PATH:Skeleton3D"]
["retarget/bone_map"]` field. **Critical**: every animation FBX
needs the same BoneMap assigned, otherwise its tracks don't retarget
onto the X Bot skeleton. New user-dropped FBXs start with
`_subresources={}` and need the retarget block injected — see the
Python helper pattern used in the animation-folder reorg commits.

**Animation library.** `xbot_animations.gd` is a static helper that
preloads all clip FBXs, extracts the first non-RESET animation from
each, duplicates + loop-flags it, applies hip-strip, and assembles a
single `AnimationLibrary` under the name `"xbot"`. Cached at class
level — `get_library()` builds once on first call. `install_on(ap)`
adds the library idempotently. Library keys are qualified at lookup
time as `"xbot/<key>"`.

**Per-weapon-class stance overlays (Phase 2 — shipped).** Beyond the
universal locomotion + combat clips, the library carries per-class
idle/walk/run + class attack so swapping weapons swaps the visible
stance. Five classes:

| Class id    | Source pack       | Library keys |
|-------------|-------------------|--------------|
| `pistol`    | Pistol Locomotion | `pistol_idle`, `pistol_walk`, `pistol_run`, attack uses universal `fire` |
| `rifle`     | Pro Rifle Pack    | `rifle_idle`, `rifle_walk`, `rifle_run`, attack uses universal `fire` |
| `melee_1h`  | Sword + Shield    | `sword_idle`, `sword_walk`, `sword_run`, `sword_slash` |
| `melee_2h`  | Melee Axe         | `axe_idle`, `axe_walk`, `axe_run`, `axe_swing` |
| `unarmed`   | (none — universal)| Falls back to `idle`/`jog`/`punch`. Unarmed strike picks randomly from `punch` / `punch_cross` / `punch_hook` / `punch_uppercut` for combo variety. |

**Class lookup helpers** (all on `XBotAnimations`):
- `weapon_class_for_id(base_id) -> StringName` — maps
  `Item.weapon_base_id` (e.g. `&"sniper_2h"`) to the class
  (`&"rifle"`). Empty / unknown id → `&"unarmed"`.
- `idle_anim_for_class(class_id) -> Array[StringName]` —
  candidate array (per-class first, `xbot/idle` last) so an enemy
  without the per-class clip loaded still resolves.
- `walk_anim_for_class` / `run_anim_for_class` — same pattern.
- `attack_anim_for_class` — sword_slash / axe_swing / fire / punch.
- `random_unarmed_punch()` — single-element array with a random
  pick from the four punch variants.

**Player picker** (`prototype_player.gd`):
- `_equipped_weapon_class()` reads
  `InventoryState.get_equipped(&"weapon").weapon_base_id` and
  threads it through `XBotAnimations.<state>_anim_for_class`. Called
  every physics tick — cheap (one dict lookup + match).
- Locomotion picker: forward jog uses class-run; idle uses class-idle.
  Strafe + walk_back + crouch stay universal (single rifle-pack
  source for now; per-class strafe is future polish).
- Attack dispatch: LMB melee + skill melee both call
  `attack_anim_for_class`; ranged paths stay on `fire`/`fire_move`.

**Enemy picker** (`prototype_enemy.gd`):
- Class is `&"rifle"` if `EnemyClass.attack_mode == RANGED`,
  else `&"unarmed"`. Enemies don't differentiate sword vs axe today
  because the X Bot mesh has no visible weapon model — the stance
  reads as "armed and ready" regardless. Future: per-EnemyClass
  stance override (e.g. brute archetype → `&"melee_2h"`).
- Both authority `_animate()` and `_remote_physics_process()` mirror
  the same class-aware picker so remotes see the right stance.

**Why the runtime merge instead of one big FBX.** Mixamo lets you
download multi-clip "packs" but the BoneMap retarget then has to
play retargeting tricks per clip; the per-FBX path with a single
shared library is cleaner and lets us swap individual clips
without re-downloading the whole pack.

**Adding a new animation.**
1. Download from Mixamo Without Skin → drop the `.fbx` into the
   appropriate `game/assets/animations/<category>/` folder.
2. Inject the BoneMap retarget into the `.fbx.import` (the user-
   dropped file starts with `_subresources={}`):
   ```
   _subresources={
   "nodes": {
   "PATH:Skeleton3D": {
   "retarget/bone_map": Resource("res://assets/characters/x_bot/x_bot_bonemap.tres")
   }
   }
   }
   ```
3. Preload it in `xbot_animations.gd` and call `_extract` with a
   library key. `strip_hip_position=true` is the default — only
   skip when the hip motion IS the anim's content (none today).
4. Wire into the picker:
   - Universal slot → add a candidate to the relevant
     `combat_constants.gd` const + use it directly.
   - Per-class slot → extend `XBotAnimations.<state>_anim_for_class`
     match block.

**Hip-track strip.** Mixamo bakes forward locomotion (and stagger
steps on hit reactions, lean-forward on casts, fall-forward on
deaths) into the hip bone's TYPE_POSITION_3D track. We re-anchor
every key's X/Z to the first key's value while preserving Y, so
jumps still arc and deaths still drop. CharacterBody3D velocity
drives all horizontal motion. ALL clips get hip-stripped by default
— it's a no-op for clips without hip motion.

**File locations.**
- `game/assets/characters/x_bot/` — `X Bot.fbx` (mesh) + `x_bot_bonemap.tres`.
- `game/assets/animations/<category>/` — every animation FBX.
- `game/scripts/characters/xbot_animations.gd` — library merger + class helpers.
- `game/scripts/util/combat_constants.gd` — candidate arrays for universal slots.
- `game/scripts/prototype/prototype_enemy.gd` — calls install_on in `_ready`.
- `game/scripts/prototype/prototype_player.gd` — `_equipped_weapon_class` + picker.
- `game/scenes/prototype/prototype_enemy.tscn` + `prototype_ranged_enemy.tscn` —
  `char_model` ext_resource points at `X Bot.fbx`.

**Still missing (deferred from animation audit).**
- Dedicated pistol firing pose (current `xbot/fire` is rifle-shaped).
- Per-class strafe / walk_back / jump / cast / hit react. Single
  universal source is fine for now; class-specific versions would
  remove the rifle-arm-pose-on-melee-character mismatch.
- Climb / vault / cover / dodge for future feature work.
