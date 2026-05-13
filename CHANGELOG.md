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
