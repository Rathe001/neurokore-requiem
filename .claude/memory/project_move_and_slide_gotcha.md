---
name: move_and_slide velocity loss on walls
description: Godot's move_and_slide zeroes velocity against walls; jumping while pressed into obstacles needs explicit momentum injection
type: project
---

Godot's `move_and_slide()` zeroes the velocity component that hits a wall. Since airborne horizontal velocity is frozen (the `if not _is_airborne:` block skips), jumping while pressed into an obstacle results in a straight-up jump with zero forward momentum.

**Fix pattern:** At jump time, check if `_want_dir` (previous frame's input) has magnitude but horizontal velocity is near-zero (< 1.0 m/s squared), and inject `_want_dir * move_speed` as initial airborne velocity. This lets the player vault over low obstacles.

**Why:** Clutter objects (0.4-1.0m tall) with 1.6m collision height were impossible to jump over while moving into them. The player had to back up, then run-jump.

**How to apply:** Any future mechanic that reads velocity after `move_and_slide()` for movement decisions (dash, dodge, etc.) should use the pre-slide wish direction, not post-slide velocity. The `wish_horiz` capture before `move_and_slide()` already follows this pattern for StepUp.
