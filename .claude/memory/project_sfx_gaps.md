---
name: SFX gaps as of 2026-06-04
description: "What audio still needs wiring. Updated 2026-06-04 after audit Phase 2b: hit_player is now wired (5 samples); play_miss + play_alt_fire functions were deleted as unused. Remaining gaps below."
type: project
originSessionId: eba7e73f-d7f6-4e08-be8e-53f1c4f66d76
---
Audio progress is most-of-the-way there. Categories below in priority order. All paths assume the existing `WeaponSounds.play_*` API.

**Active call sites with no sound (player will hear silence):**

- **Per-weapon impacts (non-RPG)** — `play_impact(weapon_base_id, pos)` runs on every projectile detonation; only `rpg_2h` has an `impact` array wired (`weapon_sounds.gd:343`). Cheapest fix: a single shared `&"bullet_ricochet"` generic that all kinetic weapons trigger instead of per-archetype impacts. Generic `hit_flesh` already covers the enemy-side feedback.

**Has 1 sample, could use variety:**

- **Plasma rifle (`ranged_2h`)** — single `plasma-rifle.wav` only. Outlier vs other ranged weapons which all have 4-6 sample arrays.

**Closed since last update:**

- ✓ **`hit_player`** wired with 5 samples (`weapon_sounds.gd:427`).
- ✗ **`play_miss`** — function deleted in audit Phase 2b (`31882ff`). If we want miss audio, re-add the function and the callers in one pass.
- ✗ **`play_alt_fire`** — function deleted in audit Phase 2b. Same note.

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
