# Changelog

All notable changes to Neurokore: Requiem are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

The `[Unreleased]` section accumulates notes until the next deploy. Run
`tools/steam/prepare_build.py` (or `deploy.sh`/`deploy.bat`, which call it)
to roll the unreleased entries into a versioned section and bump the build.
The script will refuse to deploy if `[Unreleased]` is empty — patch notes
are mandatory.

## [Unreleased]

### Added

- **New character and weapon models** — players, enemies, and every weapon were rebuilt on custom Meshy-AI low-poly models with authored PBR textures, replacing the placeholder Mixamo X Bot rig. The new meshes carry roughly 16× fewer triangles than the previous set, which is most of where this build's framerate gains come from. Enemies now split into distinct archetypes (a roster of Riot Guard grunt variants for mobs, a creature model for bosses) instead of reskinning one body.
- **Weapons are visible in hand.** Every equipped weapon now mounts to the character's right-hand bone — on the player *and* on enemies — with per-weapon grip placement tuned for both male and female rigs. Projectiles, hitscan beams, and muzzle flashes now originate from the actual barrel tip of the held weapon instead of from the body center.
- **Spent shell casings** eject from firearms as they fire, with per-weapon timing (the shotgun racks its casing on the pump), a brief heat glow, and a ballistic bounce on the floor.
- **Dropped weapons** — enemies now drop their equipped weapon as a physics object on death; it tumbles, settles, and despawns alongside the corpse.
- **Full animation overhaul.** Characters use per-weapon-class stances (one-hand pistol, two-hand rifle, melee), a held firing pose whose loop syncs to the weapon's actual fire rate, dedicated strafing animations that keep the upper body aimed while the legs walk, and melee swings whose damage and sound land on the true impact frame of the swing. Non-explosion kills now play one of 14 death animations instead of always ragdolling. Enemies cross-fade between states and turn smoothly instead of snapping.
- **Persistent blood as a ground effect.** Blood was rewritten from short-lived decals into a rasterized liquid layer: kills leave a single growing pool that settles under the corpse, pools that touch merge into one, walls take vertical splatter with gravity drip-streaks, and characters track bloody footprints out of a pool as they walk through it. Blood now persists through a fight instead of flickering away.
- **Blood is now a traction hazard.** Standing in a pool of blood applies **Slippery** / **Poor Traction** debuffs, shown as debuff icons on the HUD. Boots carry a **Traction** stat with per-surface mitigation (each hazard surface has its own resistance curve), and higher-tier traction affixes read out their mitigation directly on the boot tooltip.
- **Impact crater VFX** — sledgehammer slams and explosions now scorch a blended PBR crater into the floor, with dust and debris kicked out from inside the blast. The melee combo finisher leaves a larger AoE crater.
- **Neon interactable highlights.** A new outline compositor draws a neon-tube core plus glow halo; switches, elevators, and pickups light up cyan when you're in interaction range and white on hover, so it's clear what you can use.
- **Floor clutter decals** — themed scatter (paper, debris, stains) seeds rooms and aligns to doorways, layered so painted marks sit under stains, under litter, under piles.
- **Loading screen with a real progress bar**, painted with level art, that pauses and fully covers the world while a level streams in (no more peeking at a half-built room).
- **Display settings** — VSync toggle, FPS cap (defaults: VSync on, 60 fps), and a Global Illumination quality preset. An on-screen performance overlay (CPU phase times, object/light/triangle counts) is available for diagnosing hitches.
- **Behavior modifiers on armor drops** — every armor piece above Common rarity (Uncommon 50% chance, Rare/Unique 100%) now rolls one behavior modifier from a slot-specific pool. Mods are the identity layer: two chest pieces with identical stats and different mods play differently. 24 mods designed across six slots (head, chest, hands, legs, feet, back). Tooltip renders the mod with rolled param values and bright-green/dim-gray coloring based on whether the mod is currently active. Drops weight 85/15 toward already-active mods vs preview ("not yet wired") mods, so most drops feel live with the occasional roadmap-by-loot tease for upcoming behaviors. First two reference effects live now: **Servo Stride** (sprint costs no resource) and **Ammo Reclamator** (kills refund a round to your magazine).
- **Tiered affix ladders** — gear affixes (including shield rolls) now scale across item-level tiers, with fuller meter-bar coverage on the tooltip.

### Changed

- **Camera switched to a tighter fake-orthographic perspective** (a narrow-FOV perspective camera at distance, replacing the true ortho projection) and the gameplay focal point centers on the character's chest. Zoom was tuned in for a closer field. F8 toggles back to true ortho for comparison.
- **Major performance pass.** Headline fixes: level geometry now streams in over several frames instead of a single ~5.8s freeze on entry; the line-of-sight reveal at room boundaries is budgeted per frame to kill a ~240ms hitch; ragdoll setup is queued so multi-kills don't spike; distant and idle enemies throttle their AI, animation, and physics; and the level-up panel no longer repaints while hidden. SDFGI global illumination now defaults **off** (it was the ~50s convergence stall on level load) and is re-enableable from Display settings.
- **Game-wide asset optimization** — 16 static meshes decimated (~1.17M → ~286K triangles), character and weapon textures deduplicated and capped at 1024px. Combined with the new low-poly models, this cut a large amount of memory and draw cost.
- **Melee combat retuned** — 1H and 2H weapon swing speeds, cooldowns, and damage were rebalanced so melee DPS lands in range; swings read bigger and land their impact on the correct frame; the blade keeps a 3-hit combo with a lunge toward the cursor.
- **Explosion sizes corrected.** The RPG rocket, its Tactical Strike alt-fire, grenades, and the enemy RPG had their blast radii roughly halved to match their real damage area, and AoE blasts no longer reach through walls. Bullet and energy-bolt tracers were shrunk so they read less cartoonish.
- **Player movement speed retuned** to match the cadence of the new locomotion animations, so the feet no longer slide.
- **Removed the abandoned 2D-isometric pilot** prototype from the project.

