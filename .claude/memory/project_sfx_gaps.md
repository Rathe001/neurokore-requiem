---
name: SFX gaps as of 2026-05-12
description: What audio still needs wiring after the May 11-12 audio session — call sites that fire silently, single-sample weapons, future-work systems
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
Audio progress is most-of-the-way there. Categories below in priority order. All paths assume the existing `WeaponSounds.play_*` API.

**Active call sites with no sound (player will hear silence):**

- **`hit_player`** — called from `prototype_player.gd:832` every time the player takes damage. Biggest perceptual gap; getting shot currently has no audio feedback beyond the optional hit_grunt. Register via `WeaponSounds.register_generic(&"hit_player", _streams([...]))`.
- **Per-weapon impacts (non-RPG)** — `play_impact(weapon_base_id, pos)` runs on every projectile detonation; only `rpg_2h` has an `impact` array wired. Cheapest fix: a single shared `&"bullet_ricochet"` generic that all kinetic weapons trigger instead of per-archetype impacts. Generic `hit_flesh` already covers the enemy-side feedback.

**Has 1 sample, could use variety:**

- **Plasma rifle (`ranged_2h`)** — single `plasma-rifle.wav` only. Outlier vs other ranged weapons which all have 4-6 sample arrays.

**API exists, no call sites yet (needs both code wiring and assets):**

- **`play_miss`** — melee whiff / ranged ricochet on miss. No callers yet.
- **`play_alt_fire`** — secondary fire mode. No callers yet.

**No system yet (future):**

- Enemy death sound (silent kills)
- Item pickup / credit pickup chime
- Door open/close, switch toggle
- Skill cooldown ready audio cue
- Level up sting
- Ambient zone loops (machine hum, distant chatter — Ambient bus exists but unused)

**Already wired this session (don't re-do):**

- `hit_flesh` (5 samples @ -3 dB at the call site)
- `explosion` generic (5 samples)
- Sniper rifle, RPG, laser pistol fire (multi-sample arrays)
- Footstep metal + grate
- UI sounds (click, hover, confirm, back, navigate, open)
- Channel hold loops for taser + accelerator
- Player `hit_grunt` (10 samples)

**Why:** Keeps the next audio session from re-auditing what's done vs what's missing.

**How to apply:** When the user asks "what audio still needs work" or starts a fresh SFX-wiring session, consult this before re-grepping the call sites. Update this memory as gaps close.
