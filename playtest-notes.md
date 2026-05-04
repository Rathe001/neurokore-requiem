# Playtest Notes

Captures the current playtest pass. Hand-off file: this is what to look for when running through the prototype to validate recent work, and where to record findings before the next batch of changes lands.

---

## What to focus on this pass (~20–30 minutes)

### 1. Did the recent fixes hold?

Quick binary checks — these were fixed in the last batch but I haven't seen confirmation:

- **First-time tooltip show** — is the very first hover the correct size, or still ballooning before settling?
- **Item drop from inventory** — drag an item out of the inventory window onto the world (or click-to-place outside the panel). Does it drop?
- **Click an out-of-range chest / door / switch** — does the player walk to it and auto-trigger the interact?
- **Active Shield breaks** — when the pool drains, does the cooldown countdown timer show on the RMB slot (numeric seconds, dim icon underneath)?
- **Minimap rotation** — walk forward (W) and watch the minimap. The world should slide DOWN the minimap (the player walks "into" the screen). If it slides at a weird angle, the rotation needs flipping.

### 2. Active offhands — feel check

Tuned blind, no signal on whether they play right:

**Shield Generator (Amplification Shield):** 25% damage reduction, 25 pool, 2-min duration, 20s cooldown on break.

- Is it noticeably absorbing hits in fights, or does the buff feel invisible?
- Does it survive long enough to feel useful, or break in two hits?
- Is 20s cooldown too long for the playtest density?

**Active Shield:** 50 pool full block, 20% movement while held, 15s cooldown on break, RMB-hold lock.

- Does the held shield feel committal in the right way, or just annoying?
- Can you reliably attack (LMB) while holding RMB? (Should work — LMB has priority in the input loop.)
- Pool persists across release/press — does that feel strategic or confusing?
- White-to-red HP-bar outline as the pool depletes — readable? Does the red transition give enough warning?

### 3. Open zones + density

Auto-density is now **1 enemy per 48 sqm**. Procgen pool has new arenas at weights 0.5 (open arena, 32×24) and 0.25 (grand arena, 48×32).

- Do you actually see big arenas appearing in procgen runs? Or did the weights bury them?
- A grand arena at full density is ~32 enemies. Too many? Too few? About right?
- Mixed-class packs (melee + ranged + healer + buffer) — does combat feel different from "wall of basic_melee"? Or do support enemies blend in?
- Pit / spike rooms now ~12% of linear slots (was ~44%). Crouch corridors ~14% (was 25%). Are they still appearing meaningfully or basically gone?

### 4. Anything else weird, surprising, or annoying

Especially:
- Anything stuck — animation, state, UI element, button.
- Numbers that feel obviously wrong (too much / too little damage, too slow / too fast).
- Visual pollution (debuff icons on corpses — should be cleared on death now; stale tooltips; wrong colours).
- UX moments where you weren't sure what was happening or what to press.
- Enemy classes / floor-ring colours not differentiating.
- Charmed pet UI (green HP bar, ♥ marker, follower count in AMB tooltip).

---

## Findings (fill in during playtest)

### Confirmed working
- First-time tooltip sizing — renders correctly on first hover
- Item drop from inventory — drag-and-drop onto world works
- Auto-interact on out-of-range objects — walks to target and triggers
- Minimap rotation — correct direction (world slides down as player walks forward)

### Broken
- **[BUG] Charmed enemy stuck hostile** — enemy loses hostile flag but keeps attacking the player. Cannot be killed, blocks door-unlock condition (room never clears). Likely a charmed-pet state that partially reverted.
- **[BUG] Minimap desyncs on level transition** — after entering a new level, minimap shows stale/wrong geometry. Needs a full rebuild on level change.
- **[BUG] Inventory drag-drop canceled on panel close** — if the player picks up an item in the inventory panel, closes the panel, then clicks the world, the drop is canceled. Should allow dropping into the world even after the panel closes. Escape key should also cancel the drag at any time.
- **[BUG] Switches remain hoverable/usable after activation** — used switches should become inert (no hover highlight, no re-trigger), same treatment as corpses.
- **[BUG] Minimap missing pillars and pits** — geometry for pillars and pits not rendered on the minimap.

