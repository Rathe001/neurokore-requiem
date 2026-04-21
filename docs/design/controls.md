# Controls

## Initial Release: Mouse + Keyboard

| Input | Action |
|---|---|
| W / A / S / D | Movement |
| Left mouse button | Basic single-target attack |
| Right mouse button | Basic AoE attack |
| 1 | First class skill |
| 2 – ? | Subsequent skills (TBD per [Skill Tree](skill-tree.md)) |

**No click-to-move.** Left and right mouse buttons are reserved for the basic attacks defined in [Skill Tree](skill-tree.md). Movement is keyboard only — the modern ARPG / twin-stick convention.

---

## Controller Support

Planned but not in the initial prototype. Notes for when we get there:

- Left analog stick → movement
- Right analog stick → attack/skill targeting (or aim assist)
- Face buttons → basic attacks and skill 1
- Triggers / shoulders → additional skill slots
- Rebinding UI required for both controller and mouse/keyboard

The input action system in `project.godot` is the single source of truth for bindings, so adding controller bindings is additive — not a rewrite.

!!! question "Open Questions"
    - Aim model on controller: free aim with right stick, lock-on, or hybrid?
    - Should controller users get a target reticle that mouse users don't?
    - Local co-op via mixed input (one player on M+KB, one on controller) — defer to multiplayer phase.