### Fixed

- **You can no longer walk inside the switch console.** Its collision box had been silently voided by a formatting issue in the scene file; it's now measured to the actual model. Loot crates and the exit pad got the same collision tightening.
- **Elevators are reachable again** — the interaction range now accounts for the character's footprint, so you no longer get stuck just outside an elevator you can't quite touch.
- **Laser pistol no longer freezes the game on every shot.** Each shot was duplicating a material mid-frame, forcing a stall against the render thread (~25ms per shot). All per-shot VFX now reuse shared materials; the muzzle flash also matches the laser's color.
- **Eliminated several level-transition and combat freezes** (room-crossing, level-up, idle-enemy spikes) and a feedback loop in the performance logger that perpetuated its own hitches.
- **Audio panning no longer drifts** as you move — listener-anchored sounds now follow the listener every frame.
- **Mission tracker no longer spams duplicate switch lines.** The objective state is cleared on every level build and dead-door puzzles are pruned, so you see one clean line per gate.
- **Blood no longer pre-stains walls at level start** (uninitialized blood mask read as full coverage), and the walking-in-blood debuff now only applies while you're actually standing in a pool — not lingering on footstep residue.
- **Decals no longer project over empty space** — floor stencils stay inside room bounds and pit/void edges, instead of hanging off the platform.
- **Animation fixes** — lower body no longer twists ~90° while aiming, strafing feet no longer float above the floor, and the sledgehammer uses the shared run cycle like every other weapon.
- **Quieted the "material is null" renderer warning spam** by backfilling default materials at the mesh level where the renderer actually probes them.
- **MP:** remote co-op players now correctly take damage (a routing gap meant non-host clients were untouchable); the firing-beam network sync was repaired after a signature change.
- **Blood decals no longer paint into pits.** Kill scenes spawned near a pit edge had their satellite splats and floor mist drops land in the empty space above the pit, leaving floating bloodstains hanging mid-air. Decals now skip any spawn point that falls inside an active pit's XZ footprint.

## [0.4.1] - 2026-05-20

### Added

- **Mixamo character meshes** — player (male / female) and enemies (vanguard, alien, military_man, crypto) swapped from the placeholder Quaternius low-poly model to Mixamo X Bot–compatible meshes with authored PBR textures. Player gender is picked from character creation and drives the mesh at spawn.
- **MP per-peer gender plumbing** — each peer publishes their selected gender into the coop lobby's member data, so remote avatars in MP now render with the correct mesh instead of all defaulting to player_male.
- **Ranged firing pose** — equipping any bullet weapon plays a dedicated Firing Rifle animation while LMB or RMB is held, with a Strafing variant when moving so the upper body stays aimed and the legs walk. Enemies with ranged classes hold the same firing pose during their cast windup. Melee attacks keep the original swing.
- **Locomotion animation set** — added Jog Forward (new default run cadence, replacing Fast Run as the primary), Crouched Walking, and 14 Mixamo death clips that the player randomly picks from on death.
- **Sci-fi monitor model** swapped in for the puzzle Switch, scaled and grounded so it sits flush on the floor.
- **NG+ pill in the HUD and character select** — current New Game Plus value displays above the minimap in-game and beside the character's level in the continue panel. Hidden on NG+0 to avoid clutter on fresh runs.

### Changed

- **Blood spray distance tightened** — droplet burst speed cut roughly in half so gore reads as a wound spray instead of arcing 2–3m past the body. Floor decals and visible particles stay in lockstep via shared constants.
- **SSR step count lowered** from 64 to 24 — kills the cross-screen ghosting where muzzle flash and bullet trails bled onto reflective surfaces on the opposite side of the screen during combat, while keeping local environmental reflections on the procedural worn-steel walls.
- **Boot splash logo resized** — was rendering at full main-menu source resolution (2912×1632) and dominating the screen; pre-resized to 1024×574 for a sensible centered native-pixel-size splash.
- **Removed the flat-color player tint** that overrode the new Mixamo PBR textures with the class accent. Characters now show their authored materials.

### Fixed

- **Enemy ragdoll Jolt warning spam** — Mixamo FBX imports carry small per-axis scale residue (~0.99/1.01) on intermediate Armature/Skeleton nodes that the per-PhysicalBone3D counter-scale couldn't fully cancel under rotated parent bases. A new parent-chain normalize step at character spawn pre-bakes uniform scale onto every ancestor, eliminating the `_try_build_shape: Failed to correctly scale body` spam that historically piled up tens of thousands of warnings per session.
- **"material is null" renderer warnings** — FBX sub-meshes that imported without a material slot now get a default StandardMaterial3D assigned at spawn so RenderingServer doesn't probe a null material for shadow culling. Real PBR textures stay; only blank slots get patched.
- **Player death no longer crumbles to a T-pose blob** — the `ANIM_DEATH` candidate list looked for a non-existent generic key; replaced with a random pick from the 14 `xbot/death_N` clips. The same fix is applied to the enemy MP-client death path so coop client avatars don't crumble after a host kill either.
- **Crouch animation no-match log spam** — crouch idle and crouch move fall back to standing idle and slow_run candidates while dedicated Mixamo crouch clips aren't yet wired into every state. Crouched Walking now serves the actual crouch-move case.
- **Switch interaction outline** restored after the box-mesh body was replaced with the sci-fi monitor glb.
- **MP fix**: enemy death visual now also synchronizes for non-host clients (was previously hitting the same generic-death no-match the player suffered).

## [0.4.0] - 2026-05-15

### Added

