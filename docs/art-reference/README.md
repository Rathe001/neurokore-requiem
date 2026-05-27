# Art Reference Bible — Neurokore: Requiem (2D iso rework)

This folder is the visual-style lock for the 2D iso pivot. Every sprite
gen, every tile gen, every UI element should pass the "does it sit
cleanly next to these 48 images" test.

The goal style: **hand-painted 1996-2000 ARPG**, dimetric iso (~26.5°,
2:1 tile ratio), gritty body-horror cyberpunk tone, complementary-color
lighting (red+teal / orange+cyan), heavy baked shadows. Imagine
Diablo 2 made by the Sanitarium team with a Crusader: No Remorse art
direction nudge.

What it is NOT: clean 3D-rendered hero shots on floating platforms,
modern indie 3D-character polish, painterly-but-bright JRPG vibes.
Nine drift-style images were generated and deleted earlier in this
session — if future gens look like those (isolated character on black
background with neon platform, "League key art" lighting), the prompt
needs the painted-style anchors below.

## Midjourney prompt locking

The painted aesthetic in this bible was locked using the file with
prefix `httpss.mj.run1Lz-I0yhrNI_` as the reference image — that
reference URL (or one anchored on the soldier sprite `374b6a95`)
should be the `--sref` source for all future gens. If MJ rejects
`--sref`, try `--oref` or inline URL at prompt start.

**Always-include negative prompts:**

> NOT 3D rendered, NOT clean polish, NOT modern indie style, NOT
> isolated on black background, NOT floating platform hero shot

---

## Environments (13 images)

Painted iso scenes. Use as `--sref` style anchors for tile / room
generation. Each one suggests a theme variant for procgen levels.

### Primary references (use these first)

- **`larg_aaec3751..._3.png`** — Crimson sanctum corridor. Two figures
  with rifles approaching a red-glow shrine room. **The single best
  reference in the set** — character scale visible, dramatic lighting
  that doesn't fight gameplay readability, perfect D2 iso angle. Anchor
  for "sub-level / sanctum / dungeon" theme.

- **`Diablo_2_..._low_light_bas_5b7251e8..._2.png`** — Sanitarium dome
  with stairwells and warm light through grates. Single tiny figure
  shows character scale at iso. Closest framing to actual D2 dungeon
  composition. Anchor for "facility interior / dome / industrial
  silhouette" theme.

- **`Sci_Fi_..._huma_80349311..._3.png`** — Asylum cell with table,
  vault door, grates. Lowest visual noise of any reference — entities
  would read cleanly against this. Anchor for "personal quarters /
  cell / interior" theme.

### Secondary references

- **`Diablo_2_..._high_tech_pri_b44f4cb2..._1.png`** — Infernal forge
  with blue stone + molten orange pipes + grate floors. Anchor for
  "danger biome / boss arena / hot biome."
- **`Sci_Fi_..._alie_649857a0..._0.png`** — Red neon street with
  lamp + characters. Anchor for "outdoor / transition / town hub."
- **`Sci_Fi_..._land_1e0aab5f..._3.png`** — Cyberpunk street with
  CRN neon sign + single figure at scale. Strong gameplay readability.
  Anchor for "outdoor industrial street."
- **`Sci_Fi_..._land_ef2070d9..._2.png`** — Boiler dome with vault
  door, red/teal accents. Anchor for "industrial set piece /
  destructible reactor / boss room."

### Tertiary / atmosphere references

- **`Sci_Fi_..._larg_aaec3751..._2.png`** — Cyberpunk Victorian
  street with "BURN" sign. Slightly drifts toward 2010s indie
  aesthetic; use sparingly.
- **`Sci_Fi_..._awe_474b8775..._1.png`** — Green-tinted abandoned
  lab. Very busy / cluttered; entity readability suffers against it.
  Use for "depths / forgotten zone" only.
- **`isometric_..._bloody_room_..._c5f4310f..._0.png`** — Blood-
  soaked lab with skulls + monitors. Tone is bang-on but unbuildable
  as gameplay tiles. Use as "post-fight / encounter aftermath" mood ref.
- **`isometric_..._1990s_..._chaos_50_..._30c97468..._3.png`** — BQB
  bed / personal quarters with neon sign. Flavor piece. Anchor for
  "NPC quarters / vendor room / safe zone."

### Aftermath / post-fight mood

These came back from VFX prompts but read better as
scene-establishing atmosphere than discrete VFX frames — kept here.

