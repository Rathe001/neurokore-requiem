---
name: project_behavior_mods_wiring
description: "Behavior-mod effect dispatch pattern + which mods are implemented vs preview. 8/24 implemented as of 2026-06-04 (unchanged since 2026-05-24); recount with `grep -rln 'is_implemented = true' game/resources/behavior_mods/` before quoting numbers."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

Behavior mods route through `BehaviorModRegistry` (autoload). Effect
dispatch follows two patterns:

**A. Passive query** — `BehaviorModRegistry.get_active_param(slot, id,
key, default)` reads the rolled param value, returning `default` if the
mod isn't equipped or isn't active. Use in hot paths (move_speed math,
jump impulse, reload time computation). Examples: `servo_stride`,
`glide_pads`, `crouch_tactician`, `reflex_loader`.

**B. Event hook** — `take_damage`, `_recoil_soles_on_land`, etc. set or
clear timer/flag state on the player. Effects downstream check the
flag/timer. Examples: `pain_compiler`, `shock_discharge`, `recoil_soles`.

For outgoing-damage multipliers (Pain Compiler buff, Reflex Loader
empty penalty), aggregate through `PrototypePlayer.behavior_mod_damage_mult()`
— a single read by `PlayerCombat._deal_damage`. Adding a new offensive
buff = appending to that function, not patching every call site.

**Implemented (8 of 24), unchanged 2026-05-24 → 2026-06-04. Recount before quoting:**
- legs: `servo_stride`, `crouch_tactician`, `glide_pads`
- hands: `reflex_loader`
- chest: `pain_compiler`, `shock_discharge`
- feet: `recoil_soles`
- back: `ammo_reclamator`

**Preview (15 of 24):**
- legs: `slip_step`
- hands: `quickdraw_servos`, `static_grip`, `berserker_lock`
- chest: `kinetic_plating`, `ghost_field`
- feet: `mag_boots`, `phase_step`, `silenced_treads`
- back: `jetpack`, `phase_cloak`, `drone_bay`
- head: all 4 (`tactical_visor`, `radiant_halo`, `sensor_net`, `uv_lens`)

Head light mods are deferred until the player's existing flashlight
code (`_equipped_light`) is refactored to host arbitrary per-mod light
behavior — currently the slot type drives the light geometry, not the
mod. See [[project_attribute_system]] for the broader gear/mod design.

Drop weights (in ItemRoller): magic=0.6, rare/unique=1.0,
implemented-bias=0.85. Tuned 2026-05-24 for the 9/24 implemented
state; revisit when implemented fraction passes ~80%.
