---
name: pre-release-backlog
description: The 5-task gate to the v0.5.0 Steam release — SHIPPED & LIVE 2026-06-19 (BuildID 23824650). 3.5/5 were formally done; #4b (Meshy clutter) and #5 (multi-level playtest) shipped as-is and are now open quality items, not release gates.
metadata:
  type: project
---

Josh's gate for the v0.5.0 Steam release (flagged 2026-06-04). **v0.5.0 went
LIVE on the default branch 2026-06-19** (BuildID 23824650) — the gate is closed
by the act of shipping; the two unfinished items shipped as-is rather than
blocking the release. See [[Steam Playtest live]] for version history + deploy
gotchas.

1. **Weapon grips — DONE.** All 11 weapons tuned on both genders via the
   F9+T live tuner; tables diverged per-gender (weapon_attachment.gd).
2. **Model feet on floor — DONE.** Player + enemy measured AABB + forced-idle
   bone seat; clip grounding (a763d16) fixed the per-clip float on top.
3. **Interactable colliders — DONE.** Switch root cause was '#' comments
   voiding the .tscn box ([[tscn-hash-comments]]); footprint-aware interact
   range fixed the unreachable elevator.
4. **Clutter placement — nav half DONE, props NOT done.** Footprint-aware
   spacing, spawn clearance, navmesh mask all shipped. **0.5.0 shipped with the
   procedural white-box cover** — Meshy props to replace it were never made.
   Still an open quality item; needs Josh to generate the assets.
5. **Multi-level playtest — NOT formally run before release.** 0.5.0 shipped
   without a confirmed ≥3-level playthrough. Now a POST-release validation item:
   the 0.5.0 patch notes nudge testers toward multi-level runs, so watch
   playtest reports for level-transition / progression bugs.

Non-gating leftovers still open: medwaste decal texture (Josh/Midjourney), MP
remote aim pose (next MP session), grenade radii tuning (Josh's call),
build-time material-null console noise (known-cosmetic, see
[[godot4-runtime-gotchas]]).