- **Visual meter-bar tooltips** — every item now renders its stats as colored meter bars instead of numeric stat lines. Each bar's fill represents where this roll sits in its archetype+rarity range; a quality % in the top-right of the tooltip name row scores the overall roll on a red→yellow→green→blue gradient (30–150%). Damage-power bars carry a red decay overlay showing how much item-level scaling has eaten the raw roll; underleveled drops get a blue boost overlay instead. Shift-hold opens a side-by-side comparison panel with the union of bars from both items so missing stats are visible at a glance, and the equipped panel shows its own quality score for direct comparison.
- **Global Power scale on weapon tooltips** — the Power bar is normalized against the DPS range of every weapon archetype × rarity combo in the game, with a thin divider beneath it telegraphing "compares across weapons, everything below this line is type-scoped." Single-target weapons (Sniper / Laser Pistol / LMG) land slightly above multi-target archetypes by design, with rarity tier driving the bigger jumps.
- **Mission tracker panel** — top-right HUD panel now shows the current floor's objective chain: "Activate switches (X/Y)" → "Kill the boss" → "Descend to the next level". Multi-puzzle boss rooms get one line per door ("North gate switches (2/3)", "South gate switches (0/3)"), and phase transitions play a green checkmark animation over the completed line before swapping in the next phase.
- **Flipbook explosion VFX** — RPG, grenade, and Tactical Strike blasts now use a sprite-sheet-driven explosion shader (8×8 frames) with smoke, scaled 1:1 to gameplay blast radius so the visible fire matches the actual damage area. Instant flash sphere + radial sparks + a brighter omni light (peak 40 energy) read as a real detonation.
- **Procedural dungeon scale-up** — procgen levels now generate 25-40 rooms across a 320×120 ground (was 5-8 rooms in 160×60). Layouts include themed facility rooms (cell block, mess hall, medical ward, security checkpoint, isolation wing), pit-as-design-element rooms (bridge / island / crossing), and ~85% of room-to-room connections now have doors.
- **Asylum/prison-themed clutter** — destructibles and indestructible cover swapped to facility-flavored props: medical carts, filing cabinets, IV stands, patient trays, surveillance monitors, cell bars, exam tables, security barriers, restraint chairs, vent ducts, floor drains. Hard cover (cell bars, exam tables, security barriers) is now breakable with 80 HP so the procgen can't softlock a corridor.
- **Sustain system** — `life_on_kill` (flat HP per kill, rolls on weapons + armor) and `barrier_on_kill` (temp absorb-shield that decays after 4s of no kills, rolls on armor). New affixes "of Vitality" / "of the Parasite" / "Hardened" plus universal-bonus roll chances mean sustain shows up across most gear slots. Talent nodes "Melee Leech" and "Barrier Surge" feed the same pool.
- **Volumetric fog at shin height** — two-layer floor-only fog (0.15m slab + 0.5m haze cap) gives rooms atmospheric depth without obscuring the iso view. Bottomless pits get their own dense fog so the edges read clearly.
- **Freight elevator exit** — replaces the teleporter pad at the end of each floor. Locked until the boss dies, then status lights flash green and the player can interact to descend.
- **Combat-feel batch** — crit/kill hitstop, muzzle flash, screen damage flash, loot pickup magnet tween, level-up SFX + screen flash + camera shake, cooldown-ready flash on skill slots, smooth HP/resource bar drain with ghost-fill trails, low-HP warning vignette.
- **DebrisShard physics for destructible breaks** — barrels, crates, and clutter shatter into hand-rolled physics shards (direct velocity + gravity + spin) instead of GPUParticles3D, giving more predictable trajectories.
- **Locked enemy tooltip auto-refreshes** — LMB-locking on an enemy now polls HP and status effects in real time so the tooltip stays current as the fight progresses.
- **Mid-air control** — pressing a movement direction during a jump now applies reduced lateral velocity (60% of ground speed, 50% accel) so you can clear knee-high clutter from a standstill.
- **HUD recharge cooldown** on the Recovery slot shows whenever any charge is regenerating, with a numeric countdown. The slot stays visually usable when there are still charges available.

### Changed

- **Recovery slot replaces health potions** — old "Potion" naming retired (`Skill.ActiveKind.POTION` → `RECOVERY`, `PlayerPotion` → `PlayerRecovery`, `health_potion.tres` → `health_recovery.tres`). Recovery items roll 50–125% heal (poor common → perfect unique) with 1–5 charges, scaled by both the power-curve roll bias and rarity budget multiplier.
- **Universal rarity-curve stat rolling** — every rollable stat now passes through `_rarity_rollf` / `_rolli` / `_rollf_inv` / `_rolli_inv` helpers that apply both the per-rarity power-curve exponent (steeper bias toward floor on commons, flatter on uniques) and the `RARITY_BUDGET_MULT` ceiling stretch in one call. A handful of stats that previously used bare `rng.randf_range` (universal HP/resource, head-light energy, consumable charges + duration) now feel-out at noticeably different median rolls per rarity tier.
- **Destructible clutter is physically transparent to enemies** — destructibles sit on the PILLAR collision layer only (was ENEMY+PILLAR). Enemies' collision mask drops PILLAR, so they walk through knee-high props instead of getting stuck on a barrel's invisible chest-height bullet-catch column. Player mask gains PILLAR so cover still functions for them. Indestructible cover (cell bars, exam tables) sits on WORLD+PILLAR to keep blocking enemy movement via the WORLD layer.
- **Enemy attack-config precedence inverted** — when a class declares its own `attack_cooldown` / `attack_windup` / etc., those values now win over the shared `basic_attack` skill resource. Variant classes that share a basic_attack file (Laser Trooper vs Laser Gunner, Blade Runner vs melee Healer) can finally cadence per their per-class identity instead of all playing at the shared skill's speed.
- **Ranged weapon ranges reined in** — most ranged weapons had their effective ranges dialled back to fit the iso camera frustum; enemy kite distances reduced to match so a Sniper at 20m kite no longer disappears below the screen edge while still firing at you. Enemy attack_range gates correspondingly tighter.
- **AoE/cone attacks no longer extend past their visual area** — the damage-falloff multiplier that doubled effective range on hitscan/projectile attacks now only applies to those two paths. Sledgehammer Ground Slam, cone melee, and grenade radii hit exactly the visible blast area instead of silently reaching 2× further at reduced damage.
- **Enemy special skills disabled pending balance pass** — `_chase_tick` no longer rolls onto the per-class skill pool. Basic attacks still fire. Skills will re-enable once their cooldowns / damage scaling get a dedicated tuning pass.
- **Boss difficulty + NG+ variety** — bosses chase more aggressively, with stuck-detection that picks a fresh path when their navmesh deadlocks. NG+ now rotates the active layout across the layout pool each cycle so successive playthroughs don't hand back identical maps.
- **SMG bumped and ricochet feels real** — SMG base damage 1-1 / 2-3 → 2-3 / 4-6; ricochet damage multiplier 0.5× → 0.8× so a bounce lands as a real hit instead of rounding to 1 damage. Ricochet chance raised to 15-25% on weapons with a cap of 40%, with a visible bounce arc.
- **Accelerator visual rework** — replaced the 3D channel cone with a flat energy fan that fades in with the ramp and clips against walls via the shader. Reads clearly at iso distance without the cone clipping into geometry.
- **Switch visual redesign** — red blink replaces the previous cyan pulse, with a brighter OmniLight3D attached to each lamp so they read as waypoints from across a room. Used switches turn the light fully off.
- **ISR drone locks onto its first target** — once the drone procs on an enemy, it stays committed for the full ~7s duration instead of hopping to whatever was hit most recently. Subsequent procs while one is active are ignored.
- **Effective attack speed no longer decays with item level** — a low-ilvl SMG keeps its fast cadence at high player level; damage carries all the level-scaling work via `effective_damage_min/max`. Tools and weapons retain their characteristic feel regardless of ilvl delta.

