# Art Reference Bible — Neurokore: Requiem (2D iso rework)

This folder is the visual-style lock for the 2D iso pivot. Every sprite
gen, every tile gen, every UI element should pass the "does it sit
cleanly next to these 24 images" test.

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

## Environments (11 images)

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

## Item icons (4 images)

**Lane decision pending.** The four icons split into two adjacent-but-
distinct stylistic camps:

| Image | Style | Best fit |
|---|---|---|
| `8953d79a` (red-barrel pistol) | Painted brush, illustrated | Painted lane |
| `1bf54e31` (sniper on heraldic book) | Painted brush, illustrated | Painted lane (bad framing — see note) |
| `041acdbb` (green sci-fi rifle) | Pixel-art with painted touches | Pixel-art lane |
| `18b094ab` (SMG with skull motif) | Pixel-art lean | Pixel-art lane |

### Recommended lane: painted brush

Anchors on `8953d79a` for continuity with the painted environment +
character bible. Closest to actual D2 inventory icons. Re-prompt the
pixel-art icons to match if going this route.

### `1bf54e31` framing note

The sniper rifle on the arcane book + red velvet backdrop is **painted
beautifully** but the heraldic backdrop is irrelevant for an inventory
icon. Re-prompt with `solid dark background, isolated weapon, no book,
no fabric, no backdrop` to keep the painting quality + remove the
framing baggage.

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

## Gaps to fill before vertical slice starts

| Asset class | Status | Target count | Notes |
|---|---|---|---|
| Environments | ✅ Locked | 11 | — |
| Characters | ✅ Locked | 7 | — |
| Monsters | ✅ Locked | 6 | — |
| UI / HUD | ✅ Locked | 3 (2 primary + 1 composition) | — |
| Item icons | 🟡 Partial | 4 (need 4-8 more for variety) | See re-prompts below |
| VFX refs | ❌ Missing | 6-8 needed | See re-prompts below |

### Item icon re-prompts (use `--sref` on `8953d79a`)

Target: 6-8 more icons covering the missing categories.

1. **Melee weapon — blade** (`melee_1h` archetype)
   ```
   Diablo 2 inventory item icon, futuristic combat knife with neon
   edge, gritty hand-painted brush style, isolated on solid dark
   background, body-horror cyberpunk, baked lighting
   ```
2. **Melee weapon — sledgehammer** (`melee_2h`)
   ```
   Diablo 2 inventory item icon, heavy industrial sledgehammer with
   piston head, gritty hand-painted brush style, isolated on solid
   dark background, scrap-metal cyberpunk, baked lighting
   ```
3. **Body armor — chest piece**
   ```
   Diablo 2 inventory item icon, sci-fi armored chest plate with
   cyberware ports and exposed cabling, hand-painted brush style,
   isolated on solid dark background, body-horror cyberpunk
   ```
4. **Helmet**
   ```
   Diablo 2 inventory item icon, sci-fi combat helmet with glowing
   visor strip, hand-painted brush style, isolated on solid dark
   background, gritty neon noir
   ```
5. **Consumable — stimpack / battery**
   ```
   Diablo 2 inventory item icon, sci-fi medical stimpack with red
   liquid and exposed wiring, hand-painted brush style, isolated
   on solid dark background, gritty bio-mechanical
   ```
6. **Chip / rune / socketable**
   ```
   Diablo 2 inventory item icon, glowing sci-fi memory chip with
   etched circuitry, hand-painted brush style, isolated on solid
   dark background, neon-glowing, arcane circuit motif
   ```
7. **Re-do of `1bf54e31`** — same sniper rifle, painted brush, NO
   heraldic backdrop, isolated on dark background only

### VFX re-prompts

Target: 6-8 reference frames for combat VFX. Painted aesthetic,
embedded in the iso environment (NOT isolated icons).

1. **Plasma bolt impact**
   ```
   Diablo 2 style isometric VFX frame, plasma bolt impacting a wall,
   red and orange light burst splash, hand-painted, embedded in dark
   industrial corridor, neon noir
   ```
2. **Muzzle flash**
   ```
   Diablo 2 style isometric VFX frame, sci-fi weapon muzzle flash
   bright orange burst at character barrel, hand-painted, embedded
   in dark facility interior
   ```
3. **Melee swing impact**
   ```
   Diablo 2 style isometric VFX frame, blade slash impact with
   sparks and red blood splash, hand-painted, embedded in iso scene
   with character
   ```
4. **Explosion**
   ```
   Diablo 2 style isometric VFX frame, sci-fi grenade explosion with
   orange fireball and debris, hand-painted, embedded in industrial
   iso scene
   ```
5. **Shock / electric burst** (taser / energy weapon)
   ```
   Diablo 2 style isometric VFX frame, blue electric arc discharge
   between enemy and weapon, hand-painted, embedded in dark iso scene
   ```
6. **Heal / restore burst** (consumable use)
   ```
   Diablo 2 style isometric VFX frame, green healing particle burst
   around character, hand-painted, embedded in iso facility scene
   ```
7. **Blood splatter — large**
   ```
   Diablo 2 style isometric VFX frame, large blood splatter on iso
   floor tiles after enemy death, hand-painted, dark industrial
   setting, gore-heavy body horror
   ```
8. **Boss attack telegraph / AoE ring**
   ```
   Diablo 2 style isometric VFX frame, red warning ring on floor
   tiles indicating incoming AoE attack, hand-painted, embedded in
   iso scene
   ```

Once item icons + VFX land, the bible is complete and the vertical
slice can be specced with real visual anchors for every asset class.

---

## File naming pattern

All files share the prefix `Rathe001_` (Midjourney user identifier).
The descriptive segment after that captures the original prompt; UUID
+ index at the end disambiguates within a batch. Don't rename — the
URL pattern matters for re-referencing from Midjourney.

If a future bible needs a tag attached to a file (e.g., "this is the
locked anchor"), add a sidecar `.txt` rather than renaming the .png.
