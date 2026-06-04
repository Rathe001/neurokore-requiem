---
name: pre-release-backlog
description: "Tracked tasks Josh queued 2026-06-04 to clear before the next Steam release. Asset polish + interactive cleanup + multi-level playtest. Once done he expects to ship."
type: project
---

User-stated 2026-06-04: "Once those are completed, we'll be in good
shape for the next Steam release." Items in the order he listed them,
all unstarted. Pick any as a starting point — no declared dependencies.

## 1. Weapon attachment points need updating for all models

Visible weapons mount to the X Bot right-hand bone via
`BoneAttachment3D`. Pipeline + grip-tuning UX is documented in
[[weapon-attachment]]. Per-weapon grip transforms were live-tuned with
the F9+T tuner; some weapons still feel off (held wrong angle, wrong
position relative to the hand, clipping into the body).

**To investigate next:** equip each of the 11 weapons in turn, hit
F9+T, walk + fire to verify grip and muzzle line. Save the corrected
transform per weapon. The tuner already writes to disk.

## 2. All models' feet should be touching the floor

Imported models can sit a few cm above the floor depending on their
authored pivot. Currently most enemy variants share the X Bot mesh so
they're consistent, but boss and quirky one-off models float.

**To investigate next:** walk through each enemy archetype + boss
and visually confirm feet contact. Fix either via the spawn Y offset
in the EnemyClass resource or by re-importing the .glb with the pivot
moved. See [[xbot-character]] for the pipeline.

## 3. Interactable collision boxes need updating

User report: collision shapes on interactables (loot crates, switches,
doors, exit pads) don't match the visual mesh — either clickable area
extends beyond the mesh or fails to register on the visible silhouette.

**To investigate next:** for each interactable scene, compare the
`CollisionShape3D` extents against the mesh AABB. Probably an audit
sweep + visualizer toggle while in-engine.

## 4. Clutter / junk needs to make more sense and not trap enemies

Current procgen clutter scatters destructibles + indestructibles
(barriers, server racks, pipes, grates) inside rooms. The placement
sometimes blocks navmesh corridors so enemies wedge against them and
have to rely on the chase-stuck warp.

**To investigate next:** review clutter density + placement rules in
the procgen pass. Consider gating clutter on navmesh distance (don't
place where it'd narrow the navmesh to one body-width). Related:
[[level-architecture]], [[enemy-navigation]].

## 5. Playtest multi-level sessions

Most playtests have been single-level loops. Need end-to-end runs
through several levels in one session to surface bugs that only show
up across transitions: memory growth, leftover state on level reload,
spawn carryover, save/load between levels, etc.

**To investigate next:** run a session that plays through ≥ 3 levels
consecutively, watch perf log + console for warnings, verify HUD /
talents / inventory state survives transitions cleanly.

## Definition of done for this list

Josh: "I think once those are completed, we'll be in good shape for
the next Steam release." Treat as the gate, not as the entire pre-ship
checklist — there's likely tuning + balance polish on top, but these
five are what he flagged as blocking.
