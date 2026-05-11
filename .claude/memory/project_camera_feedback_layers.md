---
name: Camera feedback layers
description: Three independent camera mechanics in PrototypeCamera (shake, push, no lookahead) — what each is for and where the per-archetype tuning lives
type: project
---

PrototypeCamera has two distinct feedback layers, intentionally separate:

- **`shake(intensity, duration)`** — random ±intensity jitter on the camera position each frame. Used for impact / recoil. Manual decay envelope (no tween — tweens collided on rapid fire), with `SHAKE_HOLD_FRAC` peak hold then quadratic ease-out. Overlap semantics: `max(current_live_intensity, new)` for peak, `max(current_remaining, new_duration)` for time — so a small SMG shake on top of a heavy grenade shake doesn't shorten the grenade.
- **`push_at(source, aim_dir, impulse)`** — directional offset opposite aim, spring-back to neutral. Used for energy weapons to read as "pressure" rather than "impact." Modeled as velocity + position with `PUSH_DAMPING` / `PUSH_RECOVERY`, clamped to `PUSH_MAX`. Distinct from shake by design.
- **No cursor lookahead.** Was removed — conflicted with shake/push and felt disorienting. Don't reintroduce without checking with the user first.

**Per-archetype tuning tables live in `game/scripts/prototype/player_combat.gd`:**

- `RECOIL_SHAKE_BY_BASE_ID` — kinetic weapon fire-time shake (SMG/LMG/sniper/shotgun). RPG omitted; its shake fires on impact instead.
- `ENERGY_PUSH_BY_BASE_ID` — energy weapon push impulse (laser pistol/plasma rifle/accelerator/taser).
- `MELEE_SHAKE_BY_STEP_1H` / `MELEE_SHAKE_BY_STEP_2H` — escalating per combo step (0/1/2), 2H heavier than 1H at every step.

**Impact shakes** fire from inside the projectile/grenade detonation code:
- `prototype_projectile._explode` checks `weapon_base_id == &"rpg_2h"` → `PrototypeCamera.shake_at`.
- `prototype_grenade._detonate` → `PrototypeCamera.shake_at` for all grenades.
- `shake_at` measures distance from camera focal point (= player position via `focal_position()`), NOT camera global_position. The iso camera is always ~14u away so position-distance would always be near the falloff edge.

**Why:** Established this session after tuning iterations; the user explicitly chose this layering and disabled lookahead.

**How to apply:** When adding a new weapon archetype, decide whether it's kinetic (recoil shake on fire), energy (push on fire), or melee (combo-step shake). Add an entry to the appropriate dict — don't write inline `cam.shake()` calls in branch-specific code paths.

**MP gap:** Impact shakes (`shake_at` from `_explode`/`_detonate`) only fire on the peer running the detonation (host for replicated projectiles). Teammates near a host-authoritative blast won't feel it. Not fixed yet.
