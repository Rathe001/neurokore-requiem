# Controls

## Initial Release: Mouse + Keyboard

| Input | Action |
|---|---|
| W / A / S / D | Movement |
| Space | Jump |
| Left Ctrl | Crouch (hold) |
| V | Toggle FPS camera |
| Left mouse button | Fire (weapon's primary attack) |
| Right mouse button | Alt Fire (offhand attack if 1H weapon; weapon's alt attack if 2H weapon) |
| R | Reload (ranged weapons only — see [Gear Augmentation](gear-augmentation.md#magazine--reload)) |
| 1 | First class skill / Interact (near interactable or crosshair on interactable in FPS) |
| 2 – ? | Subsequent skills (TBD per [Skill Tree](skill-tree.md)) |
| F | Interact (proximity, iso view) |
| Tab | Toggle minimap (corner ↔ fullscreen) |
| Escape | Close fullscreen minimap (also opens main menu from corner view) |
| L | Toggle equipped light |

**No click-to-move.** Left and right mouse buttons are reserved for Fire and Alt Fire as defined in [Skill Tree](skill-tree.md). Movement is keyboard only — the modern ARPG / twin-stick convention.

## FPS Mode

Pressing **V** toggles between the fixed isometric camera and a first-person camera. In FPS mode:

- Mouse look controls camera pitch and player yaw (cursor is captured).
- A crosshair is always visible. When the crosshair is over an interactable (door, switch, etc.) the outline and tooltip appear, matching the iso hover behavior.
- Pressing **1** while the crosshair is on an interactable triggers the interaction.
- A fill light attached to the FPS camera illuminates the immediate area so dark zones remain navigable.

## Crouch

Hold **Left Ctrl** to crouch. While crouching:

- Movement speed is reduced (~45% of normal).
- The player's collision capsule shrinks so they can pass through low-ceiling corridors.
- If inside a crouch-only zone (low ceiling block present), the player is **locked to crouching** and cannot stand even if the key is released — they must leave the zone first.
- In FPS mode the camera drops to head height for the crouched stance.

---

## Controller Support

Planned but not in the initial prototype. Notes for when we get there:

- Left analog stick → movement
- Right analog stick → attack/skill targeting (or aim assist)
- Face buttons → Fire / Alt Fire and skill 1
- Triggers / shoulders → additional skill slots
- Rebinding UI required for both controller and mouse/keyboard

The input action system in `project.godot` is the single source of truth for bindings, so adding controller bindings is additive — not a rewrite.

!!! question "Open Questions"
    - Aim model on controller: free aim with right stick, lock-on, or hybrid?
    - Should controller users get a target reticle that mouse users don't?
    - Local co-op via mixed input (one player on M+KB, one on controller) — defer to multiplayer phase.