- **`large_realistic_b_746a852c..._0.png`** — Industrial room with
  glowing yellow energy column erupting from floor + massive blood
  splatter + character witnessing. Anchor for "boss-arena aftermath"
  or "scripted-event reveal" framing.
- **`large_realistic_b_a0df319a..._1.png`** — Gothic interior with
  body in a giant red blood pool + glowing red center + ceiling
  apparatus. Heavy body-horror atmosphere. Anchor for "ritual room /
  Enculted shrine / aftermath set piece."

---

## Player characters (7 images)

All painted style, all suitable as canonical class refs for the
bake-3D-to-2D sprite pipeline.

### Anchor reference (use as `--sref` for all char gens)

- **`Diablo_2_..._character_sprite_sci-fi_sol_374b6a95..._0.png`** —
  Male soldier with spiked shoulder pad and gun, embedded in library/
  forge. **The original painted-style anchor.** Use this as the
  reference URL for every future character gen.

### Class archetype suggestions

| Image | Visual read | Suggested class fit |
|---|---|---|
| `httpss.mj.run1Lz_..._3e664f7a..._0.png` | Male soldier with rifle, red alley | **Analog — Ranged combat** |
| `d9be6241..._0.png` | Character in red/black armor, red neon room | **Analog — Heavy** |
| `548d68af..._1.png` | Female with backpack + sash, red trim | **Analog — Pilot/scavenger** |
| `0ffb09b8..._3.png` | Bipedal mech with leg cannons | **Cyborg — Heavy combat variant** |
| `d009b01a..._0.png` | Humanoid mech on launchpad with "D" neon | **Cyborg — Alt loadout** |
| `7b2c00af..._0.png` | Female in red armor with cyan energy blade | **Polymath / Enculted — Techno-mage** |

The 4-6 distinct class archetypes here cover most of the design's
class identity space. Mapping to `docs/classes.md`:

- **Analog generalist + 3 specs** → use the soldier/heavy/pilot refs
- **Cyborg generalist + 3 specs** → use the mech refs
- **Polymath / Enculted** → use the techno-mage ref

---

## Monsters (6 images)

All painted style. Body-horror set is the strongest material in the
bible — use these as the foundation for enemy concept work.

### Body horror tier (primary monster refs)

- **`body_horror__082e8344..._3.png`** — Red parasite/crab humanoid
  with cables, near a green CRT terminal. **Anchor for "amalgamation
  / biomechanical fusion" enemies.** Body horror + sci-fi + scale all
  in one frame.
- **`body_horror__48fb5483..._3.png`** — Red walker mech with cannon
  legs facing a small character. **Anchor for "boss / elite walker"
  enemies.** Scale-via-tiny-figure framing is exemplary.
- **`body_horror__b9502765..._3.png`** — Pale humanoid with mechanical
  arms, perched, red eyes. **Anchor for "elite stalker / leaper"
  enemies.** Body horror without losing silhouette legibility.
- **`body_horror__ce70019d..._1.png`** — Vampire-faced body horror
  humanoid crouched near red neon symbol. **Anchor for "feral
  cultist / Enculted enemy"** matching the narrative bible's reps.

### 1980s sci-fi tier (set-piece monster refs)

- **`1980s_sci_fi_e09a1316..._1.png`** — Giant mech-spider with laser
  arm and umbrella plating, character at scale beside it. **Anchor
  for "boss / mini-boss / heavy walker"** encounters.
- **`1980s_sci_fi_868d172e..._0.png`** — Bedroom scene with red bed +
  small character + huge green werewolf silhouette. **Compositionally
  ambiguous** — read this as a *scene/encounter mood ref* rather than
  a single-monster sprite ref. Useful for "haunting encounter" setup.

---

## UI / HUD (3 images)

**Anti-pattern: NO globes.** Diablo 2 and Path of Exile use spherical
health/mana globes at the bottom corners — this game intentionally
avoids them because they're an over-recognized genre cliché. Use
**vertical liquid tubes** (the body horror / lab sample-tube read)
or **horizontal industrial bars** (the Crusader: No Remorse riveted-
panel read) for resource meters instead.

A fourth UI reference (`5796e8c6`, eagle/skull steampunk panel) was
deleted from the bible because it (1) included globes despite the
prompt, and (2) drifted to Warhammer 40k imperial-gothic aesthetic.

### Primary references

- **`UI_HUD_..._419af702..._3.png`** — Three-panel HUD with green/red
  liquid TUBES + steampunk gauge + tech grid panel. **The gold
  reference for the no-globes solution.** Reads as bioreactor /
  pressure-gauge / sample tube, perfectly on tone for the body-horror
  facility setting. Use as `--sref` anchor for any HUD gen. The "HUD"
  label across the top is placeholder text — strip in the real build.

