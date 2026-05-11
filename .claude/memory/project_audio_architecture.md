---
name: Audio architecture
description: Spatial audio system — bus layout, room-aware reverb, SFX pool, weapon sound registry; all wired but silent until assets are added
type: project
---

Spatial audio architecture shipped (ee5359c, 2026-05-11). Four autoload-level systems:

- **Bus layout** (`resources/audio/default_bus_layout.tres`): Master > Music, SFX, Ambient, UI, ReverbSend (with AudioEffectReverb)
- **AcousticProfile** (`scripts/audio/acoustic_profile.gd`): Resource with reverb params; `from_area()` auto-derives from room m²
- **RoomAcoustics** (`scripts/audio/room_acoustics.gd`): Autoload, cell-gated player zone tracking, crossfades reverb on ReverbSend bus. LevelBuilder registers zones per room/corridor at build time.
- **SFX** (`scripts/audio/sfx.gd`): Autoload, 16-node AudioStreamPlayer3D pool, `play_at(stream, pos)` fire-and-forget
- **WeaponSounds** (`scripts/audio/weapon_sounds.gd`): Autoload, maps weapon_base_id / enemy weapon_id → sound sets (fire/impact/miss/reload). Enemy IDs alias to player base IDs via `_ENEMY_TO_BASE`.

**Why:** User wants room-aware acoustics (small hallway vs large echoey room). System is architecture-only — runs silently until `.wav`/`.ogg` assets are dropped into `resources/audio/sfx/weapons/{archetype}/` and registered in `weapon_sounds.gd`'s `_ensure_loaded()`.

**How to apply:** When adding sounds, register in WeaponSounds. When adding new rooms, acoustic profile auto-derives from geometry unless overridden via RoomDef/CorridorDef export. RoomDef and CorridorDef both have `acoustic_profile: AcousticProfile` export under Audio group.
