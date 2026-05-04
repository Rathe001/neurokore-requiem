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
-

### Broken
-

### Feels wrong
-

### Surprising / unexpected
-

---

## After the playtest — next priorities

(In order, per the post-playtest plan)

1. **Triage findings** — fix the breakage list first.
2. **Ability module extraction from `PrototypePlayer`** — refactor per-spec mechanics (Doomsayer aura tick, Telekinesis, Drone Swarm reconcile, IED, shield buff state) into self-contained modules. PrototypePlayer is ~2000 lines and the next active offhand / talent-granted skill will compound the bloat.
3. **Junk-drawer chest cleanup** — gate the "give the player every test item" path behind a debug flag so the canonical chest tests the actual loot pipeline.
4. **Content authoring** — author 15–20 talent nodes (start with one class tree depth-first), 6–8 new enemy classes (sniper, tank, summoner, kamikaze, healer-priest, etc.).
5. **Grenade offhand** — third active-offhand archetype, blocked on the cursor-aim UX design.
