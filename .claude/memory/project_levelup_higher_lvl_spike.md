---
name: project_levelup_higher_lvl_spike
description: "Lvl 5+ level-ups cost ~100ms — root cause was talents_panel._repaint walking 240 ColorRects + theme overrides while hidden. Fixed 2026-06-04 with dirty-flag + visibility_changed flush."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

## Status: FIX SHIPPED 2026-06-04 (awaiting playtest perf log verify)

## Root cause

`TalentsPanel` is instanced once at HUD `_ready` and stays in the tree
with `visible = false` until the player presses N. It listens for four
signals: `leveled_up`, `talents_changed`, `class_changed`,
`spec_changed`, plus `theme_changed`. All four callbacks routed to
`_repaint()`, which walks 6 trees × 5 tiers × 8 nodes = 240 ColorRects
and applies `add_theme_color_override` calls on each tier label, marker,
and node rect.

In Godot 4 each `add_theme_color_override` invalidates the control's
min-size cache and queues a redraw, which cascades up the parent
chain via `_notification(NOTIFICATION_THEME_CHANGED)`. The cost runs
even when the control is hidden — Godot doesn't short-circuit theme
invalidation on `visible = false`.

Why Lvl 5/6 specifically (vs Lvl 2 being fine): with allocations
present, the allocated-tier branches apply MORE overrides per row
(white + outline + outline_size + black outline color). Lvl 2's
single allocation was cheap; Lvl 5+ with multiple allocations
multiplied the per-row override count.

## Fix

`talents_panel.gd`:

- Added `_repaint_dirty: bool`.
- `_repaint()` early-returns with `_repaint_dirty = true` when
  `not visible`. Real repaint clears the flag.
- Connected `visibility_changed` signal → `_on_visibility_changed`
  which calls `_repaint()` if the panel became visible AND dirty.
- Open-menu path (player presses N) → `visible = true` → Godot fires
  `visibility_changed` → deferred repaint flushes.

Every `_repaint` caller (talents_changed, leveled_up, class/spec
changed, theme changed) goes through this gate now. Same dirty flag
covers all of them — no per-signal logic.

## VfxWarmup is still in play

VfxWarmup pre-compiles the StandardMaterial3D variant the level-up
ring uses; that's what fixed the Lvl 2 spike originally (16ms proc at
t=96.93). It's still doing its job — the residual ~100ms at higher
levels was a separate issue. Don't remove VfxWarmup over this fix.

## How to verify

Perf log at next playtest — Lvl 5/6 proc samples should be in the
~15-25ms band like Lvl 2, not 100ms+. Filter `level_up_*` rows in the
CSV.

If still spiky after the fix, next suspects in priority order:
1. `prototype_player._recompute_stat_bonuses` — walks gear slots, but
   gear doesn't change with level so shouldn't scale. Verify with a
   per-listener timer if the spike persists.
2. `character_panel._on_leveled_up` — sets one label, should be
   trivial; rule out anyway.
3. `_play_levelup_vfx` — creates a new StandardMaterial3D instance
   each level-up. Even with VfxWarmup caching the variant, the
   per-instance setup may still hit the first time at a given level.

## Files

- `game/scripts/ui/talents_panel.gd` — added `_repaint_dirty`,
  `_on_visibility_changed`, gate in `_repaint`.

Related: [[project_vfx_warmup]], [[los-reveal-spikes]] (other recent
proc spike fix from the same memory thread).