### Fixed

- **Power-meter scoping** — Power bars used to be archetype-scoped (a common SMG at 100% meant "best possible common SMG"), making cross-archetype comparison impossible. Now normalized globally so an SMG-rare and a Sniper-rare compare on the same scale.
- **Multi-puzzle boss rooms cleanly advance** — when one of N boss-door puzzles completes, the panel jumps to "Kill the boss" instead of leaving stale per-door switch lines visible.
- **Recovery item tooltip displayed nothing** — sub-1s rolled heal durations got truncated to int 0 and the tooltip's `hp > 0 && hd > 0` gate then skipped the entire heal line, so a perfectly fine 80%/0.4s potion looked blank. Now reads heal_duration as float and branches on duration < 0.5s for an "Instantly heals X% HP" wording.
- **Right-click equip on an origin-mismatched Recovery item no longer deletes it** — quick-equip cleared the inventory slot before `set_equipped`, which silently rejected on origin mismatch, dropping the item. Added a pre-check plus a verify-and-restore so any future silent gate is also covered.
- **Jump straight up against an obstacle** — `move_and_slide` zeroed the wall-perpendicular velocity every frame the player was in contact with a destructible, so the jump injection only survived one frame and the player rose straight up. PILLAR layer dropped from the player's collision_mask while airborne so destructibles become phase-through during a jump (indestructibles still block via WORLD).
- **Invisible obstacles in clutter rooms** — destructibles register as `&"enemies"` for damage routing, which made the LosCuller's visibility test fade them out when the ray-to-prop-center clipped a wall corner — leaving collision intact while the visual disappeared. Clutter is now exempt from LOS culling.
- **Enemies path-stuck on knee-high clutter** — the same PILLAR-layer redesign that lets enemies walk through destructibles also fixed pathing softlocks. Hard cover (cell bars, exam tables) became breakable with 80 HP so a procgen-placed cell-bar in the only path doesn't softlock the floor.
- **Bullets going clean through barrels** — destructible collision shapes now extend up to chest height (1.6m) so aimed shots at the visible prop actually land. Cover-providing props block enemy fire at standing height as well as crouching.
- **Explosion fire and light were invisible** — fireball shader emission intensity bumped 1.0 → 5.0 (the previous value sat below HDR-bloom threshold), light energy bumped to peak 40 with a 0.25 volumetric_fog_energy so dense rooms haze in the explosion color. Smoke alpha was so opaque it occluded the fire and light underneath — both alpha values cut to make the flash readable.
- **RPG primary fire windup removed** — the 0.25s pre-roll existed to sync with an older SFX sample. New samples hit instantly so the rocket spawns on the click. Tactical Strike keeps its 0.6s windup as the airstrike telegraph.
- **NG+ layout rotation never firing** — the rotation index was always reading the prior layout. Now correctly advances to a fresh layout on each NG+ cycle.
- **Low-HP warning vignette not rendering**, **specular shimmer on projectile glow lights**, **ammo bar wrap at full HP**, **taser chain retention range/tooltip mismatch**, **entity pool crash on freed instance assignment**, **deal_damage crash on DestructibleProp**, **front-row stagger crash accessing a private field**, **deferred call errors in ui_sounds + overhang_fader**.
- **Player hit grunts gated** — only fire on hits clearing 5% of max HP with a 1.5s cooldown. SMG/taser chip ticks stay silent; sniper rounds, RPG splash, and melee bruisers still grunt.
- **MP destructible visuals + projectile sweep routing** carried over from v0.3.0 — destructibles still broadcast hit/break visuals to all peers, and the projectile sweep correctly routes PILLAR-layer target_group hits through the damage path.

## [0.3.0] - 2026-05-13

### Added

