# Work since v0.4.1 — review for selective carry-over

**Last Steam release:** `b70f2b1` Release v0.4.1 (2026-05-20).
**Current `main` HEAD:** `2e668e2`.
**Scope:** 246 commits, 973 files changed, +11,831 / -977 lines.

User goal: pick a safe carry-over set that does NOT reintroduce the
perf issues that drove the 2026-05-25 hard reset (preserved at tag
`perf-session-rollback-point` / commit `9ec0a64`). Items below are
risk-tagged with a quick perf note.

Risk legend:
- 🟢 Low — content, tooling, docs, memory, isolated bugfix
- 🟡 Medium — gameplay code, visual polish, single-system change
- 🔴 High — touches rendering pipeline, autoloads, hot paths, scene tree

---

## 1. Animation system — Phase 1 + 2 + polish (~35 commits)

Per-weapon-class stances (pistol / rifle / sword / axe / unarmed),
3-anim sword + axe combos, death-anim playback, directional hit
reactions, strafe / walk_back / crouch_idle, reload / grenade_throw /
cast pose, hip-strip on all clips, action-duration drives anim speed.

**Risk: 🟡 Medium overall.** Adds clips to AnimationLibrary (memory),
runs the picker every physics frame (microseconds). The `_anim_stretched`
helper is a hot path but cheap. No autoloads, no per-frame allocations.

Carry recommendation: **bring it all over.** Visual quality leap, no
perf footprint of concern.

Commits (selected):
- `418faf3` Animation Phase 2: per-weapon-class stances
- `199a368` Animation Phase 1 polish: cast / directional hits / strafe
- `b77c6fd` Animation Phase 1: folder reorg + universal slots + reload/grenade/jump wiring
- `5e48740` Strip hip position on all animations to keep them in place
- `7ebdb53` Play death animations on non-explosion kills (was always ragdoll)
- `7700e66` Sync melee animation, sound, and damage on the impact frame
- `8511793` Enemies use axe combo for melee swings (was xbot/punch)
- `22b07a7` Melee swings read bigger — swap source clips + bump playback speed
- `e3df391` Pistol fire pose: swap throw-motion clip for static aim
- `b8d31a1` Stretch blade swing — bump cooldown + lower anim speed floor
- `745ab2f` Slow 1H + 2H melee weapon attack speed (massive slowdown pass)

---

## 2. Weapon model attachment — 12 visible weapons on right-hand bone (~43 commits)

Blenderkit-sourced glb models mounted on `mixamorig_RightHand` via
`WeaponAttachment` helper. Per-weapon `_GRIP` tables tuned via live
F9-inspect + T-tune tooling. Per-weapon muzzle override for the
AABB-tip heuristic edge cases. Missing-texture fallback for the
sniper glb (geometry-only).

**Risk: 🟡 Medium.** Adds N visible meshes (1 per character, ~12 per
common combat encounter at maybe 20 enemies). MeshInstance3D + extra
draw calls per frame. Per-character mesh ~218 KB-6 MB. Not a hot path
but does increase render load proportional to enemy count.

Carry recommendation: **bring it over** — the visual gain is huge.
Watch the HUD perf overlay's draw-call count during big mob fights;
if draw calls spike from this, the workaround is to gate weapon
attachment on LoS visibility (only attach when enemy is visible).

Commits (selected):
- `79eeac4` Import 12 weapon models from Blenderkit
- `bfbcf0c` Weapon models attach to right-hand bone on player + enemies
- `c5b7559` Commit weapon glb textures + .import sidecars (12 weapons)
- `116bd0d` Projectile / hitscan origins emerge from the weapon's muzzle tip
- `c36e5fd` Live weapon-grip tuner — keyboard adjust + console dump
- `280b788` Per-weapon muzzle override + taser muzzle pulse
- `1b87c8a` Weapons: paint untextured-white materials with the dark-metal fallback
- 11× `Bake tuned grip values for <weapon>` commits

---

## 3. Outline pipeline rewrite — neon tube + glow halo (~21 commits)

