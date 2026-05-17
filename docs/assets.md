# Third-Party Asset Manifest

Single source of truth for every external asset shipped with the game.
Use this to compile credits and audit licenses before any Steam release.

**Convention:** when a new asset is added, append a row here with the
source URL. Mark **License** as `TBD` if you haven't checked terms yet
— do not ship until every used asset has a verified license.

## Status legend

| Status | Meaning |
|---|---|
| ✅ | License verified, terms allow shipping in this commercial game |
| ⚠️ | TBD — link captured, license not yet reviewed |
| ❌ | License does NOT allow shipping — replace before release |

## 3D Models

_None added from third-party sources yet. Player + enemy + drone use Quaternius
(`game/art/3d/characters/quaternius/UAL1_Standard.glb` etc.) which is CC0._

| Asset | Source | License | Files | Status | Notes |
|---|---|---|---|---|---|
| UAL1 Standard | Quaternius | CC0 (verify) | `game/art/3d/characters/quaternius/UAL1_Standard.glb` | ⚠️ | Default character rig used for player + every enemy class |
| Sci-fi Droid Robot | [Blenderkit](https://www.blenderkit.com/get-blenderkit/45ee98c2-d943-4cd8-bbc7-48e12c134040/) | Blenderkit — listed Free | `game/assets/models/objects/automaton_drone/automaton_drone.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Container Large | [Blenderkit](https://www.blenderkit.com/get-blenderkit/cab2b16d-19f4-4a70-8b79-09b309ad8a7b/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Container Large | [Blenderkit](https://www.blenderkit.com/get-blenderkit/cab2b16d-19f4-4a70-8b79-09b309ad8a7b/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Container Large | [Blenderkit](https://www.blenderkit.com/get-blenderkit/cab2b16d-19f4-4a70-8b79-09b309ad8a7b/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Container Large | [Blenderkit](https://www.blenderkit.com/get-blenderkit/cab2b16d-19f4-4a70-8b79-09b309ad8a7b/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-Fi-Crates | [Blenderkit](https://www.blenderkit.com/get-blenderkit/eb8d11d2-5ee1-43c6-8a75-5579fecb8f4e/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci Fi Storage Box | [Blenderkit](https://www.blenderkit.com/get-blenderkit/a83d36c9-b798-4adf-91b7-37617eb7c6e0/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci Fi Crate | [Blenderkit](https://www.blenderkit.com/get-blenderkit/503c664a-f5e7-46cb-b6dd-3057cc45374f/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci Fi Crate | [Blenderkit](https://www.blenderkit.com/get-blenderkit/503c664a-f5e7-46cb-b6dd-3057cc45374f/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci Fi Crate | [Blenderkit](https://www.blenderkit.com/get-blenderkit/503c664a-f5e7-46cb-b6dd-3057cc45374f/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci Fi Crate | [Blenderkit](https://www.blenderkit.com/get-blenderkit/503c664a-f5e7-46cb-b6dd-3057cc45374f/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci Fi Crate | [Blenderkit](https://www.blenderkit.com/get-blenderkit/503c664a-f5e7-46cb-b6dd-3057cc45374f/) | Blenderkit — listed Free | `game/assets/models/objects/loot_crate/loot_crate.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-Fi Industrial Panel | [Blenderkit](https://www.blenderkit.com/get-blenderkit/c862aced-0b3d-43e7-854c-2daf6efb57b6/) | Blenderkit — listed Free | `game/assets/models/objects/wall_industrial_panel/wall_industrial_panel.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-fi floor panel | [Blenderkit](https://www.blenderkit.com/get-blenderkit/00de98b1-2397-40ad-a4d6-171772d5c2c4/) | Blenderkit — listed Free | `game/assets/models/objects/floor_panel/floor_panel.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-Fi Industrial Panel | [Blenderkit](https://www.blenderkit.com/get-blenderkit/c862aced-0b3d-43e7-854c-2daf6efb57b6/) | Blenderkit — listed Free | `game/assets/models/objects/wall_industrial_panel/wall_industrial_panel.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-fi floor panel | [Blenderkit](https://www.blenderkit.com/get-blenderkit/00de98b1-2397-40ad-a4d6-171772d5c2c4/) | Blenderkit — listed Free | `game/assets/models/objects/floor_panel/floor_panel.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-fi floor panel | [Blenderkit](https://www.blenderkit.com/get-blenderkit/00de98b1-2397-40ad-a4d6-171772d5c2c4/) | Blenderkit — listed Free | `game/assets/models/objects/floor_panel/floor_panel.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-Fi Industrial Panel | [Blenderkit](https://www.blenderkit.com/get-blenderkit/c862aced-0b3d-43e7-854c-2daf6efb57b6/) | Blenderkit — listed Free | `game/assets/models/objects/wall_industrial_panel/wall_industrial_panel.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-fi floor panel | [Blenderkit](https://www.blenderkit.com/get-blenderkit/00de98b1-2397-40ad-a4d6-171772d5c2c4/) | Blenderkit — listed Free | `game/assets/models/objects/floor_panel/floor_panel.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |
| Sci-fi floor panel | [Blenderkit](https://www.blenderkit.com/get-blenderkit/00de98b1-2397-40ad-a4d6-171772d5c2c4/) | Blenderkit — listed Free | `game/assets/models/objects/floor_panel/floor_panel.glb` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |


## Audio — SFX (YouTube extracts)

Pulled via `tools/audio/extract_yt_sfx.py`. All YouTube extracts need
license review — public videos rarely include explicit usage rights.
Check description for CC license or assume "All Rights Reserved" and
replace before commercial release.

| Use | Source | License | Files | Status |
|---|---|---|---|---|
| Unarmed swing | [youtu.be/NZvCnpYdHqE](https://www.youtube.com/watch?v=NZvCnpYdHqE) | TBD | `sfx/weapons/unarmed_swing_01..05.wav` | ⚠️ |
| Blade swing (katana SFX) | [youtu.be/Ds9zM_tfTKA](https://www.youtube.com/watch?v=Ds9zM_tfTKA) | TBD | `sfx/weapons/blade_swing_01..04.wav` | ⚠️ |
| Enemy death | [youtu.be/yhB-mjTXTSM](https://www.youtube.com/watch?v=yhB-mjTXTSM) | TBD | `sfx/enemies/enemy_death_01..09.wav` | ⚠️ |
| IED placement + detonation | [youtu.be/847x3k0XkDc](https://www.youtube.com/watch?v=847x3k0XkDc) | TBD | `sfx/world/ied_place_01..03.wav`, `sfx/weapons/ied_detonate_01..04.wav` | ⚠️ |
| Plasma rifle fire | [youtu.be/3hvoeCyVrSA](https://www.youtube.com/watch?v=3hvoeCyVrSA) | TBD | `sfx/weapons/plasma_rifle_01..05.wav` | ⚠️ |
| Shield raise / hit / break | [youtu.be/dTYDNswLI88](https://www.youtube.com/watch?v=dTYDNswLI88) | TBD | `sfx/weapons/shield_raise.wav`, `shield_hit_01..02.wav`, `shield_break.wav` | ⚠️ |
| Switch click | [youtu.be/hkM2fSSsPCY](https://www.youtube.com/watch?v=hkM2fSSsPCY) | TBD | `sfx/world/switch_click.wav` | ⚠️ |
| Door open / close | [youtu.be/Mk4mZ30M5FE](https://www.youtube.com/watch?v=Mk4mZ30M5FE) | TBD | `sfx/world/door_open.wav`, `door_close.wav` | ⚠️ |
| Chest open | [youtu.be/5u8Z82IITLI](https://www.youtube.com/watch?v=5u8Z82IITLI) | TBD | `sfx/world/chest_open.wav` | ⚠️ |

## Audio — Ambient

| Use | Source | License | Files | Status |
|---|---|---|---|---|
| Floor ambience loop | [youtu.be/P1rgc5FBPOM](https://www.youtube.com/watch?v=P1rgc5FBPOM) | TBD | `ambient/floor_01.ogg` (68 min) | ⚠️ |

## Audio — Pre-existing (provenance unverified)

These audio assets were added in earlier sessions before this manifest
existed. Source is unknown unless noted. Need to either re-source with
known licenses or replace before commercial release.

| Use | Source | License | Files | Status |
|---|---|---|---|---|
| Hit flesh (5 samples) | "royalty-free pack" — exact pack unknown | TBD | `sfx/enemies/hit_flesh_01..05.wav` | ⚠️ |
| Explosion (5 samples) | "royalty-free pack" — exact pack unknown | TBD | `sfx/weapons/explosion_01..05.wav` | ⚠️ |
| Sniper rifle fire (5 samples) | ".50 cal samples from new pack" — exact pack unknown | TBD | `sfx/weapons/sniper_fire_01..05.wav` | ⚠️ |
| Hit grunt (10 samples) | unknown | TBD | `sfx/player/hit_grunt_01..10.wav` | ⚠️ |
| Footsteps metal (10 samples) | unknown | TBD | `sfx/player/step_metal_01..10.wav` | ⚠️ |
| Footsteps grate (4 samples) | unknown | TBD | `sfx/player/step_grate_01..04.wav` | ⚠️ |
| RPG fire (4) + impact (1) | unknown | TBD | `sfx/weapons/rpg_fire_01..04.wav`, `rpg-impact.wav` | ⚠️ |
| Shotgun fire (8 samples) | unknown | TBD | `sfx/weapons/shotgun_fire_01..08.wav` | ⚠️ |
| SMG fire (6 samples) | unknown | TBD | `sfx/weapons/smg_fire_01..06.wav` | ⚠️ |
| LMG fire (6 samples) | unknown | TBD | `sfx/weapons/lmg_fire_01..06.wav` | ⚠️ |
| Laser pistol fire (5 samples) | unknown | TBD | `sfx/weapons/laser_pistol_fire_01..05.wav` | ⚠️ |
| Sledge hit (4 samples) | unknown | TBD | `sfx/weapons/sledge_hit_01..04.wav` | ⚠️ |
| Reload (6 samples) | unknown | TBD | `sfx/weapons/reload_01..06.wav` | ⚠️ |
| Accelerator + Taser channel loops | unknown | TBD | `sfx/weapons/energy-accelerator(-hold).wav/.ogg`, `charged-arc-taser(-hold).wav/.ogg` | ⚠️ |
| Bluezone sci-fi weapon pack samples | Filenames suggest **Bluezone Corporation BC0295** library (commercial sample pack) | TBD — verify license seat | `sfx/weapons/Bluezone_BC0295_*.wav` | ⚠️ |
| UI clicks / hover / confirm / back / navigate / open | unknown | TBD | `sfx/ui/ui_*.wav` | ⚠️ |

## Audio — Music

| Track | Source | License | Files | Status |
|---|---|---|---|---|
| Level music 1–5 | unknown | TBD | `music/level1..5.mp3` | ⚠️ |

## Process

- **Before adding any new asset**, capture the source URL in this file.
- **Before shipping**, every row with status ⚠️ must be resolved to ✅ or
  the asset must be removed/replaced.
- **For YouTube extracts**: read the video description for an explicit
  license (CC-BY, CC0, royalty-free declaration). If absent, the audio
  is presumed All Rights Reserved and not shippable. Many "sfx pack"
  videos are uploads of paid packs and infringe on the original — those
  cannot be used even if the YouTuber claims they're free.
- **For Blenderkit**: each asset page lists the license. Royalty Free is
  shippable; CC-BY needs attribution; Editorial / CC-NC cannot ship.
- **For commercial packs** (Bluezone, etc.): verify the seat license
  covers a Steam release with the projected sales tier.