- **Procgen dungeon layouts** — sparse D2-style maze topology with dead ends, winding corridors, and loops, generated from a Growing Tree carve over a 7×7 grid. Spawn always lands in a safe leaf (zero enemies, zero adjacent-corridor enemies); boss + exit live at the far end behind a 3-switch puzzle. Difficulty scales with BFS distance from spawn, so deeper rooms hit harder.
- **Enemy density scales with zone level** — fresh L1 characters fight roughly half the per-room mob count of a deep-zone playthrough, ramping linearly to full density around player level 10. Pack chance scales together so the crowdedness curve moves coherently rather than fewer enemies but the same pack rate.
- **Cover system** — destructibles and indestructible cover props sit on a new PILLAR collision layer. Crouching behind a barrel lowers your combat-LOS test below cover height, letting it block enemy fire and line-of-sight while you still see them. Destructibles also extend their collision to chest height so they're both bullet-catchable and standing-cover.
- **Destructible and indestructible clutter** — rooms now scatter barrels, crates, monitors, chairs, and terminals (loot + credit drops on break) alongside non-destructible barriers, server racks, pipes, and floor grates. All built from procedural meshes + procedural textures, no external art needed.
- **Damage falloff beyond effective range** — hitscan and projectile attacks now keep travelling past their effective range and deal progressively less damage, decaying quadratically to 25% at 1.25× range. Cone and AoE attacks (melee swings, sledgehammer ground-slam, grenade radii) get a hard cutoff at their effective range so the hit area matches the visual instead of extending silently.
- **Health potion system** — new Consumable slot (Q key) holds either Stimpack (Analog) or Battery (Cyborg). Both types roll independently in any game; the equip-time origin gate refuses wrong-origin potions and the tooltip explains why so cross-origin trading still works. Three charges, 30s recharge per charge, heals a % of max HP over time. HP bar shows a green preview overlay projecting where the heal will land.
- **Armor damage reduction** — Head/Chest/Gloves/Legs each roll a base DR stat that aggregates across all four slots, capped per-piece. Boots and Backpack stay out of the DR system (traction and inventory respectively).
- **Per-weapon signature stats** — each archetype rolls one or two iconic stats that define its mechanical identity beyond the universal damage envelope: RPG blast radius, Shotgun pellet count + spread angle, Sniper headshot bonus, Taser chain retention + chain target count, Accelerator ramp speed, Knife bleed damage, Hammer impact radius, LMG sustained fire bonus, SMG ricochet chance, Plasma overcharge chance.
- **Unarmed strikes + glove affixes** — bare-fist combat fallback when no weapon is equipped, with glove affixes Spiked (+ flat unarmed damage), Concussive (stun chance per swing), and Shockwave (AoE radius around the player) to make unarmed builds viable.
- **Power-curve stat rolling** — rolls bias toward the low end of each range, with the bias weakening as rarity climbs. Common items cluster near their floor; uniques get a much flatter distribution where high rolls are attainable but still not guaranteed.
- **Boots always roll move speed + traction** — both stats are guaranteed on every boots drop, scaled by ilvl and rarity. Traction breakpoints at 25/50/75/100 unlock CC immunities and DoT damage reduction in lockstep.
- **Tactical range overlay** — SCANNER head mod projects two ground rings showing your weapon's effective range (inner) and falloff boundary (outer), with distance labels at the cardinals. Refreshes on equipment change.
- **World-space resonance bar** — Energy Accelerator's channel ramp now reads as a cast bar under your character (billboarded, depth-test-disabled) instead of a HUD widget, matching the spatial feel of the channel itself.
- **Aimed Shot** — replaces Sniper Focus with the same hold-to-buff behaviour plus a thin red laser sight that paints from rifle to cursor while RMB is held.
- **Ammo capacity as a rollable stat** — bullet weapons (LMG/SMG/sniper/RPG/shotgun) roll magazine size in a per-base range, scaled by rarity, so a rare drop can carry visibly more rounds than a common one of the same archetype.
- **Item level effectiveness curve** — combat power stats scale by an asymptotic multiplier driven by `item_level` vs `player_level`. Drops below player level decay to a 30% floor; drops above scale up to 150%. Storage (inventory_bonus) and feel stats (light radius) keep their raw value so a low-ilvl backpack doesn't shrink under a high-level character.
- **Starter chest in the spawn room** — always rolls either a 2H weapon, or a 1H + offhand, so first-floor combat starts armed.

### Changed

- **Weapon DPS normalized to a 3-tier model**: single-target weapons (Sniper, Laser Pistol, LMG) hit ~26 DPS, limited-multi (Assault Rifle penetration, SMG ricochet) ~23, multi-target (Melee, RPG, Shotgun, Taser, Accelerator) ~20. Damage scales meaningfully with rarity via a budget multiplier so high-rarity drops are noticeably stronger, with overlap at the edges.
- **Enemy attack cadence slowed across rapid-fire archetypes** — SMG 1.2→2.0s, LMG 2.0→2.8s, Laser 0.8→1.4s, Taser 0.8→1.4s, Accelerator 1.0→1.6s, Shotgun 2.2→2.8s, Plasma 2.0→2.5s, Sniper 3.5→4.5s, RPG 4.0→4.5s; windups raised to a 0.3s floor so attacks are readable enough to dodge. Closing distance against a pack is now possible without precision play.
- **Enemy heavy-hitter damage cut** — Sniper damage_mult 2.0→1.5, RPG 1.5→1.2, Shotgun 1.3→1.1, Plasma 1.1→0.95, Sledgehammer 1.6→1.3. Sniper projectile slowed 35→28 m/s — was effectively undodgeable.
- **L1-3 base enemy damage further reduced** — the first encounter, where the player has no DR and no potion drop yet, is the gentlest curve point. L1 enemies hit for 2-3 instead of 3-5; L2-3 ramp up gently from there.
- **Class identity preserved for variant enemies** — classes that share a basic_attack skill (Laser Trooper vs Laser Gunner, Blade Runner vs melee Healer) now actually cadence per their per-class fields. Previously the shared skill's cooldown/windup won, so sister classes played identically.
- **Default level is now the procgen dungeon layout** — level_shell.tscn ships pointing at dungeon_demo.tres, so opening F6 / running from main menu drops you straight into a generated maze.
- **Consumable rolling decoupled from origin** — both Stimpack and Battery roll in any game. Origin gating is enforced at equip time via `Item.origin_restriction`; the tooltip shows red "Requires X origin" when blocked and dim "Origin: X" when satisfied.
- **Destructible props are bullet-catchable** — visual mesh stays small (barrels, crates), but the underlying collision now extends up to standing fire height so aimed shots actually break them. Cover-providing props block enemy fire at standing height as well as crouching.
- **Player damage grunts gated** — only fire on hits clearing 5% of max HP, with a 1.5s cooldown. SMG/taser/bleed chip ticks stay silent; sniper rounds, RPG splash, and melee bruisers still announce themselves.
- **RPG primary windup removed** — the 0.25s delay existed to sync with a slow-attack sample. New samples hit instantly, so the rocket spawns on the click. Tactical Strike still telegraphs its 0.6s windup since that's the "step out of the painted X" tell, not a sound sync.
- **Combat Effects panel** — equipped-weapon signature stats are merged inline into each quirk tip with highlighted numeric values, instead of duplicated as a separate stat block.