### Feels wrong
- **Enemy damage too high** — shields deplete fast, player still dies very quickly after. Needs a tuning pass (reduce base enemy damage or increase shield pools).
- **Ranged enemy knockback feels bad** — with current density, constant knockback from ranged attacks makes the player bounce around the screen. Remove knockback from default ranged attacks; reserve it for special skills.
- **Active Shield feedback unclear** — hard to tell when active shield is protecting you. Proposal: overlay a white bar on top of the HP bar while the full-block shield is active. Keep the border approach for Amp Shield but make it thicker.
- **Open zones not large enough** — still feel corridory. D2's zones give a sense of being lost and unsure of direction; current arenas don't achieve that yet.
- **Exit placement too predictable** — large open zones always have the exit in the same spot. Player never has to explore.
- ~~**All enemies look identical**~~ — fixed: emission-based model tinting now clearly differentiates melee/ranged/support.

### Surprising / unexpected
- (none beyond the bugs above)

### Fixed this pass
- **Charmed enemy soft-lock** — root cause: `apply_charm()` consumed the one-shot `died` signal for the door puzzle. When charm was released (player death/FIFO), the enemy's actual death no longer decremented the door counter. Fixed by adding a `revived` signal + `ClearRoomPuzzle` dedup tracking + `PrototypeDoor.relock_one()`.
- **Minimap desync on level transition** — minimap baked once in `_ready()`, never rebaked. Added `rebake()` method and call from `prototype_root.gd` after level rebuild.
- **Minimap missing pillars** — pillars weren't in the `minimap_walkable` group. Added `add_to_group(&"minimap_walkable")` to `_build_pillar()`.
- **Ranged knockback removed** — enemy projectile `knockback_strength` set to 0.0 instead of inheriting melee knockback.
- **Enemy model tinting** — switched from invisible 25% albedo blend to emission-based tinting (`emission_energy_multiplier = 0.45`) on all mesh surfaces. Floor ring enlarged (0.7/0.88 radii, raised to y=0.06, emission energy 4.0). Melee=red, ranged=blue, support=green now clearly readable.
- **Active Shield white overlay** — added `_shield_overlay` ColorRect that tracks pool ratio. Amp Shield border thickened to 3px.
- **Enemy damage reduced ~30%** — L1: 5-8 (was 8-12), L2: 10-14 (was 14-20), L3: 15-21 (was 22-30).
- **Inventory drag persists after panel close** — held item stays attached to cursor when panel closes. Left-click world drops the item. Escape/right-click cancels. Reopening panel reparents cursor back for slot placement.
- **Switches already disable after use** — code was already correct (disables picking, unregisters from SpatialGrid, greys out lamp). Visual distinction may need to be more dramatic.

### Not addressed yet (level gen tuning)
- Open zones too small / exit placement too predictable — requires level generation changes, deferred to next pass.

---

## After the playtest — next priorities

(In order, per the post-playtest plan)

1. **Triage findings** — fix the breakage list first.
2. **Ability module extraction from `PrototypePlayer`** — refactor per-spec mechanics (Doomsayer aura tick, Telekinesis, Drone Swarm reconcile, IED, shield buff state) into self-contained modules. PrototypePlayer is ~2000 lines and the next active offhand / talent-granted skill will compound the bloat.
3. **Junk-drawer chest cleanup** — gate the "give the player every test item" path behind a debug flag so the canonical chest tests the actual loot pipeline.
4. **Content authoring** — author 15–20 talent nodes (start with one class tree depth-first), 6–8 new enemy classes (sniper, tank, summoner, kamikaze, healer-priest, etc.).
5. **Grenade offhand** — third active-offhand archetype, blocked on the cursor-aim UX design.