Two iterations landed:
- **SubViewport pipeline rewrite** — flat 1px edge → two-tap 8-direction
  sampling, core_boost 5.5× pushes into HDR for bloom-driven neon look.
- **Inverted-hull alternate** — `outline_hull.gdshader` replaces the
  SubViewport pipeline (`11ae475`). Simpler, no SubViewport overhead.

**Risk: 🔴 High.** Rendering pipeline change. The inverted-hull approach
replaces an autoload (`OutlineCompositor`) with per-mesh material work.
Could interact with the GI/SDFGI changes, the camera projection switch,
and any other rendering work in unpredictable ways.

Carry recommendation: **carry the FIX commits but verify carefully**
on a low-perf test machine. Specifically the `11ae475` switch from
SubViewport to inverted-hull is the most architectural — pull it as a
single coherent set, test, and only then keep it.

Commits (selected):
- `11ae475` Outline: replace SubViewport pipeline with inverted-hull overlay
- `2b10d55` Outline compositor: neon tube + glow halo (was flat 1px edge detect)
- `46ba3c9` Fix outline_compositor shader 'Redefinition of TAU' compile error
- `adfb81b` Fix outline shader: restructure early-out, return forbidden in fragment
- `09c44ed` Interactables: always-on proximity outline within interact range
- `0d81621` Outline: strip highlight layer from main camera + update color on re-attach
- `8e46580` Outline: gold for special enemies + RMB also locks the target
- `da273e7` Hover outline: restore after HitFlash finishes
- `40df4ba` Screen-space silhouette outline replaces grow + cull-front halo

---

## 4. Camera projection — ortho → fake-ortho perspective (~16 commits)

`level_shell.tscn` + `prototype_3d.tscn` switched from ortho (size=22)
to perspective (FOV=18° at ~70m). View-space identical to old ortho
framing but depth buffer now matches perspective + reverse-Z semantics
that screen-space passes (SSR, fog, soft-particle alpha, tactical
overlay LoS clip) actually need. F8 toggles at runtime.

**Risk: 🔴 High.** This IS a rendering-architecture change. Depth-buffer
semantics affect every screen-space pass, every depth-based VFX, the
tactical overlay clipping, the soft-particle ranges, decal projections.
Many things were "rebuilt on top of" the new perspective — reverting
later would unravel them.

Carry recommendation: **carry it over but understand the bundle.** If
you keep this, you keep the camera rig + every consumer that depends on
the new depth semantics. Reverting requires reverting all the depth-
dependent fixes that landed since.

Commits (selected):
- `60ca187` Try fake-ortho perspective (FOV=18°, dist=70m) — F8 toggles to ortho
- `3f28537` Inspect zoom drives ortho `size`, not `_distance`
- `c8689c1` Debug camera inspect mode (F9) + first-pass weapon grip rotation
- `dbcdd65` Scale Label3D fixed_size pixel_size for the active projection
- `d6815ac` Inspect camera: visible HUD label + F9 polling fallback
- `6bc31e3` Inspect mode: lift focal to chest for weapon-attachment framing

---

## 5. Perf systems (~19 commits + supporting autoloads)

This is the category to think about most carefully.

**Net effect: positive.** These commits ARE the fixes that recovered
perf after the issues. Most of them ADD throttling / streaming / batching.
Pulling them is a perf WIN, not a risk.

