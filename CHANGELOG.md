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