- **`action_RPG_UI_..._b229fd9a..._0.png`** — Three UI element renders
  (top bar with progress meter, big center panel with vertical glass
  tubes + amber inventory readout, bottom blue/orange status bars).
  Painted-style retro-industrial, riveted metal, glass tubes again.
  Pairs cleanly with `419af702` as the second UI anchor. Closest
  visual reference to the Crusader: No Remorse HUD framing.

### Composition reference (not for meter design)

- **`UI_overlay_..._fcabae0f..._0.png`** — Full in-game frame showing
  HUD overlay in context (character + tiles + items + skill bar +
  globes at corners). **Use this for layout** — how the HUD overlays
  sit relative to the game view, where item icons land in corners,
  where the skill bar runs along the bottom. **Do NOT use it for the
  meter design itself** — its globes are exactly what we're avoiding.

### MJ prompt-locking for UI gens

```
[anchor URL = 419af702]
Sci-fi neon noir ARPG HUD overlay, vertical liquid-filled glass tubes
for health and power meters, industrial pipework framing, riveted
steel panels, painted style, solid black background, isometric overlay,
hand-painted 1996 ARPG aesthetic
--sref [419af702 URL]
NOT globes, NOT orbs, NOT spheres, NOT D2 health globes, NOT modern
flat UI, NOT eagles, NOT 40k imperial aesthetic
```

---

## Item icons (11 images)

**Painted-brush lane locked.** Anchored on `8953d79a` for continuity
with the painted environment + character bible. Closest to actual D2
inventory icons. Two early pixel-art-lean icons (`041acdbb`, `18b094ab`)
are kept as outliers — re-prompt them to match the painted lane if
they ever ship.

### Weapons

- **`8953d79a` red-barrel pistol** — Painted brush. **Anchor for the
  entire icon lane.** Use as `--sref` for every future icon gen.
- **`9c062c43` glowing combat knife** — Orange-edged ceremonial blade
  with ring pommel. Slight fantasy-ceremonial lean but the glow keeps
  it sci-fi. Anchor for "melee_1h / energy blade."
- **`01c00396` industrial sledge** — Mechanical hammer with chain +
  red-slit glow. Body-horror cyberpunk perfect. Anchor for "melee_2h."
- **`1bf54e31` sniper rifle (on book backdrop)** — Painted beautifully
  BUT framed on an arcane book + red velvet. Use the *rifle silhouette
  only*; ignore the framing.
- **`041acdbb` green sci-fi rifle** — Pixel-art with painted touches.
  Outlier in the painted-brush bible. Keep for shape reference; re-do
  in painted-brush lane if shipping.
- **`18b094ab` SMG with skull motif** — Pixel-art lean. Same caveat as
  `041acdbb`.

### Armor

- **`322b8dee` spiked chest armor** — Spiked rust-orange torso plate
  with chains crossing. Quintessential D2 inventory icon framing.
  Anchor for "body armor / chest."
- **`ddee8728` combat helmet** — Black armor helm with red visor strip
  + bull-horn pipe. **Style note: leans modern stylized rather than
  1996 painted-brush** — borderline but kept. Anchor for "helmet"
  with the caveat that head-armor gens may need a tighter painted-
  brush sref to stay on-bible.
- **`623acc0a` industrial gloves** — Bronze + green-glow body-horror
  gauntlets. Olive bg (not pure black) but the style is dead-on.
  Anchor for "gloves / gauntlets."

### Consumables & sockets

- **`b071cbc2` medical stimpack** — Bronze injector with red liquid
  tube + organic tubing. Body-horror medical perfect. Anchor for
  "stimpack / battery / consumable."
- **`60aeac2d` memory chip / rune** — Bronze circuit-board square with
  green/orange energy tendrils erupting outward. Nails the "arcane
  circuit motif" intent. Anchor for "chip / rune / socketable."

### Deleted icons (anti-references)

Documented so re-rolling doesn't repeat the same drift:

- **`a68b62ad` trenchcoat** — Returned a full paper-doll panel
  (multiple items in a framed display) WITH visible **"DIABLT"
  branding text**. Wrong format + copyright drift.
- **`1a4caef0` MRAD sniper rifle (dark)** — Returned as clean
  vector-illustration / tactical-comic style, not painted brush.
- **`db6188fc` MRAD sniper rifle (light)** — Same style drift + a
  wolf-skull logo watermark in the corner.