**Risk: 🟢 Low (they're fixes).**

Carry recommendation: **bring them all.** Especially:
- `2c644c8` RagdollQueue: cap XBotRagdoll setup+activate at N/frame
- `3d3bf0d` LevelBuilder: stream piece build to kill 5.8s entry freeze
- `fd1096f` GI: SDFGI off by default + Display setting "Global Illumination" preset toggle
- `81da9b3` MMI batching: corridor walls + decorative pillars
- `afdac82` Enemy perf: nav-target throttle + distant-idle tick skip
- `25cbf1b` Idle proc: throttle near-IDLE enemies + yield pre-loop build steps
- `d5ad5f4` Enemy throttle: extend to distant CHASING enemies
- `b3702a1` LoS culler: surgical fixes for 4 reported failure modes
- `0d39645` Cache the player skeleton lookup — hot-path saver
- `78c9069` PerfLogger autoload + level-up VFX shader warmup
- `6c616ed` PerfLogger: per-frame spike detection (catches sub-second freezes)
- `f7883e3` Perf pass from latest log: drop PIECES_PER_FRAME to 1 + notes

**Heads-up:** PerfLogger had a positive-feedback-loop bug — spike rows
wrote `find_children` walks that fed back into next-frame proc, locking
in spike mode. Fixed in `bc5798e` (LIVE_TREE_WALKS=false). Memory file
`project_perf_logger_feedback.md` documents it. Don't skip this fix.

---

## 6. VFX additions — crater / shell casings / warmup (~29 commits)

`hammer_crater.gdshader` (refraction + center darken + scorch tint),
`shell_casing.gd` (scripted ballistics, no RigidBody), `vfx_warmup.gd`
(pre-compiles shaders during loading window so first-LMB doesn't stall),
HitFlash tuning, blood decal variants.

**Risk: 🟡 Medium.** Adds particles, decals, mesh spawns per shot/hit.
Per-shot cost is small but compounds at horde scale. Crater shader does
screen-space refraction — that's a SCREEN_TEXTURE sample, modest cost.

Carry recommendation: **bring it but watch the per-frame VFX count.**
The HUD perf overlay's particle/decal counters tell the story. If horde
combat shows particle counts exceeding ~200, gate behind LoS or pool
more aggressively.

Commits (selected):
- `b71d2ad` Hammer crater shader: refraction + center darken + scorch tint (+the entire crater stack)
- `bdeedf0` Shell casing ejection: hide shotgun's baked-in casing, reuse for fire
- `8a02aff` Casing heat-pop emission fades to zero in 80ms
- `78c9069` PerfLogger autoload + level-up VFX shader warmup
- 14× shell-casing / muzzle / VFX polish

---

## 7. Blood / gore / ground effects (~39 commits)

Full traction system rework (per-surface mitigation curve, override flags,
ilvl-scaled rolls), object blood pipeline (props/pillars/interactables
splatter), blood pool ground effect (slip + slow + stumble), per-effect
debuff icons, settle pool under ragdoll corpses, enemy bloody footprints.

**Risk: 🟡 Medium.** Adds Area3D detection zones per pool, decal ring
buffer eviction, per-frame slip/friction multiplier in player movement.
Decal cap (400 in ring buffer) prevents runaway growth. Pool-attach
logic is O(N) over the ring per kill which is bounded.

Carry recommendation: **bring it all over.** This is the polish that
makes combat feel weighty. The perf characteristics are bounded.

Commits (selected):
- `b711071` Blood pools are now a Divinity-style ground effect
- `69c9caf` Traction: per-surface hyperbolic mitigation + override flags
- `4c6d1a6` Traction: ilvl-scaled open-ended roll range + tuned endgame k values
- `5ba4d01` Per-effect debuff icons (Slippery + Poor Traction) instead of per-surface
- `740e185` Fix blood pools disappearing after a fight (ring eviction backwards)
- `7e22052` Spawn settle-pool under ragdoll corpse on rest
- `106c301` Enemies leave bloody footprints when they step through a pool

---

## 8. Loading screen + streamed level build (~6 commits)

Loading screen redesign with progress bar, full-opacity overlay so the
world freezes underneath. `LevelBuilder._build_level` now async — yields
every N pieces. `prototype_root._ready` awaits the new `built` signal.

**Risk: 🟢 Low.** This is the fix for the 5.8s entry freeze. Async +
signal-driven hide. No allocations, no hot paths.

Carry recommendation: **bring it all over.**

Commits:
- `3d3bf0d` LevelBuilder: stream piece build to kill 5.8s entry freeze
- `0d20b54` LoadingScreen: pause SceneTree + full-opaque overlay so the world freezes
- `46e7985` LoadingScreen: swap '...' dots for a progress bar driven by LevelBuilder
- `d634d91` LoadingScreen: paint level1.png as background, move UI to bottom strip
- `f86ed1e` LoadingScreen: drop title + subtitle labels (wording bakes into bg image)
- `497f84a` Minimap: gate initial bake on streamed-build completion

---

## 9. Behavior mods system (~6 commits)

`BehaviorModRegistry` autoload. 24 mods designed across 6 slots. Two
dispatch patterns: passive `get_active_param` query for hot-path reads,
plus event-style hooks. 6 effects wired so far (Servo Stride, Ammo
Reclamator, etc.).

**Risk: 🟢 Low.** Autoload + dictionary lookups. Hot-path queries are
single dict get + bool check.

Carry recommendation: **bring it over.** This is the identity layer
of the gear system — without it the gear loop feels flat.

Commits:
- `054346b` Behavior mods: foundation — resource type + 24 designed mods
- `93f5f06` Behavior mods: registry + ItemRoller + tooltip + 2 reference effects
- `171ccd5` Behavior mods: wire 6 effects + finish servo_stride trade + drop tuning
- `9bf6555` CHANGELOG: behavior mods MVP
- `38b6020` Behavior mods: tooltip preview/active polish

---

## 10. Items / affixes / tooltips (~19 commits)

Tiered affix ladders (4 tiers per damage stat), ilvl-scaled boots
traction, per-surface mitigation tooltip on boots, "Resolved" object
blood pipeline notes, item meter strip updates.

**Risk: 🟢 Low.** ItemRoller is build-time only. Tooltip code is on
hover (cold path).

Carry recommendation: **bring it all over.**

---

## 11. Host migration scaffolding (2 commits)

Session 1 + 1.5 of multi-session host migration work. Behind
`DebugConfig.host_migration_enabled` flag (off by default).

**Risk: 🟢 Low (feature-flagged off).** Code lives but doesn't execute
in normal play.

Carry recommendation: **bring it.** Even though it's not active, the
scaffolding doesn't cost anything and you keep the work-in-progress.

Commits:
- `083662f` Host migration: Session 1 scaffolding (experimental, off by default)
- `eb77b99` Host migration Session 1.5: UI overlay + debug trigger + SP guards

---

## 12. Audio fixes (~9 commits)

Audio listener anchor fix (`cea4d12` — panning was drifting because sources
set position once at play-time while listener moved every frame),
shotgun SFX overhaul, UI sounds inherit SFX volume.

**Risk: 🟢 Low.** Bugfixes.

Carry recommendation: **bring them.**

---

## What NOT to carry (perf-rollback territory)

The 2026-05-25 perf session work that DEGRADED gameplay fps was rolled
back via hard-reset to `cea4d12`. Those commits aren't on main today —
they live in tag `perf-session-rollback-point` (commit `9ec0a64`).

**Don't cherry-pick from that tag** without revisiting the rollback
analysis (`project_perf_session_2026_05_25` memory). The individual
optimizations measured as wins, but their cumulative behavior change
degraded combat fps below the 60fps baseline.

If you decide to "revert main back to a state I know is lag-free":
- `cea4d12` (audio listener anchor fix) is the last commit on the
  conservative perf baseline.
- Or `f5573fc` (Release v0.4.0) — known-good Steam-deployed state.
- Or `b70f2b1` (Release v0.4.1) — also Steam-deployed.

To roll back to one of those AND cherry-pick the carry-over set above,
the order would be:
1. `git reset --hard <chosen-base>` (be sure you've pushed everything!)
2. Cherry-pick categories 1, 5, 8, 9, 10, 11, 12 first (all 🟢 / safe).
3. Test combat perf at horde scale.
4. Cherry-pick categories 2, 6, 7 (🟡 — visual polish that adds work).
5. Re-test perf.
6. Only then cherry-pick 3 + 4 (🔴 — the rendering pipeline changes).
7. Final perf test on slow hardware before any Steam push.
