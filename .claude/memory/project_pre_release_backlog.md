---
name: pre-release-backlog
description: The 5-task gate to the next Steam release (flagged 2026-06-04). Status as of 2026-06-10 — 3.5 of 5 done; remaining = Meshy clutter props (Josh) + multi-level playtest (Josh).
metadata:
  type: project
---

Josh's gate for the next Steam release (2026-06-04). Status 2026-06-10:

1. **Weapon grips — DONE.** All 11 weapons tuned on both genders via the
   F9+T live tuner; tables diverged per-gender (weapon_attachment.gd).
2. **Model feet on floor — DONE.** Player: measured AABB + forced-idle
   bone seat + 1.6m height normalization. Enemies: same measured seat,
   cached per mesh path (5477aa8). Clip grounding (a763d16) fixed the
   per-clip float on top.
3. **Interactable colliders — DONE.** Switch root cause was '#' comments
   voiding the .tscn box ([[tscn-hash-comments]]); all boxes now
   measured-aligned via scripts/tools/audit_interactables.gd; footprint-
   aware interact range fixed the unreachable elevator.
4. **Clutter placement — HALF DONE.** Nav half shipped (1cfd98c):
   footprint-aware spacing, spawn clearance, navmesh collision mask.
   Remaining: Meshy props to replace procedural white-box cover —
   waiting on Josh generating the assets.
5. **Multi-level playtest — PENDING.** ≥3 consecutive levels; unblocked
   (elevator + missions + clutter all fixed). Josh's to run.

Non-gating leftovers: medwaste decal texture (Josh/Midjourney), MP
remote aim pose (next MP session), grenade radii tuning (Josh's call),
build-time material-null console noise (known-cosmetic, see
[[godot4-runtime-gotchas]]).