Pattern: when the prompt says "isolated rifle on black background"
without anchoring `--sref [8953d79a]`, MJ defaults to gun-illustration
style rather than D2 inventory style. Always pin the anchor.

### MJ prompt-locking for icon gens

```
[anchor URL = 8953d79a]
Diablo 2 inventory item icon, [WEAPON or ARMOR or CONSUMABLE
description], hand-painted brush style, illustrated, baked lighting,
isolated on solid dark background, 1996 ARPG aesthetic, gritty sci-fi
neon noir, painted texture
--sref [8953d79a URL]
NOT pixel art, NOT clean 3D render, NOT modern flat icon, NOT scene,
NOT backdrop, NOT velvet, NOT book, just the item on dark background
```

---

## VFX (8 images)

Painted aesthetic, embedded in iso scenes (NOT isolated icons). Use
as `--sref` anchors for the corresponding effect when running the
3D-to-2D sprite pipeline's stylization pass.

### Strong references (on-bible setting + effect)

- **`VFX_..._blade_slash_impac_edcd8258..._0.png`** — Three characters
  in a sanctum corridor, red blade beam + impact blast at center.
  Anchor for "melee impact / red energy weapon discharge."
- **`VFX_..._plasma_bolt_impac_49056be5..._2.png`** — Industrial
  corridor with plasma bolt of orange fire/lightning hitting wall
  apparatus. Anchor for "plasma weapon impact / hitscan VFX."
- **`VFX_..._sci-fi_grenade_ex_ba5d19c3..._2.png`** — Iso industrial
  catwalk scene with massive orange explosion + character at scale.
  Anchor for "grenade / explosive impact."
- **`VFX_..._sci-fi_weapon_muz_8e964d6b..._0.png`** — Mech-scale unit
  firing a chaingun with bright muzzle burst against industrial
  backdrop. Anchor for "muzzle flash / sustained-fire weapon."
- **`VFX_..._subtle_wispy_gree_37bbf4cb..._1.png`** — Character in iso
  scene surrounded by green particle swirl, green portal light source.
  Anchor for "heal / restore / buff burst."

### Marginal references (effect on-bible, setting drifts)

Useful for the effect SHAPE only — the underlying scene drifts to
gothic-fantasy rather than cyberpunk facility. When re-prompting,
add explicit facility/industrial/sci-fi setting words.

- **`VFX_..._blue_electric_arc_a84c4062..._2.png`** — Lightning arc
  visual is excellent; setting is gothic cathedral with arched
  windows + skull + tomb. Use for lightning shape; re-prompt in a
  facility setting.
- **`VFX_..._red_warning_ring__3a59c63a..._1.png`** — Red AoE telegraph
  ring shape is correct; setting is library with candles + curtains +
  fireplace. Use for the ring SHAPE; re-prompt in a facility setting.
- **`VFX_..._large_blood_splat_a8b46a5a..._2.png`** — Industrial room
  with floor blood pool AND yellow energy column from ceiling. Two
  effects mashed — useful for both halves separately.

### MJ prompt-locking for VFX gens

```
[anchor URL = ba5d19c3]
Diablo 2 style isometric VFX frame, [EFFECT], hand-painted brush,
embedded in dark industrial cyberpunk facility, iso scene with
character at scale, painted texture
--sref [ba5d19c3 URL]
NOT gothic cathedral, NOT castle, NOT candles, NOT curtains,
NOT fantasy setting, NOT clean 3D render, NOT modern particle effects
```

`--sref ba5d19c3` is the new VFX anchor — it has the cleanest
industrial setting + most legible effect of the eight.

---

## Gaps to fill before vertical slice starts

| Asset class | Status | Target count | Notes |
|---|---|---|---|
| Environments | ✅ Locked | 13 | — |
| Characters | ✅ Locked | 7 | — |
| Monsters | ✅ Locked | 6 | — |
| UI / HUD | ✅ Locked | 3 | No-globes solution locked |
| Item icons | ✅ Locked | 11 | Painted-brush lane locked on `8953d79a` |
| VFX refs | ✅ Locked | 8 (5 strong + 3 marginal) | Anchor `ba5d19c3` for re-rolls |

**Bible status: complete.** Vertical slice planning can begin — every
asset class has a locked anchor reference for the AI render pipeline.
See `docs/2d-iso-pipeline.md` (TBD) for the production pipeline once
the pilot test ships.

### Item icon re-prompts (historical — kept for re-rolls)

These were the prompts used to fill the icon set. Most landed
on-bible; flagged ones drifted and may need re-rolls.