### Fixed

- **MP destructibles** — damage numbers, hit flashes, and break visuals are now broadcast to all peers (mirrors `PrototypeEnemy`'s authority pattern). Previously the host saw the prop break and clients saw it persist until something else resynced.
- **Projectile sweep raycast routes PILLAR damage hits correctly** — extending destructibles to chest height meant the per-frame sweep ray (WORLD|PILLAR mask, used to prevent thin-wall tunneling) treated them as walls. Now PILLAR-layer hits that match the target group forward to the damage path so the prop actually takes damage.
- **LOS culler crashes** when corpses, static glows, or clutter entries became freed mid-loop. Each path now guards with is_instance_valid before reading global_position. Adds a periodic stale-entry sweep for entries that became invalid while settled.
- **det == 0 physics errors** in two places: knockback knockdown could shrink an enemy to zero scale (now scales to near-zero), and destructible props were tearing down collision shapes during the break tween (now disable shapes before queue_free).
- **SaveManager schema persistence** — `origin_restriction` is now serialized/deserialized, and v0.2.1-era consumables in saved inventories back-fill their origin from sub_type on load.
- **Heal_total → heal_pct migration** — old flat-HP saved potions now floor at 10% + 3s instead of silently buffing by clamping the raw flat value into the percentage namespace.
- **HoT fractional carry** — low-roll potions accumulate fractional HP across ticks instead of round()-ing to 0 every tick, so the full healed amount actually lands.
- **Offhand item lost** when equipping a 2H weapon — the offhand now correctly reflows to inventory or the world drop path.
- **Raw BBCode tags** showing in enemy tooltips.
- **Ricochet preload path** corrected (SMG ricochets now actually spawn).
- **Tooltip ghost persistence** when interactables get freed by NG+ transitions.
- **Missions panel drift** in some viewport sizes.

## [0.2.1] - 2026-05-12

### Added

- **Spatial audio system** — every weapon now has fire SFX with multi-sample variants and per-play pitch/volume variance, so repeated shots don't sound mechanical and enemy fire sits audibly distinct from the player's. Includes room-aware reverb (small hallway vs. large room) and a 24-slot positional audio pool with prefer-idle eviction.
- **Channel-beam audio** — Charged Arc Taser and Energy Accelerator each get a one-shot engage zap plus a continuous hold loop while LMB is held.
- **Explosion SFX** — every grenade detonation and RPG impact now plays a randomized blast sound with full-camera shake.
- **Hit-flesh layer** — quiet pop on every enemy hit that confirms damage landing without competing with the weapon fire.
- **Footsteps** — metal and grate variants for both player and enemies; player gets a subtle dust puff per step.
- **Player damage grunts** — 10-sample pool plays when you take damage.
- **UI sounds** — automatic click / hover / confirm / back / navigate / open feedback on all buttons and tabs.
- **Music system** — title theme, 5 level tracks cycling per NG+ run with shuffle, 15s fade-in on level entry, 30-second silent gap before re-looping so the mood resets.
- **Audio settings tab** — Music / Sound Effects / Ambience volume sliders, persisted across sessions. Settings panel is now tabbed (Game / Display / Audio / Accessibility).
- **Item icons replace unicode glyphs** everywhere: inventory grid, drag preview, ground pickups (billboarded textured plane), and the click-to-move held cursor. Icons are slot-based (one Head icon, one Chest icon, etc.) and rarity-tinted via modulate.
- **Combat Effects + Missions HUD panels** — under the minimap, with a slight black background and gold-trim title. Combat Effects shows your equipped-weapon quirk tips; Missions is a placeholder for the eventual quest UI.
- **Camera shake & push system** — distinct from each other and per-archetype: SMG/LMG/sniper/shotgun get random-jitter recoil at fire time, RPG/grenades get distance-scaled impact shake, energy weapons (laser pistol/plasma rifle/accelerator/taser) get a directional "pressure" push that springs back. Melee combo shake escalates per step and the 2H hammer finisher hits with a ground-slam jolt.
- **Per-archetype enemy weapons** — full set of enemy classes (blade, sledge, SMG, LMG, sniper, shotgun, plasma rifle, laser pistol, RPG, taser, accelerator, plus healer / damage-buffer support roles) with their own attack routines, VFX, and audio.
- **Enemy footsteps and hit grunts** — enemies now make their presence heard as they move and take damage.

### Changed

- **RPG wind-up now actually delays the projectile** (0.4s) — previously it only froze the player while the rocket fired instantly. The fire SFX plays at LMB press so the audio's pre-roll lines up with the wind-up wait and the launch transient hits when the projectile spawns.
- **Energy Accelerator damage ramp** — replaced the stack-based +30% peak (reached in ~0.7s) with a time-based lerp to 2.5× over 2.5 seconds. Sustained channels now reward staying on target with a clear power curve.
- **Specular shimmer on walls and floors fixed** — procedural normal maps were aliasing under camera motion. Cut metallic + bump strength and raised roughness on the four tech shaders; disabled FXAA (redundant with TAA).
- **Tooltip type line cleaned up** — armor reads as "Armor — Legs" / "Armor — Chest" instead of "Leg Armor — Chaps". The model name lives in the item title already; the subtype line now shows category and slot.
- **Character panel layout** — equipment grid rearranged (Backpack / Head / —, Weapon / Chest / Off-hand, Legs / Feet / Hands), avatar moved out of the grid centre into a tall portrait beside the stats column.
- **Rarity-colored slot borders** — inventory and equipment slots tint their border by the contained item's rarity (blue magic, gold rare, orange unique), matching the existing text and glyph color signals.
- **Save schema now persists** `icon_path`, `model_name`, `damage_type`, and bullet-weapon ammo state — previously these were silently stripped on every autosave, so loaded items reverted to glyph rendering, neutral element, and broken reloads.
- **Per-archetype model variants for the Energy Accelerator** consolidated from 5 distinct icons down to 1 (other accelerator drops still roll varied model names).
- **`prototype_enemy.gd` modularized** — the 3000+ line monolith split into `enemy_combat`, `enemy_afflictions`, and `enemy_visuals` modules behind a thin host facade.

### Fixed

- **Enemy hover/tooltip/health-bar regressions** introduced during the module extraction: tooltips were calling a non-existent method (silently no-op), the health bar's shader-driven fill got replaced with a broken scale.x + StandardMaterial override, and floor rings rendered as solid opaque-white discs instead of subtle emissive halos.
- **Plasma rifle pierce-through** correctly continues through one enemy before stopping.
- **IED screen shake** now triggers on traps the player lays.
- **Ground pickup visual** now reads as the item icon (billboarded textured plane) instead of procedural primitive meshes for archetypes that have art.
- **Pickup name labels** no longer overlap on tightly-grouped drops.
- **Player run animation** no longer flickers between frames during sustained sprints.
- **Leash extension on long-range damage** — enemies that take damage from beyond their leash radius extend their pursuit window rather than immediately giving up.

## [0.2.0] - 2026-05-10

### Added

- **Seven new weapons**: SMG, LMG, Sniper Rifle, RPG, Shotgun, Charged Arc Taser, Energy Accelerator. Bullet weapons use a magazine + reload (R key, auto on empty); energy weapons keep the resource-pool cost model.
- **RPG Tactical Strike** (RMB) — paint an X on the ground at your cursor, the rocket falls from the sky onto it. Massive AoE, ~30s cooldown.
- **Signature passive per weapon archetype** — each weapon now has one iconic quirk: Knife Backstab (+50% from behind), Hammer Wind-Up (+75% after 1s still), Plasma Pierce (bolts pass through 1 enemy), SMG Penetration (every 5th shot 2×), LMG Heat (+10%/shot, max +50%), Sniper First Mark (+50% on a fresh target), RPG Concussive (blast staggers), Shotgun Point Blank (+50% at <2m), Taser Static Build (every 10th hit 3×), Accelerator Resonance (held stream ramps to +30%), Laser Charged Shot (+50% after 1s idle).
- **3-hit melee combo** — each swing widens the cone, hits harder, and the 3rd-hit finisher applies a status: 1H knives stack bleed (a per-tier % HP DoT), 2H hammers stun briefly.
- **Hitstop** — animations briefly freeze on melee connect; sells the weight of every hit.
- **Procedural blade slash visual** for 1H knives — replaces the generic cone with a tapered, glowing arc.
- **HUD quirk reminder panel** — small always-visible widget under the minimap showing the play tip for each equipped weapon, so you don't have to memorize the table.
- **In-game multiplayer chat** — press Enter to open, type, Enter to send, Esc to cancel. Sender names are colored by class.
- **Persistent global multiplayer lobby** — players who enter MP join a shared global chat room separate from any active coop session.
- **Host-disconnect screen** — clients get a graceful "Session Ended" overlay with a "Return to Main Menu" button when the host drops mid-game (previously froze the game in an unplayable state).
- **Cross-client projectile visibility** — peers now see each other's shots and projectile trails in coop.
- **Cross-client channel-beam visibility** — Energy Accelerator flame visual replicates to other peers.
- **Invented sci-fi model names per archetype** — every weapon drop rolls a name like "VK-9 Stinger" / "MK-7 Voidcaster" / "TR-19 Reaper" (family codes per archetype: VK=SMG, MK=sniper, TR=LMG, etc.). Melee uses real-world type names (Stiletto, Karambit, Sledgehammer, Maul).
- **Per-slot armor names** — armor drops now read as "Vest" / "Trenchcoat" / "Stompers" / "Knuckle Guards" instead of "Chest Armor" / "Boots" / etc.

### Changed

- **Weapon DPS normalized to ~22 base** across all archetypes (shotgun damage cut to 1-2 per pellet × 9 pellets; everything else was already in the band).
- **DPS tooltip formula now accurate** — factors fire rate, pellet count, multistrike expectation, channel tick rate, and damage multipliers.
- **MP and SP character rosters fully isolated** — MP characters never appear in SP and vice versa; hardcore/normal are also segregated.
- **Tripod (LMG RMB) visually crouches the player** for the duration of the aim hold.
- **Common-rarity drops now roll a flavor adjective** ("Worn", "Battered", "Salvaged", etc.) so two whites of the same base don't share a name in the loot pile.
- **HUD layout**: controls hint moved to the top-left corner; the top-right under-minimap slot now hosts the quirk reminder panel.
- **Removed the Buckler offhand** — was stat-less and added no value to the drop pool.

### Fixed

- **Energy Accelerator** now reliably rolls an elemental type (flame/cryo/electric), the flame visual respects walls, and the cone aligns with the player's aim direction.
- **Shotgun now uses ammo** (8-shot magazine, 2.5s reload) like every other bullet weapon.
- **Airstrike rocket** no longer prints a "colinear vectors" warning when falling straight down; orientation correctly tracks travel direction.
- **Airstrike X marker** appears the instant you press RMB (was delayed until after the windup); rendered as a true floor decal instead of floating geometry.
- **Host disconnect** no longer leaves clients in a frozen-but-running session — they see a clear "Session Ended" screen and can return to the menu.
- **LoS culler** no longer crashes when a static emissive glow is freed mid-frame.
- **Various MP performance hot paths**: shotgun pellet RPCs batched into a single message (was 9-18 per cast), lightning arc visuals reuse a cached mesh + material template (was allocating per tick), visual-replication anchors pooled instead of allocated per RPC.

## [0.1.3] - 2026-05-08

### Added

- **Ragdoll corpses** with physics tumble — enemies fall and roll on death (impulse derived from the killing hit), self-sink into the floor after 20s. Walk through them freely; corpses brush aside but never block. Grenades launch them.
- **Exile perk laser** — cursed enemies show a thin red "red dot sight" beam from the player to their chest while the curse ticks; persists through the auto-shot impact.
- **Shield bubble visual** — translucent white sphere around the player whenever an Active Shield is up.
- **Laser-trooper enemy archetype** — fast-firing, low-damage-per-shot ranged variant that mixes into the spawn pool alongside the existing slug-thrower ranged enemies.
- **Side-by-side equipped item comparison** — hold Shift while hovering an item to view your currently equipped piece next to it.
- **Snarky randomized death messages**, with cause-specific lines (e.g. falling into a pit gets its own pool).
- **Click your avatar** to open the character sheet (no need to remember the hotkey).

### Changed

- **Tooltips for enemies, pickups, and interactables now pin to top-center** instead of hovering above the target. Locked tooltips (LMB-held on an enemy) gain a gold border.
- **Item tooltips show only the headline DPS comparison inline**; everything else is plain values. Use Shift for the full side-by-side compare.
- **Bullets and laser bolts render as a thin elongated streak** instead of a glowing ball; charged plasma keeps its sphere look. Enemy fire is now distinctly yellow vs. player cyan.
- **Projectile speeds bumped across the board** (~2× for laser-pistol-feel weapons; charged plasma deliberately slower).
- **Bullets and AoE shots now visibly impact walls** instead of vanishing.
- **Boss is faster (1.35× chase speed) and hits harder (2.25× base damage)**.
- **Early-game enemy damage roughly doubled** (level 1–4) so combat has bite from the start.
- **Loot drop rate cut roughly in half** at every level.
- **Item rarity weights skew much harder toward common** (80% common / 14% magic / 5% rare / 1% unique). Named monsters now floor at magic instead of rare so they don't overrun the curve.
- **XP curve slowed** so the first boss lands you around level 3 instead of 5+.
- **First talent point now lands at level 2** (the first level you gain), then every 3 levels after — 2, 5, 8, 11...
- **Talent-point indicator (the green +)** moved to the upper-right of the avatar with a larger, pulsing glow.
- **Level-up banner** simplified to "Level up!" with a second line ("Talent point available (N)") only when a point was actually granted.
- **Starter chest skipped on NG+** runs — your existing gear is enough.
- **Death messages use a smaller font** so longer snark lines fit cleanly.

### Fixed

- **Multiplayer: character selection is required** before joining or hosting a multiplayer session (was being bypassed).
- **Multiplayer: phantom second avatar** no longer appears when starting a host session solo (Steam ID vs. Godot peer ID confusion).
- **Multiplayer: items can now be picked up** in MP sessions — owner-ID and host-side validation were comparing different ID spaces.
- **Multiplayer: enemy projectiles no longer crash** the game when they hit the player (charmed-pet check signature mismatch).
- **No more error spam or crashes when exiting a level or quitting to the main menu** — multiple teardown paths (SpatialGrid, ProximityLighting, mid-attack enemies) were touching detached nodes.
- **Bullets and laser bolts no longer cast jittery shadows** as they fly.

## [0.1.2] - 2026-05-06

### Added

- Low-HP warning vignette: pulsing red rim activates below 30% HP, intensity ramps as HP drops further.
- Death screen glitch effect: slice displacement + channel drops behind the death screen UI.
- Impact burst VFX on bullet and laser hits — emissive flash + light pop at the target.
- Temporal Anti-Aliasing (TAA) option in display Settings.

### Changed

- Default anti-aliasing now MSAA 4× + TAA on + 16× anisotropic filtering. Kills the texture shimmer / crawl on movement that's been there since the project started.
- Enemy HP cut 50% globally — combat was excessively grindy at higher levels.
- Player now spawns at room center; starter chest tucked into the SW corner.
- HP regen pauses while aggro'd enemies are within 12m, not just for 5s after damage.
- Enemy chase→attack transitions get hysteresis on both ranged and melee paths — no more stutter at the range boundary, melee enemies hold position between swings instead of pushing into the player.
- Death screen overlay alpha and glitch intensity toned down for readability.
- Projectile and laser glow values rebalanced now that transient lights actually spawn at full brightness.

### Fixed

- Projectile and laser-impact lights now glow on spawn — `ProximityLighting` was pre-dimming all transient lights to zero.
- Glow / bloom no longer disappears after alt-tabbing back into the game.

### Docs

- Full `/docs/` rewrite: 32-file tree consolidated into 5 short docs (`world.md`, `classes.md`, `systems.md`, `conventions.md`, `narrative-bible.md`) plus a rewritten README and CLAUDE.md.

## [0.1.1] - 2026-05-06

### Fixed

- Resource loaders for perks, monster pack affixes, and named monsters
  now load in exported Steam builds. The previous `DirAccess` enumeration
  worked in the editor but returned empty in the export, silently dropping
  every talent perk grant, every rare-pack modifier, and every named-boss
  encounter. Talent allocations now correctly grant perks again.

## [0.1.0] - 2026-04-28

### Added

- Initial Steam playtest build.
