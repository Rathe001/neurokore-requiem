---
name: project_audio_listener_anchor
description: Player-anchored audio must follow the listener every frame; setting source position once at play-time causes panning to drift opposite player movement
metadata:
  type: project
---

The AudioListener3D lives on prototype_camera (top-level, current=true, at
player chest height) and is updated each frame in `_snap_to_target` to follow
the player. AudioStreamPlayer3D source positions, however, are set ONCE at
play-time. After even one frame of player motion, source and listener are
displaced — and panning is computed from their relative offset, so the
source appears in the stereo direction OPPOSITE the player's movement.

Symptom: player moves left → sound shifts to stereo right.

**Fix pattern in SFX autoload:**
- `play_at_listener` / `claim_reserved_at_listener` mark the returned
  AudioStreamPlayer3D with `set_meta(_ANCHORED_META, true)`
- SFX._process snaps every flagged player's `global_position` to the live
  listener position each frame
- `SFX.process_priority = 100` so the snap runs AFTER prototype_camera's
  `_snap_to_target` updates the listener — otherwise we'd re-introduce a
  1-frame drift
- `_claim_player()` clears the meta when reusing a slot, so listener-anchor
  doesn't leak into a non-listener caller
- Camera's AudioListener3D is registered into the `&"audio_listener"` group
  so SFX can resolve it without coupling to the camera class

**For any new player-anchored sound:** route through `SFX.play_at_listener`
or `SFX.claim_reserved_at_listener` — never `play_at` with the player
position. The anchor flag is the contract that keeps source and listener
co-located.

**Channel-loop note:** `WeaponSounds.update_channel_position` checks the
anchor meta and skips repositioning anchored players, since SFX._process
already locks them to the listener. Enemy channel loops (unanchored) still
follow their wielder normally.

Related: [[project_audio_architecture]], [[project_sfx_gaps]]