1. ✅ **Melee weapon — blade** (`melee_1h` archetype) → `9c062c43`
   ```
   Diablo 2 inventory item icon, futuristic combat knife with neon
   edge, gritty hand-painted brush style, isolated on solid dark
   background, body-horror cyberpunk, baked lighting
   ```
2. ✅ **Melee weapon — sledgehammer** (`melee_2h`) → `01c00396`
   ```
   Diablo 2 inventory item icon, heavy industrial sledgehammer with
   piston head, gritty hand-painted brush style, isolated on solid
   dark background, scrap-metal cyberpunk, baked lighting
   ```
3. ✅ **Body armor — chest piece** → `322b8dee`
   ```
   Diablo 2 inventory item icon, sci-fi armored chest plate with
   cyberware ports and exposed cabling, hand-painted brush style,
   isolated on solid dark background, body-horror cyberpunk
   ```
4. 🟡 **Helmet** → `ddee8728` (style drift — kept, may need re-roll)
   ```
   Diablo 2 inventory item icon, sci-fi combat helmet with glowing
   visor strip, hand-painted brush style, isolated on solid dark
   background, gritty neon noir
   ```
5. ✅ **Consumable — stimpack / battery** → `b071cbc2`
   ```
   Diablo 2 inventory item icon, sci-fi medical stimpack with red
   liquid and exposed wiring, hand-painted brush style, isolated
   on solid dark background, gritty bio-mechanical
   ```
6. ✅ **Chip / rune / socketable** → `60aeac2d`
   ```
   Diablo 2 inventory item icon, glowing sci-fi memory chip with
   etched circuitry, hand-painted brush style, isolated on solid
   dark background, neon-glowing, arcane circuit motif
   ```
7. ❌ **Re-do of `1bf54e31`** — Two attempts (`1a4caef0`, `db6188fc`)
   both drifted to tactical-comic-book style. Deleted. Painted-brush
   sniper rifle is still an open icon gap.

### VFX re-prompts (historical — kept for re-rolls)

All eight landed. Three drifted to gothic-fantasy settings (flagged
in the VFX section above).

1. ✅ **Plasma bolt impact** → `49056be5`
   ```
   Diablo 2 style isometric VFX frame, plasma bolt impacting a wall,
   red and orange light burst splash, hand-painted, embedded in dark
   industrial corridor, neon noir
   ```
2. ✅ **Muzzle flash** → `8e964d6b`
   ```
   Diablo 2 style isometric VFX frame, sci-fi weapon muzzle flash
   bright orange burst at character barrel, hand-painted, embedded
   in dark facility interior
   ```
3. ✅ **Melee swing impact** → `edcd8258`
   ```
   Diablo 2 style isometric VFX frame, blade slash impact with
   sparks and red blood splash, hand-painted, embedded in iso scene
   with character
   ```
4. ✅ **Explosion** → `ba5d19c3`
   ```
   Diablo 2 style isometric VFX frame, sci-fi grenade explosion with
   orange fireball and debris, hand-painted, embedded in industrial
   iso scene
   ```
5. 🟡 **Shock / electric burst** → `a84c4062` (gothic setting drift)
   ```
   Diablo 2 style isometric VFX frame, blue electric arc discharge
   between enemy and weapon, hand-painted, embedded in dark iso scene
   ```
6. ✅ **Heal / restore burst** → `37bbf4cb`
   ```
   Diablo 2 style isometric VFX frame, green healing particle burst
   around character, hand-painted, embedded in iso facility scene
   ```
7. 🟡 **Blood splatter — large** → `a8b46a5a` (mixed with energy column)
   ```
   Diablo 2 style isometric VFX frame, large blood splatter on iso
   floor tiles after enemy death, hand-painted, dark industrial
   setting, gore-heavy body horror
   ```
8. 🟡 **Boss attack telegraph / AoE ring** → `3a59c63a` (gothic setting)
   ```
   Diablo 2 style isometric VFX frame, red warning ring on floor
   tiles indicating incoming AoE attack, hand-painted, embedded in
   iso scene
   ```

All eight VFX prompts landed; three need facility-setting re-rolls
to fully nail the tone. Bible is complete — vertical slice planning
can begin.

---

## File naming pattern

All files share the prefix `Rathe001_` (Midjourney user identifier).
The descriptive segment after that captures the original prompt; UUID
+ index at the end disambiguates within a batch. Don't rename — the
URL pattern matters for re-referencing from Midjourney.

If a future bible needs a tag attached to a file (e.g., "this is the
locked anchor"), add a sidecar `.txt` rather than renaming the .png.
